#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BUILD_CONFIG="${1:-release}"
APP_NAME="Wired Bot"
APP_EXECUTABLE="WiredBotApp"
BOT_EXECUTABLE="WiredBot"
BUNDLE_ID="fr.read-write.WiredBot"
MARKETING_VERSION="${WIRED_BOT_MARKETING_VERSION:-1.0}"
BUILD_NUMBER="${WIRED_BOT_BUILD_NUMBER:-1}"
APP_DIR="$ROOT_DIR/dist/${APP_NAME}.app"
CONTENTS_DIR="$APP_DIR/Contents"
MACOS_DIR="$CONTENTS_DIR/MacOS"
RESOURCES_DIR="$CONTENTS_DIR/Resources"
INFO_PLIST="$CONTENTS_DIR/Info.plist"
ICON_SOURCE="$ROOT_DIR/Assets/bot-icon.png"
ICONSET_DIR="$ROOT_DIR/dist/WiredBot.iconset"
ICON_FILE="$RESOURCES_DIR/WiredBot.icns"

if [[ "$BUILD_CONFIG" != "debug" && "$BUILD_CONFIG" != "release" ]]; then
  echo "Usage: $0 [debug|release]"
  exit 1
fi

cd "$ROOT_DIR"

echo "==> Building $APP_EXECUTABLE ($BUILD_CONFIG)"
swift build -c "$BUILD_CONFIG" --product "$APP_EXECUTABLE"

echo "==> Building $BOT_EXECUTABLE ($BUILD_CONFIG)"
swift build -c "$BUILD_CONFIG" --product "$BOT_EXECUTABLE"

BUILD_DIR="$ROOT_DIR/.build/$BUILD_CONFIG"
APP_BINARY="$BUILD_DIR/$APP_EXECUTABLE"
BOT_BINARY="$BUILD_DIR/$BOT_EXECUTABLE"
WIRED_XML="$ROOT_DIR/.build/checkouts/WiredSwift/Sources/WiredSwift/Resources/wired.xml"

if [[ ! -x "$APP_BINARY" ]]; then
  echo "Missing app executable: $APP_BINARY" >&2
  exit 1
fi
if [[ ! -x "$BOT_BINARY" ]]; then
  echo "Missing bot executable: $BOT_BINARY" >&2
  exit 1
fi
if [[ ! -f "$WIRED_XML" ]]; then
  echo "Missing wired.xml: $WIRED_XML" >&2
  exit 1
fi
if [[ ! -f "$ICON_SOURCE" ]]; then
  echo "Missing icon source: $ICON_SOURCE" >&2
  exit 1
fi

echo "==> Creating app bundle at $APP_DIR"
rm -rf "$APP_DIR"
mkdir -p "$MACOS_DIR" "$RESOURCES_DIR"

cp "$APP_BINARY" "$MACOS_DIR/$APP_EXECUTABLE"
chmod 755 "$MACOS_DIR/$APP_EXECUTABLE"

cp "$BOT_BINARY" "$RESOURCES_DIR/wiredbot"
chmod 755 "$RESOURCES_DIR/wiredbot"

cp "$WIRED_XML" "$RESOURCES_DIR/wired.xml"

echo "==> Creating app icon"
rm -rf "$ICONSET_DIR"
mkdir -p "$ICONSET_DIR"
sips -z 16 16 "$ICON_SOURCE" --out "$ICONSET_DIR/icon_16x16.png" >/dev/null
sips -z 32 32 "$ICON_SOURCE" --out "$ICONSET_DIR/icon_16x16@2x.png" >/dev/null
sips -z 32 32 "$ICON_SOURCE" --out "$ICONSET_DIR/icon_32x32.png" >/dev/null
sips -z 64 64 "$ICON_SOURCE" --out "$ICONSET_DIR/icon_32x32@2x.png" >/dev/null
sips -z 128 128 "$ICON_SOURCE" --out "$ICONSET_DIR/icon_128x128.png" >/dev/null
sips -z 256 256 "$ICON_SOURCE" --out "$ICONSET_DIR/icon_128x128@2x.png" >/dev/null
sips -z 256 256 "$ICON_SOURCE" --out "$ICONSET_DIR/icon_256x256.png" >/dev/null
sips -z 512 512 "$ICON_SOURCE" --out "$ICONSET_DIR/icon_256x256@2x.png" >/dev/null
sips -z 512 512 "$ICON_SOURCE" --out "$ICONSET_DIR/icon_512x512.png" >/dev/null
iconutil -c icns "$ICONSET_DIR" -o "$ICON_FILE"
rm -rf "$ICONSET_DIR"

echo "==> Copying SwiftPM resource bundles"
shopt -s nullglob
for bundle in "$BUILD_DIR"/*.bundle; do
  cp -R "$bundle" "$RESOURCES_DIR/"
done
shopt -u nullglob

cat > "$INFO_PLIST" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleDevelopmentRegion</key>
  <string>en</string>
  <key>CFBundleExecutable</key>
  <string>$APP_EXECUTABLE</string>
  <key>CFBundleIdentifier</key>
  <string>$BUNDLE_ID</string>
  <key>CFBundleInfoDictionaryVersion</key>
  <string>6.0</string>
  <key>CFBundleName</key>
  <string>$APP_NAME</string>
  <key>CFBundleDisplayName</key>
  <string>$APP_NAME</string>
  <key>CFBundleIconFile</key>
  <string>WiredBot</string>
  <key>CFBundlePackageType</key>
  <string>APPL</string>
  <key>CFBundleShortVersionString</key>
  <string>$MARKETING_VERSION</string>
  <key>CFBundleVersion</key>
  <string>$BUILD_NUMBER</string>
  <key>LSMinimumSystemVersion</key>
  <string>13.0</string>
  <key>LSUIElement</key>
  <true/>
  <key>NSHighResolutionCapable</key>
  <true/>
</dict>
</plist>
PLIST

echo "==> Ad-hoc signing"
codesign --force --sign - "$RESOURCES_DIR/wiredbot"
codesign --force --deep --sign - "$APP_DIR"

echo "==> Done: $APP_DIR"
