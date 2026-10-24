#!/bin/bash
set -euo pipefail
repo_root=$(cd "$(dirname "$0")/.." && pwd)
cd "$repo_root"
[[ $(uname -s) == Darwin ]] || { echo 'Run the bundled UI smoke test in a macOS GUI session.' >&2; exit 1; }

arch=$(uname -m)
case "$arch" in
  arm64|x86_64) ;;
  *) echo 'Run on an Apple Silicon or Intel Mac.' >&2; exit 1 ;;
esac

temporary_root=$(mktemp -d "${TMPDIR:-/tmp}/EyesightBundledUITests.XXXXXX")
trap 'rm -rf "$temporary_root"' EXIT
app="$temporary_root/EyesightBundledUITests.app"
bundle_id='com.oxremy.blinkmorefree.bundle-ui-tests'
mkdir -p "$app/Contents/MacOS" "$app/Contents/Resources/UI" "$app/Contents/Resources/Icons"

cat > "$app/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleExecutable</key><string>BundledUITests</string>
<key>CFBundleIdentifier</key><string>$bundle_id</string>
<key>CFBundleName</key><string>Eyesight Bundled UI Tests</string>
<key>CFBundlePackageType</key><string>APPL</string>
<key>CFBundleShortVersionString</key><string>1.0</string>
<key>CFBundleVersion</key><string>1</string>
<key>LSMinimumSystemVersion</key><string>14.0</string>
<key>LSUIElement</key><true/>
<key>NSHighResolutionCapable</key><true/>
<key>NSCameraUsageDescription</key><string>Bundled UI tests do not start camera capture.</string>
</dict></plist>
PLIST

cp -R BlinkMore/Resources/UI/. "$app/Contents/Resources/UI/"
rm -rf "$app/Contents/Resources/UI/assets/sources"
cp -R BlinkMore/Resources/Icons/. "$app/Contents/Resources/Icons/"

cargo build --manifest-path core/Cargo.toml --locked
sources=(BlinkMore/Core/*.swift BlinkMore/Services/*.swift BlinkMore/UI/*.swift BlinkMore/App/ApplicationController.swift)
swiftc -Onone -parse-as-library -target "$arch-apple-macosx14.0" \
  -module-name BundledUITests -import-objc-header core/include/BlinkCore.h \
  Tests/NativeWindowTests.swift "${sources[@]}" core/target/debug/libblinkmore_core.a \
  -o "$app/Contents/MacOS/BundledUITests"

codesign --force --sign "${BLINKMORE_SIGN_IDENTITY:--}" \
  --entitlements BlinkMore/BlinkMore.entitlements "$app"
codesign --verify --strict "$app"
codesign -d --entitlements :- "$app" > "$temporary_root/signed-entitlements.plist" 2>/dev/null
plutil -lint "$temporary_root/signed-entitlements.plist" >/dev/null

echo "Built signed isolated bundle $app"
if [[ ${BUNDLE_UI_COMPILE_ONLY:-0} == 1 ]]; then
  exit 0
fi

# Execute the signed bundle's own executable directly. This keeps the test's output
# attached to the invoking shell while preserving the app bundle and sandbox context.
python3 - "$app/Contents/MacOS/BundledUITests" <<'PY'
import subprocess
import sys

try:
    result = subprocess.run([sys.argv[1]], timeout=30, check=False)
except subprocess.TimeoutExpired:
    print("Bundled UI test exceeded its 30 second limit", file=sys.stderr)
    raise SystemExit(124)
raise SystemExit(result.returncode)
PY
