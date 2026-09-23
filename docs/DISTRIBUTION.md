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

Set `DIST_DIR` to write the archive somewhere other than `dist/`. The script refuses a `SIGN_IDENTITY` that is not in the keychain and warns when it is not a Developer ID Application identity: an Apple Development certificate can exercise the signing branch locally, but Gatekeeper on other Macs will not accept it and Apple will not notarize it.

### One-time setup for a notarized release

These steps belong to the account holder; Avakasha's scripts never see a password or a private key.

1. Join the Apple Developer Program (paid, yearly) at developer.apple.com/programs/enroll and wait for the approval.
2. In Xcode › Settings › Accounts, select the Apple ID, then Manage Certificates › + › **Developer ID Application**. The certificate and its private key stay in your login keychain.
3. At account.apple.com › Sign-In and Security › App-Specific Passwords, create a password named for example "avakasha-notary".
4. Store it for `notarytool` once, in Terminal (it asks for the app-specific password and keeps it in the keychain):
   `xcrun notarytool store-credentials avakasha-notary --apple-id YOUR_APPLE_ID --team-id YOUR_TEAM_ID`
5. Build with both set. The script signs with the hardened runtime and a secure timestamp, submits the archive, stops with Apple's log unless the status is **Accepted**, staples the ticket, checks it with `stapler validate` and `spctl --assess`, and only then rewrites the archive and prints `NOTARIZED`.

The hardened-runtime build has been checked locally with an Apple Development identity (the app launches and runs its demo views with no extra entitlements); that build is not distributable.

The profile must already be configured using Apple's `notarytool`. Never commit private keys, certificates or passwords. The script submits to Apple only when `NOTARY_PROFILE` is explicitly set. Review Apple's current Developer ID and notarization requirements before release.

- https://developer.apple.com/developer-id/
- https://developer.apple.com/documentation/security/notarizing-macos-software-before-distribution

## Signing validation, 22 September 2026

- The ad-hoc package builds, passes `codesign --verify --strict`, `--launch-check` inside the bundle and the release audit.
- The signing branch was exercised locally with an **Apple Development** identity into a scratch `DIST_DIR`: hardened runtime and a trusted timestamp were applied and `codesign -dvv` shows the full certificate chain. `spctl --assess` rejects that build, as expected for a non-Developer-ID identity. Nothing signed this way is distributed.
- No Developer ID Application identity and no `notarytool` keychain profile exist on the build Mac, so notarization was not attempted and is not claimed. The script path is ready; it only needs the identity and profile.
- No Intel Mac, no clean Mac and no Gatekeeper acceptance test were available; these remain checklist items.

## Release checklist

- [ ] Unit/filesystem tests and release build pass on the release commit.
- [ ] Independent review has no unresolved release-blocking findings.
- [ ] Source audit passes; artwork and examples are synthetic.
- [ ] Test selection, preview, batch confirmation, partial failure and Undo on disposable fixtures.
- [ ] Test on a second Mac and each OS/architecture claimed as verified.
- [ ] For a public binary: Developer ID signing, notarization and ticket verification succeed.
- [ ] Download the actual ZIP to a clean Mac and test with Gatekeeper enabled.
- [ ] Publish exact signing/test limitations, checksum and release notes.

The repository is public as of beta 10 (an owner decision, 23 September 2026); the project ships as source plus an ad-hoc signed ZIP. A beta release is not a completed public launch.
