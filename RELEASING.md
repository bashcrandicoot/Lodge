# Releasing a new version of Lodge

Lodge checks for updates with [Sparkle](https://sparkle-project.org). Once a day it reads
the update feed on Cloudflare R2:

    https://pub-dc943f7d0c2042e992edc65b72cb7efe.r2.dev/lodge/appcast.xml

`SUFeedURL` in `Lodge/Info.plist` is that address. When the feed lists a newer build,
Lodge offers it, downloads the signed disk image

    https://pub-dc943f7d0c2042e992edc65b72cb7efe.r2.dev/lodge/Lodge-<version>.dmg

and installs it. There is no zip. It only installs a disk image signed with your private
Sparkle key, so nobody else can push an update to your users.

The copy of that feed in this repo is `release/appcast.xml`. Uploading that file is what
publishes the feed. The root `appcast.xml` is the old GitHub feed. Leave it in place.

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
- The **public key** is `SUPublicEDKey` in `Lodge/Info.plist`
  (`9Y5ssl+tCdpqaggzyIUbmUkGlcm77uCP8TvU4QcjmR4=`). Never change it.

## Licenses

Lodge activates keys with Polar's public customer-portal API. No API token is in the app.
Live organization `ece11ea2-d5d5-4acc-ad68-68f2ba66a6f9` at `https://api.polar.sh`.
Keys use the prefix `LODGE`, allow 3 activations, and do not expire.

Debug builds can talk to the sandbox (`https://sandbox-api.polar.sh`, organization
`6501e028-3477-48a7-b174-df0c4d223b6c`). Set the Lodge target build setting
`LODGE_POLAR_SANDBOX` to `YES`, or run with `LODGE_POLAR_SANDBOX=1`. Release builds
ignore both and always use the live organization. Buy Lodge opens

    https://buy.polar.sh/polar_cl_gS9NEtdIPJuJDXu8sdui02XetKbkwKuHgiYxi4FBkM1

A Mac without a key works for 3 days. That first-launch date is stored in the Keychain.

## Every release

Example: releasing **1.0**.

1. **Bump the version.** In Xcode, click the Lodge project → Lodge target → General:
   - *Version* (`MARKETING_VERSION`): `1.0`. This is what people see.
   - *Build* (`CURRENT_PROJECT_VERSION`): one more than the last release (Lodge 1.0
     was `6`, so the next release is `7`). **Sparkle compares the build number**,
     so it must always go up, even for a tiny fix. Never reuse one.
   Change both Debug and Release (setting them on the target's General tab does), and
   set the LodgeTests target to the same Version and Build so the whole project agrees.
   **In the same commit, update every place that names the current version:**
   - `README.md`: any line that names the current version.
   - `docs/index.html`: the **Install Lodge x.y** heading and the footer (**Lodge x.y ·**).
   - `SECURITY.md` (the supported release) and the bug report placeholder in
     `.github/ISSUE_TEMPLATE/bug_report.yml`.
   - A new section at the top of `docs/changelog.md`.
   Then run

       scripts/check-version.sh 1.0

   It fails if any `MARKETING_VERSION` in the project isn't 1.0, if `README.md` or
   `docs/index.html` don't name 1.0, or if they still name any other version
   (`LODGE_SKIP_DOC_CHECK=1` skips the README and site part). `scripts/make-dmg.sh` and
   `scripts/make-appcast.sh` run the same check first and stop if it fails, so a release
   can't be packaged or signed with a stale README or site.
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
   `xcrun stapler staple build/release/Lodge.app` **before** making the disk image.
4. **Make the disk image** in `build/release/`:

       scripts/make-dmg.sh 1.0

   `scripts/make-dmg.sh` makes `build/release/Lodge-1.0.dmg` with Lodge.app and an
   Applications shortcut, laid out by `scripts/dmg/DS_Store`. The mounted volume's icon is
   made from the current AppIcon in `Lodge/Assets.xcassets` each time (`iconutil` →
   `.VolumeIcon.icns`, plus the custom-icon flag with `SetFile -a C`), so a new app icon
   needs no extra step. It doesn't open any Finder windows. Do not make a zip.

   Optionally write release notes as `build/release/Lodge-1.0.md` (Markdown). They
   appear in Lodge's "A new version is available" window.
5. **Update the R2 feed:**

       scripts/make-appcast.sh 1.0

   It checks the disk image, signs it with your Keychain key and adds a 1.0 entry to
   `release/appcast.xml` pointing at
   `https://pub-dc943f7d0c2042e992edc65b72cb7efe.r2.dev/lodge/Lodge-1.0.dmg`.
   The first time, macOS may ask whether `generate_appcast` can use your Keychain:
   type your Mac login password and click **Always Allow**.
6. **Upload to R2** (the bucket behind `pub-dc943f7d0c2042e992edc65b72cb7efe.r2.dev`),
   before you commit the feed. The two object keys are:

       lodge/Lodge-1.0.dmg
       lodge/appcast.xml

   `lodge/appcast.xml` is the file `release/appcast.xml`. That disk image is the only
   download. The website is updated separately; do not point it at a zip.
7. **Commit the feed:** `git add release/appcast.xml && git commit -m "Appcast: Lodge 1.0"`.
8. **Push** (`git push`). Do this after the disk image and `lodge/appcast.xml` answer on
   R2. As soon as that appcast is public, everyone's new Lodge will see the update.
9. **Check it:** open an older Sparkle-enabled Lodge whose feed is already the R2 URL
   and choose Lodge ▸ Check for Updates….

## Builds that still use the GitHub feed

Lodge 1.0 (build 6) has `SUFeedURL` set to

    https://raw.githubusercontent.com/bashcrandicoot/Lodge/main/appcast.xml

That file stays in the repo so those installs keep finding build 6. GitHub does not
redirect `raw.githubusercontent.com`, so the old URL cannot 301 to R2. The only
download is one signed disk image, hosted on R2:

    https://pub-dc943f7d0c2042e992edc65b72cb7efe.r2.dev/lodge/Lodge-<version>.dmg

There is no zip. The v1.0 GitHub release carries only `Lodge-1.0.dmg`.

The enclosure’s `sparkle:edSignature` is a signature of that disk image. On a Mac,
with the Sparkle private key in the login Keychain:

    <sparkle-bin>/sign_update Lodge-1.0.dmg

`sign_update` prints the file length and the EdDSA signature. Put that length and
`sparkle:edSignature` on the `<enclosure>` in `appcast.xml`. `scripts/make-appcast.sh`
does the same thing through `generate_appcast` and writes them into `release/appcast.xml`.
Do not reuse a signature that was made for a zip.

Ship **one bridge release** on that old feed, then stop:

1. The bridge build is the first release whose `SUFeedURL` is the R2 appcast above.
   Its build number must be higher than 6.
2. Put its signed disk image on R2 (`lodge/Lodge-<version>.dmg`).
3. Append that one item to the root `appcast.xml` as well, with the same enclosure URL
   and the same EdDSA signature `scripts/make-appcast.sh` wrote into `release/appcast.xml`.
   Commit and push that single item to `main`.
4. Lodge 1.0 downloads that disk image from the GitHub feed, installs it, and every
   later check uses the R2 feed baked into the new app.
5. Leave the root `appcast.xml` frozen after that item. Later versions go only in
   `release/appcast.xml`.

## Where are Sparkle's tools?

`generate_keys`, `generate_appcast` and `sign_update` come with the Sparkle Swift package:
after any build they're in `<DerivedData>/SourcePackages/artifacts/sparkle/Sparkle/bin/`
(for example `/tmp/LodgeRelease/SourcePackages/artifacts/sparkle/Sparkle/bin/`).
`scripts/make-appcast.sh` finds them itself, or set `SPARKLE_BIN` to that folder.
