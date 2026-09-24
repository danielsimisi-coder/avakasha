#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
version="${VERSION:-0.1.0-beta.19}"
build_root="${BUILD_ROOT:-.build/distribution}"
dist_dir="${DIST_DIR:-dist}"
mkdir -p "$build_root" "$dist_dir"
for arch in arm64 x86_64; do
  swift build -c release --arch "$arch" --scratch-path "$build_root/$arch" -Xswiftc -debug-prefix-map -Xswiftc "$PWD=."
done
stage="$(mktemp -d "${TMPDIR:-/tmp}/avakasha-package.XXXXXX")"
trap 'rm -rf "$stage"' EXIT
app="$stage/Avakasha.app"
mkdir -p "$app/Contents/MacOS" "$app/Contents/Resources"
cp LICENSE "$app/Contents/Resources/LICENSE.txt"
# Declared localizations let AppKit honour the in-app language choice (English default, Hebrew with right-to-left layout).
for lang in en he; do mkdir -p "$app/Contents/Resources/$lang.lproj"; printf '/* Avakasha %s */\n' "$lang" > "$app/Contents/Resources/$lang.lproj/InfoPlist.strings"; done
arm_bin="$(swift build -c release --arch arm64 --scratch-path "$build_root/arm64" --show-bin-path)/Avakasha"
intel_bin="$(swift build -c release --arch x86_64 --scratch-path "$build_root/x86_64" --show-bin-path)/Avakasha"
lipo -create "$arm_bin" "$intel_bin" -output "$app/Contents/MacOS/Avakasha"
strip -S "$app/Contents/MacOS/Avakasha"
/usr/libexec/PlistBuddy -c 'Clear dict' "$app/Contents/Info.plist"
/usr/libexec/PlistBuddy -c 'Add :CFBundleExecutable string Avakasha' "$app/Contents/Info.plist"
/usr/libexec/PlistBuddy -c 'Add :CFBundleIdentifier string io.github.danielsimisi-coder.Avakasha' "$app/Contents/Info.plist"
/usr/libexec/PlistBuddy -c 'Add :NSHumanReadableCopyright string © 2026 Daniel Siman Tov — daniel.simisi@gmail.com' "$app/Contents/Info.plist"
/usr/libexec/PlistBuddy -c 'Add :CFBundleName string Avakasha' "$app/Contents/Info.plist"
/usr/libexec/PlistBuddy -c 'Add :CFBundleDevelopmentRegion string en' "$app/Contents/Info.plist"
/usr/libexec/PlistBuddy -c 'Add :CFBundleLocalizations array' -c 'Add :CFBundleLocalizations:0 string en' -c 'Add :CFBundleLocalizations:1 string he' "$app/Contents/Info.plist"
/usr/libexec/PlistBuddy -c 'Add :CFBundlePackageType string APPL' "$app/Contents/Info.plist"
/usr/libexec/PlistBuddy -c "Add :CFBundleShortVersionString string ${version%%-*}" "$app/Contents/Info.plist"
# The build number is the prerelease number ("0.1.0-beta.19" → 18), so each release is newer than the last.
build_number="${version##*.}"; case "$build_number" in ''|*[!0-9]*) build_number=1 ;; esac
/usr/libexec/PlistBuddy -c "Add :CFBundleVersion string $build_number" "$app/Contents/Info.plist"
/usr/libexec/PlistBuddy -c 'Add :LSMinimumSystemVersion string 13.0' "$app/Contents/Info.plist"
/usr/libexec/PlistBuddy -c 'Add :NSHighResolutionCapable bool true' "$app/Contents/Info.plist"
if [ -f assets/AppIcon.icns ]; then
  cp assets/AppIcon.icns "$app/Contents/Resources/AppIcon.icns"
  /usr/libexec/PlistBuddy -c 'Add :CFBundleIconFile string AppIcon' "$app/Contents/Info.plist"
fi
if [ -n "${SIGN_IDENTITY:-}" ]; then
  security find-identity -v -p codesigning | grep -Fq "$SIGN_IDENTITY" || { echo "SIGN_IDENTITY not found in the keychain: $SIGN_IDENTITY"; exit 1; }
  case "$SIGN_IDENTITY" in "Developer ID Application:"*) ;; *) echo "WARNING: $SIGN_IDENTITY is not a Developer ID Application identity; Gatekeeper on other Macs will not accept it and notarization will be refused." ;; esac
  codesign --force --options runtime --timestamp --sign "$SIGN_IDENTITY" "$app"
else
  codesign --force --sign - "$app"
  echo 'AD-HOC BUILD: not Developer ID signed or notarized. Do not label as notarized.'
fi
codesign --verify --strict "$app"
"$app/Contents/MacOS/Avakasha" --launch-check
archive="$dist_dir/Avakasha-$version-universal.zip"
ditto --norsrc --noextattr -c -k --keepParent "$app" "$archive"
if [ -n "${NOTARY_PROFILE:-}" ]; then
  test -n "${SIGN_IDENTITY:-}" || { echo 'NOTARY_PROFILE requires SIGN_IDENTITY'; exit 1; }
  case "$SIGN_IDENTITY" in "Developer ID Application:"*) ;; *) echo 'Notarization needs a Developer ID Application identity.'; exit 1 ;; esac
  # Apple's verdict decides: anything but "Accepted" prints Apple's log and stops, and nothing is labelled notarized.
  result="$(xcrun notarytool submit "$archive" --keychain-profile "$NOTARY_PROFILE" --wait --output-format json)"
  echo "$result"
  field() { printf '%s' "$result" | /usr/bin/python3 -c "import json,sys; print(json.load(sys.stdin).get('$1',''))"; }
  if [ "$(field status)" != "Accepted" ]; then
    xcrun notarytool log "$(field id)" --keychain-profile "$NOTARY_PROFILE" || true
    echo "NOT NOTARIZED: Apple returned status '$(field status)'."
    exit 1
  fi
  xcrun stapler staple "$app"
  xcrun stapler validate "$app"
  spctl --assess --type execute -vv "$app" # Gatekeeper must accept the stapled app as a downloaded one would be
  ditto --norsrc --noextattr -c -k --keepParent "$app" "$archive"
  echo 'NOTARIZED: Developer ID signed, accepted by Apple, ticket stapled and validated.'
fi
(cd "$dist_dir" && shasum -a 256 "$(basename "$archive")") > "$archive.sha256"
echo "$archive"
