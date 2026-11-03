#!/bin/bash
# Adds a new Lodge release to release/appcast.xml (the Sparkle feed served from
# Cloudflare R2), signed with the EdDSA private key in your login Keychain.
#
#   scripts/make-appcast.sh <version> [folder-with-the-release-files]
#   scripts/make-appcast.sh 1.0                 # looks in build/release
#
# The folder must contain Lodge-<version>.dmg (from scripts/make-dmg.sh). Sparkle
# downloads that disk image. There is no zip. Optional release notes:
# Lodge-<version>.md (or .html) next to the dmg.
#
# The enclosure URL is
#   https://pub-dc943f7d0c2042e992edc65b72cb7efe.r2.dev/lodge/Lodge-<version>.dmg
# Upload that file and release/appcast.xml so they are served at
#   https://pub-dc943f7d0c2042e992edc65b72cb7efe.r2.dev/lodge/appcast.xml
#
# This script does not change the legacy GitHub feed, appcast.xml at the repo root.
# See RELEASING.md.
#
# Environment (optional):
#   SPARKLE_BIN    folder with Sparkle's generate_appcast (found automatically otherwise)
#   ED_KEY_FILE    sign with a private key file instead of the Keychain (testing only)
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
DOWNLOAD_PREFIX="https://pub-dc943f7d0c2042e992edc65b72cb7efe.r2.dev/lodge/"
PUBLIC_KEY="9Y5ssl+tCdpqaggzyIUbmUkGlcm77uCP8TvU4QcjmR4="
FEED_URL="${DOWNLOAD_PREFIX}appcast.xml"
REPO_URL="https://github.com/bashcrandicoot/Lodge"

version="${1:-}"
if [[ -z "$version" ]]; then
    echo "Usage: $0 <version> [folder]   e.g. $0 1.0" >&2
    exit 64
fi
version="${version#v}"
folder="${2:-$ROOT/build/release}"
dmg="$folder/Lodge-$version.dmg"

# Refuse to sign a release the README, the site or the project don't name yet.
"$ROOT/scripts/check-version.sh" "$version"
[[ -f "$dmg" ]] || { echo "Can't find $dmg (DMG only; do not pass a zip)" >&2; exit 66; }
[[ -f "$ROOT/release/appcast.xml" ]] || { echo "Missing $ROOT/release/appcast.xml" >&2; exit 66; }

# Find Sparkle's command-line tools (they come with the Swift package).
find_bin() {
    if [[ -n "${SPARKLE_BIN:-}" ]]; then echo "$SPARKLE_BIN"; return; fi
    local candidate
    for candidate in \
        "$ROOT"/build/DerivedData/SourcePackages/artifacts/sparkle/Sparkle/bin \
        /tmp/*/SourcePackages/artifacts/sparkle/Sparkle/bin \
        "$HOME"/Library/Developer/Xcode/DerivedData/Lodge-*/SourcePackages/artifacts/sparkle/Sparkle/bin; do
        if [[ -x "$candidate/generate_appcast" ]]; then echo "$candidate"; return; fi
    done
    echo "Fetching the Sparkle package to get its tools…" >&2
    DEVELOPER_DIR="${DEVELOPER_DIR:-/Applications/Xcode.app/Contents/Developer}" \
        xcodebuild -project "$ROOT/Lodge.xcodeproj" -scheme Lodge \
        -derivedDataPath /tmp/LodgeSparkleTools -resolvePackageDependencies >/dev/null
    echo /tmp/LodgeSparkleTools/SourcePackages/artifacts/sparkle/Sparkle/bin
}
bin="$(find_bin)"
[[ -x "$bin/generate_appcast" ]] || { echo "generate_appcast not found in $bin" >&2; exit 69; }

# Sanity check: the app in the disk image must be the version you said, its feed must
# already be the R2 appcast, and its build number (CFBundleVersion, which Sparkle
# compares) must be higher than every build in the R2 feed and the legacy GitHub feed.
check="$(mktemp -d)"
staging="$(mktemp -d)"
mnt="$check/mnt"
mkdir -p "$mnt"
detach() {
    if mount | grep -q " on $mnt "; then
        hdiutil detach "$mnt" -quiet || hdiutil detach "$mnt" -force -quiet || true
    fi
}
trap 'detach; rm -rf "$check" "$staging"' EXIT
hdiutil attach -quiet -nobrowse -readonly -noverify -mountpoint "$mnt" "$dmg"
plist="$mnt/Lodge.app/Contents/Info.plist"
[[ -f "$plist" ]] || { echo "The disk image must contain Lodge.app at its top level." >&2; exit 65; }
app_version="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$plist")"
app_build="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' "$plist")"
app_feed="$(/usr/libexec/PlistBuddy -c 'Print :SUFeedURL' "$plist")"
app_key="$(/usr/libexec/PlistBuddy -c 'Print :SUPublicEDKey' "$plist" 2>/dev/null || true)"
detach
if [[ "$app_version" != "$version" ]]; then
    echo "The disk image contains Lodge $app_version, not $version." >&2; exit 65
fi
if [[ "$app_key" != "$PUBLIC_KEY" ]]; then
    echo "This Lodge.app has no matching SUPublicEDKey, so it was built without Sparkle." >&2; exit 65
fi
if [[ "$app_feed" != "$FEED_URL" ]]; then
    echo "SUFeedURL is $app_feed" >&2
    echo "Expected $FEED_URL" >&2
    exit 65
fi
versions_in() {
    local file="$1"
    [[ -f "$file" ]] || return 0
    grep -o '<sparkle:version>[^<]*' "$file" | sed 's/.*>//' || true
}
latest_build="$( { versions_in "$ROOT/release/appcast.xml"; versions_in "$ROOT/appcast.xml"; } | sort -n | tail -1 || true)"
if [[ -n "$latest_build" ]] && (( app_build <= latest_build )); then
    echo "Build number $app_build isn't higher than $latest_build, already in a feed." >&2
    echo "Raise CURRENT_PROJECT_VERSION in the Lodge target and rebuild." >&2
    exit 65
fi

# generate_appcast works on a folder: give it the R2 feed plus just this disk image.
cp "$ROOT/release/appcast.xml" "$staging/appcast.xml"
cp "$dmg" "$staging/"
for notes in "$folder/Lodge-$version".{md,html,txt}; do
    [[ -f "$notes" ]] && cp "$notes" "$staging/"
done

args=(--download-url-prefix "$DOWNLOAD_PREFIX"
      --link "$REPO_URL"
      --maximum-deltas 0
      --embed-release-notes)
if [[ -n "${ED_KEY_FILE:-}" ]]; then args+=(--ed-key-file "$ED_KEY_FILE"); fi

echo "Signing Lodge $version (build $app_build) with your Sparkle key…"
echo "(If macOS asks whether generate_appcast may use your Keychain, click Always Allow.)"
"$bin/generate_appcast" "${args[@]}" "$staging"

# Refuse an unsigned entry, a zip enclosure, or a URL that is not this disk image.
new_item() {
    awk -v b="<sparkle:version>$app_build</sparkle:version>" \
        '/<item>/{buf=""} {buf=buf $0 "\n"} /<\/item>/{if (index(buf, b)) printf "%s", buf}' "$1"
}
item="$(new_item "$staging/appcast.xml")"
expected="${DOWNLOAD_PREFIX}Lodge-$version.dmg"
if ! printf '%s' "$item" | grep -q 'sparkle:edSignature='; then
    echo "The new entry wasn't signed (does your Keychain key match SUPublicEDKey?)." >&2
    echo "release/appcast.xml was left unchanged." >&2
    exit 70
fi
if ! printf '%s' "$item" | grep -q "$expected"; then
    echo "The enclosure is not $expected" >&2
    echo "release/appcast.xml was left unchanged." >&2
    exit 70
fi
if printf '%s' "$item" | grep -q '\.zip'; then
    echo "The new entry points at a zip. Lodge updates are disk images only." >&2
    echo "release/appcast.xml was left unchanged." >&2
    exit 70
fi

cp "$staging/appcast.xml" "$ROOT/release/appcast.xml"
echo
echo "Updated release/appcast.xml with Lodge $version."
echo "Upload these two objects so the public R2 URL serves them:"
echo "  $dmg"
echo "    -> ${expected}"
echo "  $ROOT/release/appcast.xml"
echo "    -> ${FEED_URL}"
echo "Do not add this version to the legacy GitHub feed (appcast.xml) except as the"
echo "one bridge release in RELEASING.md. Nothing was uploaded."
