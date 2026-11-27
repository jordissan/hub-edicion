#!/bin/bash
# ─────────────────────────────────────────────────────────────────────────────
# Publica lo LOCAL (fuente de verdad: ~/HubEdicion) en la copia de la NUBE (cloud/ = repo
# público en GitHub). Se trabaja primero aquí, en la Mac; GitHub y Cloudflare solo reciben.
#
#   ./sync-cloud.sh                      → copia y muestra qué cambió (no publica)
#   ./sync-cloud.sh --publicar "mensaje" → además commit + push (Cloudflare Pages
#                                          despliega solo) y, si cambió server.py,
#                                          republica los datos (workflow de Actions)
#   (--forzar, antes de lo demás, publica aunque GitHub tenga cambios de archivos de la Mac
#    que no salieron de aquí: los pisa con lo local)
#
# Freno antes de copiar: cloud/ se pone al día con GitHub (solo fast-forward). Si en GitHub hay
# cambios de archivos que nacen en la Mac y no salieron de aquí (por ejemplo, alguien editó en
# github.com), se detiene: publicar los desharía en silencio. Lo que vive solo en cloud/
# (pendientes/, CLAUDE.md, README.md, publish.py, functions/, embed/) se edita en cloud/ y sale
# con la misma publicación.
#
# Mac → cloud/ (qué copia):
#   · tal cual:  index.html, server.py, fonts/ (el dashboard que se despliega)
#   · con limpieza de privacidad (nombres reales → de ejemplo, montos → $XX,XXX):
#       docs/ (lo que ayuda a mantener el sistema), README.md → docs/guia-de-uso.md,
#       mac/ (app del sprint + atajos de Siri), widgets/ (Scriptable + SwiftBar),
#       y las herramientas de la raíz → scripts/
#   La lista exacta está abajo (ARCHIVOS). Lo que NO sube y por qué: docs/solo-en-la-mac.md.
# Antes de dar nada por bueno, privacidad.py revisa TODO el repo: si ve una llave real, un
# correo, un ID o un nombre real de pareja/estudio, se detiene sin publicar. El hook pre-push
# de cloud/ corre la misma revisión ante cualquier `git push`, aunque sea a mano.
# Detalle del flujo: docs/arquitectura.md → "Mantenimiento".
# Compatible con el bash 3.2 de macOS (sin arreglos asociativos).
# ─────────────────────────────────────────────────────────────────────────────
set -euo pipefail
cd "$(dirname "$0")"
CLOUD="${HUB_CLOUD_DIR:-cloud}"   # (solo para pruebas se puede apuntar a otra copia)

# local → repo (con limpieza). Las rutas del repo son las mismas salvo las de la raíz.
ARCHIVOS=(
  "docs/arquitectura.md:docs/arquitectura.md"
  "docs/arquitectura-unificada-analisis.md:docs/arquitectura-unificada-analisis.md"
  "docs/atajo-modo-oscuro.md:docs/atajo-modo-oscuro.md"
  "docs/diseno.md:docs/diseno.md"
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
)

CANDADO=.sync.lock
g() { git -C "$CLOUD" "$@"; }

# ruta del repo → ruta local ("" si vive solo en el repo)
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

# Freno: cloud/ al día con GitHub sin perder nada. Sale 0 = seguir · 1 = detenerse.
freno() {
  local rama; rama="$(g rev-parse --abbrev-ref HEAD)"
  if [ "$rama" != main ]; then
    echo "✗ cloud/ está en la rama «$rama», no en main. Regrésalo con: git -C $CLOUD checkout main"; return 1
  fi
  if ! g fetch -q origin main 2>/dev/null; then
    echo "  (sin conexión con GitHub: se copia, pero publicar fallará hasta que vuelva)"; return 0
  fi
  local adelante atras
  adelante="$(g rev-list --count origin/main..HEAD)"; atras="$(g rev-list --count HEAD..origin/main)"
  [ "$atras" -eq 0 ] && return 0
  if [ "$adelante" -gt 0 ]; then
    echo "✗ cloud/ y GitHub divergieron ($adelante commit(s) locales y $atras nuevos en GitHub). Revisa con:"
    echo "  git -C $CLOUD log --oneline --left-right HEAD...origin/main"; return 1
  fi
  local ajenos=() ruta
  while IFS= read -r ruta; do
    [ -n "$ruta" ] && [ -n "$(origen_local "$ruta")" ] && ajenos+=("$ruta")
  done < <(g diff --name-only HEAD origin/main)
  if [ "${#ajenos[@]}" -gt 0 ] && [ "$FORZAR" = 0 ]; then
    echo "✗ GitHub tiene cambios que no salieron de esta Mac: ${ajenos[*]}"
    echo "  Publicar los desharía. Pásalos a mano a ~/HubEdicion (git -C $CLOUD log -p HEAD..origin/main)"
    echo "  y vuelve a correr. Para pisarlos con lo local: ./sync-cloud.sh --forzar [--publicar …]"
    return 1
  fi
  if ! g merge -q --ff-only origin/main 2>/dev/null; then
    echo "✗ No se pudo poner cloud/ al día (¿cambios sin commit que chocan?). Revisa: git -C $CLOUD status"; return 1
  fi
  echo "  cloud/ al día con GitHub ($(g rev-parse --short HEAD))."
  return 0
}

# un solo sync a la vez
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

# 0) lo que cloud/ tenga sin commit en archivos que nacen en la Mac es una vista previa de una
#    corrida anterior: se descarta, porque se vuelve a copiar ahora. Luego, el freno.
while IFS= read -r ruta; do
  [ -n "$(origen_local "$ruta")" ] && g checkout -q -- "$ruta"
done < <(g diff --name-only HEAD)
while IFS= read -r ruta; do
  [ -n "$(origen_local "$ruta")" ] && rm -f "$CLOUD/$ruta"
done < <(g ls-files --others --exclude-standard)
freno || { echo "✗ No se copia nada hasta resolver lo de arriba."; exit 1; }

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
    echo "✓ Nada que publicar."; exit 0
  fi
  g add -A
  g commit -q -m "$msg"
  # por si GitHub cambió mientras tanto (el freno ya revisó lo de antes)
  if ! g pull -q --rebase origin main; then
    g rebase --abort 2>/dev/null || true
    echo "✗ No se pudo combinar con lo último de GitHub. Tu commit quedó guardado en $CLOUD/, SIN publicar."
    exit 1
  fi
  g push -q origin main
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
