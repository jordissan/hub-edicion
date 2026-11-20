#!/bin/zsh
# Compila "Sprint flotante" y lo instala en ~/Applications (registra hubsprint://).
# Solo necesita las Command Line Tools (swiftc), no Xcode.
set -e
cd "$(dirname "$0")"
APP="$HOME/Applications/Sprint flotante.app"
BUILD="$(mktemp -d)"

mkdir -p "$BUILD/Sprint flotante.app/Contents/MacOS" "$BUILD/Sprint flotante.app/Contents/Resources"
# -target: sin él swiftc apunta al SDK (puede ser un macOS más nuevo que el instalado y la app
# no abre: error -10825). Igual que LSMinimumSystemVersion del Info.plist.
swiftc -O -target "$(uname -m)-apple-macos13.0" -o "$BUILD/Sprint flotante.app/Contents/MacOS/SprintFlotante" main.swift \
  -framework Cocoa -framework WebKit -framework ServiceManagement -framework Network
cp Info.plist "$BUILD/Sprint flotante.app/Contents/Info.plist"

# icono: el mismo del Hub
ICON_SRC="../../icon-512.png"
if [[ -f "$ICON_SRC" ]]; then
  SET="$BUILD/AppIcon.iconset"; mkdir -p "$SET"
  for s in 16 32 128 256 512; do
    sips -z $s $s "$ICON_SRC" --out "$SET/icon_${s}x${s}.png" >/dev/null
    d=$((s*2)); [[ $d -le 512 ]] && sips -z $d $d "$ICON_SRC" --out "$SET/icon_${s}x${s}@2x.png" >/dev/null
  done
  iconutil -c icns "$SET" -o "$BUILD/Sprint flotante.app/Contents/Resources/AppIcon.icns"
fi

codesign --force --deep -s - "$BUILD/Sprint flotante.app"

# reemplaza la instalada (si está abierta, ciérrala primero)
pkill -x SprintFlotante 2>/dev/null || true
mkdir -p "$HOME/Applications"
rm -rf "$APP"
mv "$BUILD/Sprint flotante.app" "$APP"
rm -rf "$BUILD"
/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister -f "$APP"
echo "Instalada: $APP"
