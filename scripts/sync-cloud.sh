#!/bin/bash
# ─────────────────────────────────────────────────────────────────────────────
# Sincroniza las dos carpetas de la Mac con GitHub, en los dos sentidos.
#
#   ./sync-cloud.sh --traer              → GitHub → Mac (lo corre solo el LaunchAgent
#                                          com.jordi.hub-edicion.sync cada 15 min y al iniciar sesión)
#   ./sync-cloud.sh                      → Mac → cloud/: copia y muestra qué cambió (no publica)
#   ./sync-cloud.sh --publicar "mensaje" → además commit + push (Cloudflare Pages
#                                          despliega solo) y, si cambió server.py,
#                                          republica los datos (workflow de Actions)
#   (--forzar, antes de lo demás, publica aunque haya cambios de GitHub sin traer: los pisa)
#
# GitHub → Mac (--traer, y siempre antes de copiar):
#   1. cloud/ (el clon) se pone al día con `git merge --ff-only`. Si cloud/ tiene cambios a mano,
#      commits sin subir o divergió de GitHub, avisa y NO toca nada.
#   2. Si en GitHub cambió algo que nace en la Mac (por ejemplo, un PR de index.html ya
#      mergeado), lo trae a ~/HubEdicion SOLO si la copia local no se tocó desde la última
#      sincronización (es idéntica a la versión anterior del repo). Así nunca se pierde nada.
#   3. Lo que no puede traer solo (la copia local también cambió, o el repo lleva nombres de
#      ejemplo, como los .md) lo lista con una notificación y bloquea la publicación hasta que
#      se traiga a mano. Sin esto, la siguiente publicación desharía en silencio el cambio de GitHub.
#   Estado en .sync-base (último commit que la Mac ya refleja) y .sync-estado (última corrida).
#
# Mac → cloud/ (qué copia):
#   · tal cual:  index.html, server.py, fonts/ (el dashboard que se despliega)
#   · con limpieza de privacidad (nombres reales → de ejemplo, montos → $XX,XXX):
#       docs/ (lo que ayuda a mantener el sistema), README.md → docs/guia-de-uso.md,
#       mac/ (app del sprint + atajos de Siri), widgets/ (Scriptable + SwiftBar),
#       y las herramientas de la raíz → scripts/
#   La lista exacta está abajo (ARCHIVOS). Lo que NO sube y por qué: docs/solo-en-la-mac.md.
# Antes de dar nada por bueno, privacidad.py revisa TODO el repo: si ve una llave real, un
# correo, un ID o un nombre real de pareja/estudio, se detiene sin publicar.
# publish.py, functions/, embed/ y pendientes/ viven solo en cloud/ y se editan ahí.
# Detalle del flujo: docs/arquitectura.md → "Mantenimiento".
# Compatible con el bash 3.2 de macOS (sin arreglos asociativos).
# ─────────────────────────────────────────────────────────────────────────────
set -euo pipefail
cd "$(dirname "$0")"
CLOUD="${HUB_CLOUD_DIR:-cloud}"   # (solo para pruebas se puede apuntar a otra copia)
NOTIFICAR="${HUB_NOTIFICAR:-1}"   # 0 = sin notificaciones de macOS (pruebas)

# local → repo (con limpieza). Las rutas del repo son las mismas salvo las de la raíz.
ARCHIVOS=(
  "docs/arquitectura.md:docs/arquitectura.md"
  "docs/arquitectura-unificada-analisis.md:docs/arquitectura-unificada-analisis.md"
  "docs/atajo-modo-oscuro.md:docs/atajo-modo-oscuro.md"
  "docs/migracion-swiftui.md:docs/migracion-swiftui.md"
  "docs/solo-en-la-mac.md:docs/solo-en-la-mac.md"
  "docs/propuestas/auditoria-diseno-2026-11-10.md:docs/propuestas/auditoria-diseno-2026-11-10.md"
  "docs/propuestas/trazo/snap.swift:docs/propuestas/trazo/snap.swift"
  "README.md:docs/guia-de-uso.md"
  "mac/SprintFlotante/main.swift:mac/SprintFlotante/main.swift"
  "mac/SprintFlotante/build.sh:mac/SprintFlotante/build.sh"
  "mac/SprintFlotante/Info.plist:mac/SprintFlotante/Info.plist"
  "mac/Siri/make-shortcuts.py:mac/Siri/make-shortcuts.py"
  "widgets/README.md:widgets/README.md"
  "widgets/HubEdicion.scriptable.js:widgets/HubEdicion.scriptable.js"
  "widgets/HubEdicion-dona.scriptable.js:widgets/HubEdicion-dona.scriptable.js"
  "widgets/Dark Mode (global).js:widgets/Dark Mode (global).js"
  "widgets/hubedicion.5m.py:widgets/hubedicion.5m.py"
  "widgets/atajo/make-atajo.py:widgets/atajo/make-atajo.py"
  "sync-cloud.sh:scripts/sync-cloud.sh"
  "privacidad.py:scripts/privacidad.py"
  "snapshot-demo.py:scripts/snapshot-demo.py"
  "start.command:scripts/start.command"
  "com.jordi.hub-edicion.plist:scripts/com.jordi.hub-edicion.plist"
  "com.jordi.hub-edicion.sync.plist:scripts/com.jordi.hub-edicion.sync.plist"
)

BASE=.sync-base       # último commit de cloud/ que ~/HubEdicion ya refleja
ESTADO=.sync-estado   # una línea: fecha · resultado de la última corrida (para SwiftBar, etc.)
AVISADO=.sync-avisado # último aviso mostrado, para no repetir la misma notificación cada 15 min
CANDADO=.sync.lock

g() { git -C "$CLOUD" "$@"; }

aviso() {   # aviso "título" "detalle": a la terminal siempre; notificación solo si es nuevo
  echo "$1${2:+ — $2}"
  printf '%s · %s%s\n' "$(date '+%Y-%m-%d %H:%M')" "$1" "${2:+ — $2}" > "$ESTADO"
  local clave="$1|${2:-}"
  if [ "$NOTIFICAR" = 1 ] && [ "$(cat "$AVISADO" 2>/dev/null)" != "$clave" ]; then
    printf '%s' "$clave" > "$AVISADO"
    local t="${1//\"/\'}" d="${2//\"/\'}"
    osascript -e "display notification \"$d\" with title \"Hub de Edición\" subtitle \"$t\"" \
      >/dev/null 2>&1 || true
  fi
}
listo() {   # todo en orden: se registra, sin notificación (y se olvida el último aviso)
  printf '%s · %s\n' "$(date '+%Y-%m-%d %H:%M')" "$1" > "$ESTADO"; rm -f "$AVISADO"
  [ -n "${CALLADO:-}" ] || echo "$1"
}

# ruta del repo → ruta local ("" si no nace en la Mac)
origen_local() {
  case "$1" in
    index.html|server.py|fonts/*.woff2) echo "$1"; return ;;
  esac
  local par
  for par in "${ARCHIVOS[@]}"; do
    [ "${par#*:}" = "$1" ] && { echo "${par%%:*}"; return; }
  done
  echo ""
}
copia_tal_cual() { case "$1" in index.html|server.py|fonts/*) return 0 ;; *) return 1 ;; esac; }

# ¿el archivo local $1 es idéntico a <rev>:<ruta del repo>?
igual_a_rev() { g cat-file -e "$2:$3" 2>/dev/null && cmp -s "$1" <(g show "$2:$3"); }
# ¿el archivo local $1, pasado por la limpieza de privacidad, ya da <rev>:<ruta del repo>?
limpio_igual_a_rev() {
  copia_tal_cual "$3" && { igual_a_rev "$@"; return; }
  local tmp; tmp="$(mktemp -d)"
  python3 privacidad.py copiar "$1" "$tmp" "$3" >/dev/null 2>&1 \
    && g cat-file -e "$2:$3" 2>/dev/null && cmp -s "$tmp/$3" <(g show "$2:$3")
  local r=$?; rm -rf "$tmp"; return $r
}

# GitHub → Mac. Sale 0 = al día · 2 = hay cosas de GitHub por traer a mano · 1 = bloqueado.
traer() {
  local rama; rama="$(g rev-parse --abbrev-ref HEAD)"
  if [ "$rama" != main ]; then
    aviso "cloud/ no está en main" "está en «$rama»: no se toca nada"; return 1
  fi
  if ! g fetch -q origin main 2>/dev/null; then
    listo "Sin conexión con GitHub; se reintenta en la próxima corrida."; return 0
  fi
  if [ -n "$(g status --porcelain)" ]; then
    aviso "cloud/ tiene cambios sin publicar" "publica con sync-cloud.sh --publicar o descártalos"
    return 1
  fi
  local adelante atras
  adelante="$(g rev-list --count origin/main..HEAD)"; atras="$(g rev-list --count HEAD..origin/main)"
  if [ "$adelante" -gt 0 ] && [ "$atras" -gt 0 ]; then
    aviso "cloud/ y GitHub divergieron" "$adelante commit(s) locales y $atras nuevos en GitHub; no se toca nada"
    return 1
  fi
  if [ "$adelante" -gt 0 ]; then
    aviso "cloud/ tiene $adelante commit(s) sin subir" "revisa y haz push; no se toca nada"; return 1
  fi
  local antes; antes="$(g rev-parse HEAD)"
  [ "$atras" -gt 0 ] && g merge -q --ff-only origin/main
  local ahora; ahora="$(g rev-parse HEAD)"

  # primera vez: se asume que la Mac reflejaba lo que había en cloud/ antes de traer
  local base; base="$(cat "$BASE" 2>/dev/null || true)"
  if [ -z "$base" ] || ! g cat-file -e "$base^{commit}" 2>/dev/null; then
    base="$antes"; echo "$base" > "$BASE"
  fi

  local traidos=() pendientes=() server=0 app=0 widgets=0 ruta src
  while IFS= read -r ruta; do
    [ -n "$ruta" ] || continue
    src="$(origen_local "$ruta")"; [ -n "$src" ] || continue      # vive solo en el repo
    if [ -f "$src" ] && limpio_igual_a_rev "$src" "$ahora" "$ruta"; then
      continue                                                       # la Mac ya lo tiene
    fi
    local intacto=0   # ¿la copia local sigue como quedó en la última sincronización?
    if [ -f "$src" ]; then igual_a_rev "$src" "$base" "$ruta" && intacto=1
    elif [ ! -e "$src" ] && ! g cat-file -e "$base:$ruta" 2>/dev/null; then intacto=1; fi
    if [ "$intacto" = 1 ] && g cat-file -e "$ahora:$ruta" 2>/dev/null; then
      # la copia local no se tocó desde la última sincronización: traerlo no pierde nada
      mkdir -p "$(dirname "$src")"
      [ -f "$src" ] && cp "$src" "$src.sync-tmp"     # (así conserva los permisos)
      g show "$ahora:$ruta" > "$src.sync-tmp"
      mv "$src.sync-tmp" "$src"
      traidos+=("$src")
      case "$src" in server.py) server=1 ;; mac/*) app=1 ;; widgets/*) widgets=1 ;; esac
    else
      pendientes+=("$src")
    fi
  done < <(g diff --name-only "$base" "$ahora")

  if [ "${#traidos[@]}" -gt 0 ]; then
    local extra=""
    [ "$server" = 1 ] && launchctl kickstart -k "gui/$(id -u)/com.jordi.hub-edicion" 2>/dev/null \
      && extra="$extra Servidor local reiniciado."
    [ "$app" = 1 ] && extra="$extra Recompila la app: mac/SprintFlotante/build.sh."
    [ "$widgets" = 1 ] && extra="$extra Los widgets del iPhone se actualizan a mano en Scriptable."
    aviso "Traído de GitHub: ${#traidos[@]} archivo(s)" "${traidos[*]}.$extra"
  fi
  if [ "${#pendientes[@]}" -gt 0 ]; then
    aviso "Cambios de GitHub por traer a mano" "${pendientes[*]} (la copia local también cambió o lleva nombres reales). sync-cloud.sh no publica hasta que se traigan."
    return 2
  fi
  echo "$ahora" > "$BASE"
  if [ "${#traidos[@]}" -eq 0 ]; then
    if [ "$antes" != "$ahora" ]; then listo "Al día con GitHub (${ahora:0:7}); nada de la Mac cambió."
    else listo "Al día con GitHub (${ahora:0:7})."; fi
  fi
  return 0
}

# un solo sync a la vez (el LaunchAgent y una publicación a mano no deben cruzarse)
if ! mkdir "$CANDADO" 2>/dev/null; then
  if [ -n "$(find "$CANDADO" -maxdepth 0 -mmin +10 2>/dev/null)" ]; then
    rm -rf "$CANDADO"; mkdir "$CANDADO"
  else
    echo "Otro sync está corriendo; inténtalo en un momento."; exit 0
  fi
fi
trap 'rm -rf "$CANDADO"' EXIT

FORZAR=0
[ "${1:-}" = "--forzar" ] && { FORZAR=1; shift; }

if [ "${1:-}" = "--traer" ]; then
  [ "${2:-}" = "--callado" ] && CALLADO=1
  r=0; traer || r=$?
  exit "$r"
fi

# 0) lo último de GitHub primero. Lo que cloud/ tenga sin commit en archivos que nacen en la Mac
#    es una vista previa de una corrida anterior: se descarta, porque se vuelve a copiar ahora.
while IFS= read -r ruta; do
  [ -n "$(origen_local "$ruta")" ] && g checkout -q -- "$ruta"
done < <(g diff --name-only HEAD)
while IFS= read -r ruta; do
  [ -n "$(origen_local "$ruta")" ] && rm -f "$CLOUD/$ruta"
done < <(g ls-files --others --exclude-standard)
r=0; traer || r=$?
if [ "$r" = 1 ]; then echo "✗ No se copia nada hasta resolver lo de arriba."; exit 1; fi
if [ "$r" = 2 ] && [ "$FORZAR" = 0 ]; then
  echo "✗ No se copia nada: GitHub tiene cambios de esos archivos que la Mac no tiene y se perderían."
  echo "  Pásalos a mano a ~/HubEdicion (git -C $CLOUD log -p -- <ruta del repo> muestra qué cambió)"
  echo "  y vuelve a correr. Para pisarlos con lo local: ./sync-cloud.sh --forzar [--publicar …]"
  exit 1
fi

# 1) validar antes de copiar
python3 -c "import ast,sys; ast.parse(open('server.py').read())" \
  || { echo "✗ server.py tiene un error de sintaxis — no se copia nada."; exit 1; }
grep -q 'window.SNAPSHOT_DATA' index.html \
  || { echo "✗ index.html sin SNAPSHOT_DATA (¿archivo truncado?) — no se copia nada."; exit 1; }
# el repo de la nube es público: el snapshot embebido debe ser el de ejemplo (marca "demo":true)
grep -q 'window.SNAPSHOT_DATA = {.*"demo":true' index.html \
  || { echo "✗ El snapshot embebido no es el de ejemplo — corre ./snapshot-demo.py y vuelve a intentar."; exit 1; }

# 2) copiar
cp index.html "$CLOUD/index.html"
cp server.py "$CLOUD/server.py"
mkdir -p "$CLOUD/fonts" && cp fonts/*.woff2 "$CLOUD/fonts/"
for par in "${ARCHIVOS[@]}"; do
  src="${par%%:*}"; dst="${par#*:}"
  [ -f "$src" ] || { echo "  (falta $src — se salta)"; continue; }
  python3 privacidad.py copiar "$src" "$CLOUD" "$dst"
done

# 3) revisión de privacidad de TODO lo que git subiría (lo copiado y lo que vive solo en cloud/)
python3 privacidad.py revisar "$CLOUD" \
  || { echo "✗ No se publica nada. Corrige lo de arriba (o añade el nombre a .privacidad.json → extra)."; exit 1; }

# server.py cambió respecto a lo PUBLICADO (último commit) → hay que republicar los datos
server_changed=0
g diff --quiet HEAD -- server.py || server_changed=1

echo "→ Cambios en $CLOUD/:"
g status --short
g diff --stat | tail -1

# 4) publicar (solo si se pide)
if [ "${1:-}" = "--publicar" ]; then
  msg="${2:?Falta el mensaje del commit: ./sync-cloud.sh --publicar \"mensaje\"}"
  if [ -z "$(g status --porcelain)" ]; then
    echo "✓ Nada que publicar."; g rev-parse HEAD > "$BASE"; exit 0
  fi
  g add -A
  g commit -q -m "$msg"
  # otra sesión (por ejemplo, un pendiente guardado desde el teléfono) pudo subir cambios a main
  if ! g pull -q --rebase origin main; then
    g rebase --abort 2>/dev/null || true
    echo "✗ No se pudo combinar con lo último de GitHub. Tu commit quedó guardado en $CLOUD/, SIN publicar."
    exit 1
  fi
  g push -q origin main
  g rev-parse HEAD > "$BASE"   # lo publicado sale de la Mac: la Mac ya lo refleja
  listo "Publicado: $(g log --oneline -1)"
  echo "✓ Publicado: $(g log --oneline -1) — Cloudflare Pages despliega en ~1-2 min."
  if [ "$server_changed" = 1 ]; then
    (cd "$CLOUD" && gh workflow run publish.yml) && echo "✓ server.py cambió: republicando datos (Actions, ~2-4 min)."
  fi
  # el servidor local también debe recargar server.py
  if [ "$server_changed" = 1 ]; then
    launchctl kickstart -k "gui/$(id -u)/com.jordi.hub-edicion" 2>/dev/null && echo "✓ Servidor local reiniciado."
  fi
else
  echo "(sin publicar — revisa el diff y luego: ./sync-cloud.sh --publicar \"mensaje\")"
fi
