#!/bin/bash
# Doble clic para iniciar el Hub de Edición (puente local + dashboard).
cd "$(dirname "$0")"

abrir_app() {
  # Abre la web app del Dock; si no existe, cae al navegador
  open -a "Hub de Edición" 2>/dev/null || open "http://localhost:4599"
}

# Si el servidor ya corre (p. ej. vía launchd), solo abre la app y listo.
if lsof -nP -iTCP:4599 -sTCP:LISTEN >/dev/null 2>&1; then
  echo "✓  El servidor ya está corriendo — abriendo la app…"
  abrir_app
  sleep 1
  exit 0
fi

if [ ! -f "$HOME/.notion-dashboard-token" ] && [ -z "$NOTION_TOKEN" ]; then
  echo ""
  echo "⚠  Falta el token de Notion."
  echo "   Sigue los pasos del README (sección «Configurar el token») y vuelve a abrir esto."
  echo ""
  read -n 1 -s -r -p "Presiona cualquier tecla para cerrar…"
  exit 1
fi

# Mata cualquier instancia huérfana previa (sin puerto, pero viva)
OLD=$(pgrep -f "[s]erver.py")
if [ -n "$OLD" ]; then
  echo "↻  Deteniendo instancia previa ($OLD)…"
  kill $OLD 2>/dev/null
  sleep 1
fi

echo "▶  Iniciando Hub de Edición…"
echo "✓  Dashboard: http://localhost:4599"
echo "   Deja esta ventana abierta mientras lo usas. Ciérrala para detener el servidor."
echo ""

( sleep 1.5; abrir_app ) &

# exec en PRIMER PLANO: al cerrar esta ventana, el servidor muere con ella (sin huérfanos)
exec /usr/bin/python3 server.py
