#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
export MACOSX_DEPLOYMENT_TARGET=14.0
arch=$(uname -m)
case "$arch" in
  arm64) rust_target=aarch64-apple-darwin ;;
  x86_64) rust_target=x86_64-apple-darwin ;;
  *) echo "Build on an Apple Silicon or Intel Mac." >&2; exit 1 ;;
esac
cargo build --manifest-path core/Cargo.toml --release --target "$rust_target" --locked
app="$PWD/dist/BlinkMore.app"
mkdir -p "$app/Contents/MacOS" "$app/Contents/Resources" dist/iconset.iconset
sources=(BlinkMore/Core/*.swift BlinkMore/Services/*.swift BlinkMore/UI/*.swift BlinkMore/App/*.swift)
swiftc -O -whole-module-optimization -parse-as-library -target "$arch-apple-macosx14.0" \
  -module-name BlinkMore -import-objc-header core/include/BlinkCore.h \
  "${sources[@]}" "core/target/$rust_target/release/libblinkmore_core.a" \
  -o "$app/Contents/MacOS/BlinkMore"
swiftc -O -parse-as-library Scripts/MakeIcon.swift BlinkMore/UI/MenuBarController.swift BlinkMore/Core/TrackingState.swift -o dist/make-icon
dist/make-icon dist/iconset.iconset
iconutil -c icns dist/iconset.iconset -o "$app/Contents/Resources/AppIcon.icns"
cp BlinkMore/Info.plist "$app/Contents/Info.plist"
rm -rf "$app/Contents/Resources/UI" "$app/Contents/Resources/Icons"
cp -R BlinkMore/Resources/Icons "$app/Contents/Resources/Icons"
cp -R BlinkMore/Resources/UI "$app/Contents/Resources/UI"
cp LICENSE.md "$app/Contents/Resources/LICENSE.md"
cp LICENSE-RUST-STD "$app/Contents/Resources/LICENSE-RUST-STD"
codesign --force --sign "${BLINKMORE_SIGN_IDENTITY:--}" --entitlements BlinkMore/BlinkMore.entitlements "$app"
codesign --verify --strict "$app"
swiftc -O -target "$arch-apple-macosx14.0" Automation/BlinkMoreACAgent.swift -o dist/BlinkMoreACAgent
printf 'Built %s\n' "$app"
