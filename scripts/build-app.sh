#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
version="${VERSION:-0.1.0-beta.1}"
build_root="${BUILD_ROOT:-.build/distribution}"
mkdir -p "$build_root" dist
for arch in arm64 x86_64; do
  swift build -c release --arch "$arch" --scratch-path "$build_root/$arch" -Xswiftc -debug-prefix-map -Xswiftc "$PWD=."
done
stage="$(mktemp -d "${TMPDIR:-/tmp}/filetriage-package.XXXXXX")"
trap 'rm -rf "$stage"' EXIT
app="$stage/FileTriage.app"
mkdir -p "$app/Contents/MacOS" "$app/Contents/Resources"
cp LICENSE "$app/Contents/Resources/LICENSE.txt"
arm_bin="$(swift build -c release --arch arm64 --scratch-path "$build_root/arm64" --show-bin-path)/FileTriage"
intel_bin="$(swift build -c release --arch x86_64 --scratch-path "$build_root/x86_64" --show-bin-path)/FileTriage"
lipo -create "$arm_bin" "$intel_bin" -output "$app/Contents/MacOS/FileTriage"
strip -S "$app/Contents/MacOS/FileTriage"
/usr/libexec/PlistBuddy -c 'Clear dict' "$app/Contents/Info.plist"
/usr/libexec/PlistBuddy -c 'Add :CFBundleExecutable string FileTriage' "$app/Contents/Info.plist"
/usr/libexec/PlistBuddy -c 'Add :CFBundleIdentifier string io.github.danielsimisi-coder.FileTriage' "$app/Contents/Info.plist"
/usr/libexec/PlistBuddy -c 'Add :NSHumanReadableCopyright string © 2026 Daniel Siman Tov — daniel.simisi@gmail.com' "$app/Contents/Info.plist"
/usr/libexec/PlistBuddy -c 'Add :CFBundleName string FileTriage' "$app/Contents/Info.plist"
/usr/libexec/PlistBuddy -c 'Add :CFBundlePackageType string APPL' "$app/Contents/Info.plist"
/usr/libexec/PlistBuddy -c "Add :CFBundleShortVersionString string ${version%%-*}" "$app/Contents/Info.plist"
/usr/libexec/PlistBuddy -c 'Add :CFBundleVersion string 1' "$app/Contents/Info.plist"
/usr/libexec/PlistBuddy -c 'Add :LSMinimumSystemVersion string 13.0' "$app/Contents/Info.plist"
/usr/libexec/PlistBuddy -c 'Add :NSHighResolutionCapable bool true' "$app/Contents/Info.plist"
if [ -f assets/AppIcon.icns ]; then
  cp assets/AppIcon.icns "$app/Contents/Resources/AppIcon.icns"
  /usr/libexec/PlistBuddy -c 'Add :CFBundleIconFile string AppIcon' "$app/Contents/Info.plist"
fi
if [ -n "${SIGN_IDENTITY:-}" ]; then
  codesign --force --options runtime --timestamp --sign "$SIGN_IDENTITY" "$app"
else
  codesign --force --sign - "$app"
  echo 'AD-HOC BUILD: not Developer ID signed or notarized. Do not label as notarized.'
fi
codesign --verify --strict "$app"
archive="dist/FileTriage-$version-universal.zip"
ditto -c -k --keepParent "$app" "$archive"
if [ -n "${NOTARY_PROFILE:-}" ]; then
  test -n "${SIGN_IDENTITY:-}" || { echo 'NOTARY_PROFILE requires SIGN_IDENTITY'; exit 1; }
  xcrun notarytool submit "$archive" --keychain-profile "$NOTARY_PROFILE" --wait
  xcrun stapler staple "$app"
  xcrun stapler validate "$app"
  ditto -c -k --keepParent "$app" "$archive"
fi
(cd dist && shasum -a 256 "$(basename "$archive")") > "$archive.sha256"
echo "$archive"
