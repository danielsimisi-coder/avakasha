# Build and distribute

## Requirements

macOS 13+, Xcode or current Command Line Tools, Swift 5.9+. The app has no third-party package dependencies.

```sh
swift test
swift build -c release
./scripts/build-app.sh
```

The packaging script builds Apple Silicon and Intel slices, combines them into a universal `.app`, verifies the code signature and creates a ZIP plus SHA-256 checksum in `dist/`. It stages the bundle outside iCloud-synced folders to avoid Finder resource-fork signing problems.

## Apple-signed distribution

The default package is **ad-hoc signed**, not Developer ID signed or notarized. It is suitable for controlled beta/source-build testing, not a frictionless public download. Do not tell users to disable Gatekeeper or remove quarantine attributes.

For a normal public binary release, the maintainer needs an Apple Developer Program identity:

```sh
SIGN_IDENTITY='Developer ID Application: Your Name (TEAMID)' \
NOTARY_PROFILE='your-keychain-profile' \
VERSION='0.1.0' ./scripts/build-app.sh
```

The profile must already be configured using Apple's `notarytool`. Never commit private keys, certificates or passwords. The script submits to Apple only when `NOTARY_PROFILE` is explicitly set. Review Apple's current Developer ID and notarization requirements before release.

- https://developer.apple.com/developer-id/
- https://developer.apple.com/documentation/security/notarizing-macos-software-before-distribution

## Release checklist

- [ ] Unit/filesystem tests and release build pass on the release commit.
- [ ] Independent review has no unresolved release-blocking findings.
- [ ] Source audit passes; artwork and examples are synthetic.
- [ ] Test selection, preview, batch confirmation, partial failure and Undo on disposable fixtures.
- [ ] Test on a second Mac and each OS/architecture claimed as verified.
- [ ] For a public binary: Developer ID signing, notarization and ticket verification succeed.
- [ ] Download the actual ZIP to a clean Mac and test with Gatekeeper enabled.
- [ ] Publish exact signing/test limitations, checksum and release notes.

Keep the repository private during preparation. Changing visibility is a separate owner decision. A private beta release is not a completed public launch.
