# Releasing a new version of Lodge

Lodge checks for updates with [Sparkle](https://sparkle-project.org). Once a day it reads
the update feed, `appcast.xml` in this repo:

    https://raw.githubusercontent.com/bashcrandicoot/Lodge/main/appcast.xml

When the feed lists a newer build, Lodge offers it, downloads the zip from the GitHub
release and installs it. It only installs a zip signed with your private Sparkle key,
so nobody else can push an update to your users.

> Lodge 1.0.0 was released before Sparkle was added, so it can't update itself. People on
> 1.0.0 need to download the next version by hand once. From then on, updates are automatic.

## One-time setup (already done)

- The **private signing key** is in your login Keychain (Keychain Access → login →
  search for `sparkle`; the item is called *Private key for signing Sparkle updates*,
  account `ed25519`). **Back it up**: if you lose it, apps already out there can never
  accept an update again. Export it to a file you keep somewhere safe (a password
  manager or an encrypted drive, never this repo):

      <sparkle-bin>/generate_keys -x ~/Desktop/lodge-sparkle-private-key.txt

  then move that file somewhere safe. (`<sparkle-bin>` is the folder the script below
  prints, or see "Where are Sparkle's tools?" at the end.) On a new Mac, import it with
  `generate_keys -f <file>`.
- The **public key** is `SUPublicEDKey` in `Lodge/Info.plist`. Never change it.

## Every release

Example: releasing **1.0.1**.

1. **Bump the version.** In Xcode, click the Lodge project → Lodge target → General:
   - *Version* (`MARKETING_VERSION`): `1.0.1`. This is what people see.
   - *Build* (`CURRENT_PROJECT_VERSION`): one more than last time (1.0.0 was `1`, so
     1.0.1 is `2`, 1.0.2 is `3`, 1.1.0 is `4`…). **Sparkle compares the build number**,
     so it must always go up, even for a tiny fix. Never reuse one.
   Change both Debug and Release (setting them on the target's General tab does).
2. **Build the Release app** (universal, Apple silicon + Intel):

       DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer \
         xcodebuild -project Lodge.xcodeproj -scheme Lodge -configuration Release \
         -destination 'generic/platform=macOS' -derivedDataPath /tmp/LodgeRelease build
       rm -rf build/release && mkdir -p build/release
       cp -R /tmp/LodgeRelease/Build/Products/Release/Lodge.app build/release/

3. **Sign and notarize (if you have a paid Apple Developer account).** Lodge is currently
   ad-hoc signed and not notarized, which Sparkle accepts because the updates are
   EdDSA-signed. If you later get a Developer ID certificate, sign `Lodge.app` with it
   (with Hardened Runtime on), notarize it with `xcrun notarytool submit … --wait`, and
   `xcrun stapler staple build/release/Lodge.app` **before** making the zip and dmg.
4. **Make the zip and dmg** in `build/release/`:

       cd build/release
       ditto -c -k --keepParent Lodge.app Lodge-1.0.1.zip
       cd ../..
       scripts/make-dmg.sh 1.0.1

   `scripts/make-dmg.sh` makes `build/release/Lodge-1.0.1.dmg` with Lodge.app and an
   Applications shortcut, laid out by `scripts/dmg/DS_Store`. The mounted volume's icon is
   made from the current AppIcon in `Lodge/Assets.xcassets` each time (`iconutil` →
   `.VolumeIcon.icns`, plus the custom-icon flag with `SetFile -a C`), so a new app icon
   needs no extra step. It doesn't open any Finder windows.

   Optionally write release notes as `build/release/Lodge-1.0.1.md` (Markdown). They
   appear in Lodge's "A new version is available" window.
5. **Update the feed:**

       scripts/make-appcast.sh 1.0.1

   It checks the zip, signs it with your Keychain key and adds a 1.0.1 entry to
   `appcast.xml` pointing at
   `https://github.com/bashcrandicoot/Lodge/releases/download/v1.0.1/Lodge-1.0.1.zip`.
   The first time, macOS may ask whether `generate_appcast` can use your Keychain:
   type your Mac login password and click **Always Allow**.
6. **Commit the feed:** `git add appcast.xml && git commit -m "Appcast: Lodge 1.0.1"`.
7. **Upload to GitHub:** create the release with the tag **`v1.0.1`** (exactly that, the
   feed's download link depends on it) and attach `Lodge-1.0.1.zip` and
   `Lodge-1.0.1.dmg`, for example:

       gh release create v1.0.1 build/release/Lodge-1.0.1.zip build/release/Lodge-1.0.1.dmg \
         --title "Lodge 1.0.1" --notes-file build/release/Lodge-1.0.1.md

8. **Push** (`git push`). Do this last: as soon as `appcast.xml` is on `main`, everyone's
   Lodge will see the update, so the zip must already be on the release.
9. **Check it:** open an older Sparkle-enabled Lodge and choose Lodge ▸ Check for Updates….

## Where are Sparkle's tools?

`generate_keys`, `generate_appcast` and `sign_update` come with the Sparkle Swift package:
after any build they're in `<DerivedData>/SourcePackages/artifacts/sparkle/Sparkle/bin/`
(for example `/tmp/LodgeRelease/SourcePackages/artifacts/sparkle/Sparkle/bin/`).
`scripts/make-appcast.sh` finds them itself, or set `SPARKLE_BIN` to that folder.
