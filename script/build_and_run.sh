#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
MODE="${1:-run}"
case "$MODE" in
  run|--build|--release|--verify|--debug|--logs|--telemetry) ;;
  *) echo "Usage: $0 [--build|--release|--verify|--debug|--logs|--telemetry]" >&2; exit 2 ;;
esac

export CLANG_MODULE_CACHE_PATH="$PWD/.build/ModuleCache"
export SWIFTPM_MODULECACHE_OVERRIDE="$PWD/.build/ModuleCache"
APP="$PWD/dist/Signalbox.app"
mkdir -p "$APP/Contents/MacOS"

if [[ "$MODE" == --release ]]; then
  for arch in arm64 x86_64; do
    build_options=(--disable-sandbox --build-system native --configuration release --arch "$arch")
    swift build "${build_options[@]}"
    bin_dir="$(swift build "${build_options[@]}" --show-bin-path)"
    cp "$bin_dir/Signalbox" "dist/Signalbox-$arch"
  done
  lipo -create dist/Signalbox-arm64 dist/Signalbox-x86_64 -output "$APP/Contents/MacOS/Signalbox"
  rm dist/Signalbox-arm64 dist/Signalbox-x86_64
else
  swift build --disable-sandbox --build-system native
  bin_dir="$(swift build --disable-sandbox --build-system native --show-bin-path)"
  cp "$bin_dir/Signalbox" "$APP/Contents/MacOS/Signalbox"
fi
mkdir -p dist/icon-assets "$APP/Contents/Resources"
xcrun actool "$PWD/Assets/Signalbox.icon" --compile "$PWD/dist/icon-assets" --platform macosx --minimum-deployment-target 14.0 --app-icon Signalbox --output-partial-info-plist "$PWD/dist/icon-info.plist" >/dev/null
cp dist/icon-assets/Signalbox.icns dist/icon-assets/Assets.car "$APP/Contents/Resources/"
cat > "$APP/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleExecutable</key><string>Signalbox</string>
<key>CFBundleIdentifier</key><string>xyz.braksa.apps.signalbox</string>
<key>CFBundleIconFile</key><string>Signalbox</string>
<key>CFBundleIconName</key><string>Signalbox</string>
<key>CFBundleName</key><string>Signalbox</string>
<key>CFBundlePackageType</key><string>APPL</string>
<key>CFBundleShortVersionString</key><string>1.0.0</string>
<key>CFBundleVersion</key><string>8</string>
<key>LSMinimumSystemVersion</key><string>14.0</string>
<key>NSPrincipalClass</key><string>NSApplication</string>
<key>LSUIElement</key><true/>
</dict></plist>
PLIST
signing_identity="${SIGNALBOX_SIGNING_IDENTITY:--}"
signing_options=()
if [[ "$MODE" == --release && "$signing_identity" != - ]]; then
  signing_options=(--options runtime --timestamp)
fi
codesign --force "${signing_options[@]+"${signing_options[@]}"}" --sign "$signing_identity" "$APP"
codesign --verify --strict "$APP"
case "$MODE" in
  --build|--release) ;;
  --debug) lldb -- "$APP/Contents/MacOS/Signalbox" ;;
  --logs|--telemetry) open -n "$APP"; /usr/bin/log stream --info --style compact --predicate 'process == "Signalbox"' ;;
  --verify) open -n "$APP"; sleep 1; pgrep -x Signalbox >/dev/null ;;
  run) open -n "$APP" ;;
esac
