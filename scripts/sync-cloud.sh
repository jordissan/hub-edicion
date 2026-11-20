#!/bin/bash
# ─────────────────────────────────────────────────────────────────────────────
# Porta lo LOCAL (fuente de verdad) a la copia de la NUBE (cloud/ = repo público en GitHub).
#
#   ./sync-cloud.sh                      → copia y muestra qué cambió (no publica)
#   ./sync-cloud.sh --publicar "mensaje" → además commit + push (Cloudflare Pages
#                                          despliega solo) y, si cambió server.py,
#                                          republica los datos (workflow de Actions)
#
# Qué copia:
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
# ─────────────────────────────────────────────────────────────────────────────
set -euo pipefail
cd "$(dirname "$0")"
CLOUD="${HUB_CLOUD_DIR:-cloud}"   # (solo para pruebas se puede apuntar a otra copia)

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
)

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
git -C "$CLOUD" diff --quiet HEAD -- server.py || server_changed=1

echo "→ Cambios en $CLOUD/:"
git -C "$CLOUD" status --short
git -C "$CLOUD" diff --stat | tail -1

# 4) publicar (solo si se pide)
if [ "${1:-}" = "--publicar" ]; then
  msg="${2:?Falta el mensaje del commit: ./sync-cloud.sh --publicar \"mensaje\"}"
  if [ -z "$(git -C "$CLOUD" status --porcelain)" ]; then
    echo "✓ Nada que publicar."; exit 0
  fi
  git -C "$CLOUD" add -A
  git -C "$CLOUD" commit -q -m "$msg"
  # otra sesión (por ejemplo, un pendiente guardado desde el teléfono) pudo subir cambios a main
  if ! git -C "$CLOUD" pull -q --rebase origin main; then
    git -C "$CLOUD" rebase --abort 2>/dev/null || true
    echo "✗ No se pudo combinar con lo último de GitHub. Tu commit quedó guardado en $CLOUD/, SIN publicar."
    exit 1
  fi
  git -C "$CLOUD" push -q origin main
  echo "✓ Publicado: $(git -C "$CLOUD" log --oneline -1) — Cloudflare Pages despliega en ~1-2 min."
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
