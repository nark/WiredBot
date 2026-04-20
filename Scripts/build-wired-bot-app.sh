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
GIT_COMMIT="${WIRED_BOT_GIT_COMMIT:-unknown}"
APP_DIR="$ROOT_DIR/dist/${APP_NAME}.app"
CONTENTS_DIR="$APP_DIR/Contents"
MACOS_DIR="$CONTENTS_DIR/MacOS"
RESOURCES_DIR="$CONTENTS_DIR/Resources"
INFO_PLIST="$CONTENTS_DIR/Info.plist"
ICON_SOURCE="$ROOT_DIR/Assets/bot-icon.png"
ICONSET_DIR="$ROOT_DIR/dist/WiredBot.iconset"
ICON_FILE="$RESOURCES_DIR/WiredBot.icns"
APP_ZIP_PATH="$ROOT_DIR/dist/Wired-Bot.app.zip"
NOTARIZE="${NOTARIZE:-}"
NOTARY_PROFILE="${NOTARY_PROFILE:-}"

if [[ "$BUILD_CONFIG" != "debug" && "$BUILD_CONFIG" != "release" ]]; then
  echo "Usage: $0 [debug|release]"
  exit 1
fi

cd "$ROOT_DIR"

TARGET_ARCHS=("arm64" "x86_64")
UNIVERSAL_BIN_DIR="$ROOT_DIR/.build/universal/$BUILD_CONFIG"
mkdir -p "$UNIVERSAL_BIN_DIR"

build_for_arch() {
  local arch="$1"
  local scratch_path="$ROOT_DIR/.build/$BUILD_CONFIG-$arch"

  swift build -c "$BUILD_CONFIG" --arch "$arch" --scratch-path "$scratch_path" --product "$APP_EXECUTABLE"
  swift build -c "$BUILD_CONFIG" --arch "$arch" --scratch-path "$scratch_path" --product "$BOT_EXECUTABLE"
}

declare -a APP_SLICES=()
declare -a BOT_SLICES=()

for arch in "${TARGET_ARCHS[@]}"; do
  echo "==> Building $APP_EXECUTABLE and $BOT_EXECUTABLE ($BUILD_CONFIG, $arch)"
  BUILD_LOG="$(mktemp)"
  if ! build_for_arch "$arch" 2>&1 | tee "$BUILD_LOG"; then
    if grep -q "PCH was compiled with module cache path" "$BUILD_LOG"; then
      echo "==> Detected stale module cache path for $arch, cleaning and retrying once"
      rm -rf "$ROOT_DIR/.build/$BUILD_CONFIG-$arch"
      build_for_arch "$arch"
    else
      echo "Build failed for arch $arch. See log: $BUILD_LOG" >&2
      exit 1
    fi
  fi
  rm -f "$BUILD_LOG"

  ARCH_BIN_DIR="$ROOT_DIR/.build/$BUILD_CONFIG-$arch/$BUILD_CONFIG"
  ARCH_APP_BINARY="$ARCH_BIN_DIR/$APP_EXECUTABLE"
  ARCH_BOT_BINARY="$ARCH_BIN_DIR/$BOT_EXECUTABLE"

  if [[ ! -x "$ARCH_APP_BINARY" ]]; then
    echo "Missing app executable: $ARCH_APP_BINARY" >&2
    exit 1
  fi
  if [[ ! -x "$ARCH_BOT_BINARY" ]]; then
    echo "Missing bot executable: $ARCH_BOT_BINARY" >&2
    exit 1
  fi

  APP_SLICES+=("$ARCH_APP_BINARY")
  BOT_SLICES+=("$ARCH_BOT_BINARY")
done

APP_BINARY="$UNIVERSAL_BIN_DIR/$APP_EXECUTABLE"
BOT_BINARY="$UNIVERSAL_BIN_DIR/$BOT_EXECUTABLE"
WIRED_XML="$ROOT_DIR/.build/checkouts/WiredSwift/Sources/WiredSwift/Resources/wired.xml"

echo "==> Creating universal binaries (arm64 + x86_64)"
lipo -create "${APP_SLICES[@]}" -output "$APP_BINARY"
lipo -create "${BOT_SLICES[@]}" -output "$BOT_BINARY"
chmod 755 "$APP_BINARY" "$BOT_BINARY"
lipo -info "$APP_BINARY"
lipo -info "$BOT_BINARY"

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
RESOURCE_BUNDLE_DIR="$ROOT_DIR/.build/$BUILD_CONFIG-${TARGET_ARCHS[0]}/$BUILD_CONFIG"
shopt -s nullglob
for bundle in "$RESOURCE_BUNDLE_DIR"/*.bundle; do
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
  <key>WiredGitCommit</key>
  <string>$GIT_COMMIT</string>
  <key>WiredBuildMetadata</key>
  <string>$MARKETING_VERSION ($BUILD_NUMBER+$GIT_COMMIT)</string>
  <key>LSMinimumSystemVersion</key>
  <string>13.0</string>
  <key>LSUIElement</key>
  <true/>
  <key>NSHighResolutionCapable</key>
  <true/>
</dict>
</plist>
PLIST

resolve_signing_identity() {
  if [[ -n "${APPLE_SIGN_IDENTITY:-}" ]]; then
    echo "$APPLE_SIGN_IDENTITY"
    return 0
  fi

  local auto
  auto="$(security find-identity -v -p codesigning 2>/dev/null | sed -n 's/.*"\\(Developer ID Application:[^"]*\\)".*/\\1/p' | head -n 1)"
  if [[ -n "$auto" ]]; then
    echo "$auto"
  fi
}

sign_file() {
  local identity="$1"
  local file="$2"
  codesign --force --timestamp --options runtime --sign "$identity" "$file"
}

sign_app_bundle() {
  local identity="$1"
  local app="$2"
  codesign --force --deep --timestamp --options runtime --sign "$identity" "$app"
}

SIGNING_IDENTITY="$(resolve_signing_identity || true)"
SIGNING_MODE="adhoc"
if [[ -n "$SIGNING_IDENTITY" ]]; then
  SIGNING_MODE="developer-id"
  if [[ -n "${APPLE_DEV_ACCOUNT:-}" ]]; then
    echo "==> Signing with Developer ID for account hint: $APPLE_DEV_ACCOUNT"
  fi
  echo "==> Using signing identity: $SIGNING_IDENTITY"
  sign_file "$SIGNING_IDENTITY" "$RESOURCES_DIR/wiredbot"
  sign_app_bundle "$SIGNING_IDENTITY" "$APP_DIR"
else
  echo "==> No Developer ID identity found, using ad-hoc signing"
  codesign --force --sign - "$RESOURCES_DIR/wiredbot"
  codesign --force --deep --sign - "$APP_DIR"
fi

if [[ -z "$NOTARIZE" ]]; then
  if [[ -n "$NOTARY_PROFILE" ]]; then
    NOTARIZE="1"
  else
    NOTARIZE="0"
  fi
fi

case "$NOTARIZE" in
  1|true|TRUE|yes|YES) NOTARIZE="1" ;;
  0|false|FALSE|no|NO|"") NOTARIZE="0" ;;
  *)
    echo "Invalid NOTARIZE value: $NOTARIZE (expected 1/0/true/false)"
    exit 1
    ;;
esac

echo "==> Creating distribution archive"
rm -f "$APP_ZIP_PATH"
ditto -c -k --keepParent "$APP_DIR" "$APP_ZIP_PATH"

if [[ "$NOTARIZE" == "1" ]]; then
  if [[ -z "$SIGNING_IDENTITY" ]]; then
    echo "Notarization requires a Developer ID signature. Set APPLE_SIGN_IDENTITY."
    exit 1
  fi
  if [[ -z "$NOTARY_PROFILE" ]]; then
    echo "NOTARIZE=1 requires NOTARY_PROFILE (xcrun notarytool keychain profile name)."
    exit 1
  fi

  echo "==> Notarizing $APP_NAME"
  xcrun notarytool submit "$APP_ZIP_PATH" --keychain-profile "$NOTARY_PROFILE" --wait

  echo "==> Stapling notarization ticket to app"
  xcrun stapler staple "$APP_DIR"
  xcrun stapler validate "$APP_DIR"
  rm -f "$APP_ZIP_PATH"
  ditto -c -k --keepParent "$APP_DIR" "$APP_ZIP_PATH"
fi

echo "==> Verifying signatures"
codesign --verify --strict --verbose=2 "$RESOURCES_DIR/wiredbot"
codesign --verify --deep --strict --verbose=2 "$APP_DIR"

if [[ "$SIGNING_MODE" == "developer-id" ]]; then
  echo "==> Gatekeeper assessment"
  spctl --assess --type execute --verbose=4 "$APP_DIR"
else
  echo "==> Skipping Gatekeeper assessment for ad-hoc signature"
fi

echo "==> Done: $APP_DIR"
