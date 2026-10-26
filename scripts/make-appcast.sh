#!/bin/bash
# Adds a new Lodge release to appcast.xml (the Sparkle update feed), signed with the
# EdDSA private key in your login Keychain.
#
#   scripts/make-appcast.sh <version> [folder-with-the-release-files]
#   scripts/make-appcast.sh 1.0.1                 # looks in build/release
#
# The folder must contain Lodge-<version>.zip (Lodge.app zipped with `ditto -c -k
# --keepParent`). Sparkle downloads the zip; the .dmg is for people downloading by hand.
# Optional release notes: Lodge-<version>.md (or .html) next to the zip.
#
# Only appcast.xml in the repo is changed. Nothing is uploaded or pushed.
# See RELEASING.md for the whole release, step by step.
#
# Environment (optional):
#   SPARKLE_BIN    folder with Sparkle's generate_appcast (found automatically otherwise)
#   ED_KEY_FILE    sign with a private key file instead of the Keychain (testing only)
set -euo pipefail

REPO_URL="https://github.com/bashcrandicoot/Lodge"
ROOT="$(cd "$(dirname "$0")/.." && pwd)"

version="${1:-}"
if [[ -z "$version" ]]; then
    echo "Usage: $0 <version> [folder]   e.g. $0 1.0.1" >&2
    exit 64
fi
version="${version#v}"
folder="${2:-$ROOT/build/release}"
zip="$folder/Lodge-$version.zip"
[[ -f "$zip" ]] || { echo "Can't find $zip" >&2; exit 66; }

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

# Sanity check: the app in the zip must be the version you said, and its build number
# (CFBundleVersion, which Sparkle compares) must be higher than every build in the feed.
check="$(mktemp -d)"
staging="$(mktemp -d)"
trap 'rm -rf "$check" "$staging"' EXIT
ditto -x -k "$zip" "$check"
plist="$check/Lodge.app/Contents/Info.plist"
[[ -f "$plist" ]] || { echo "The zip must contain Lodge.app at its top level." >&2; exit 65; }
app_version="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$plist")"
app_build="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' "$plist")"
if [[ "$app_version" != "$version" ]]; then
    echo "The zip contains Lodge $app_version, not $version." >&2; exit 65
fi
if ! /usr/libexec/PlistBuddy -c 'Print :SUPublicEDKey' "$plist" >/dev/null 2>&1; then
    echo "This Lodge.app has no SUPublicEDKey, so it was built without Sparkle." >&2; exit 65
fi
latest_build="$(grep -o '<sparkle:version>[^<]*' "$ROOT/appcast.xml" | sed 's/.*>//' | sort -n | tail -1 || true)"
if [[ -n "$latest_build" ]] && (( app_build <= latest_build )); then
    echo "Build number $app_build isn't higher than $latest_build, already in appcast.xml." >&2
    echo "Raise CURRENT_PROJECT_VERSION in the Lodge target and rebuild." >&2
    exit 65
fi

# generate_appcast works on a folder: give it the current feed plus just this release.
cp "$ROOT/appcast.xml" "$staging/appcast.xml"
cp "$zip" "$staging/"
for notes in "$folder/Lodge-$version".{md,html,txt}; do
    [[ -f "$notes" ]] && cp "$notes" "$staging/"
done

args=(--download-url-prefix "$REPO_URL/releases/download/v$version/"
      --link "$REPO_URL"
      --maximum-deltas 0
      --embed-release-notes)
if [[ -n "${ED_KEY_FILE:-}" ]]; then args+=(--ed-key-file "$ED_KEY_FILE"); fi

echo "Signing Lodge $version (build $app_build) with your Sparkle key…"
echo "(If macOS asks whether generate_appcast may use your Keychain, click Always Allow.)"
"$bin/generate_appcast" "${args[@]}" "$staging"

# Refuse an unsigned entry: Lodge only installs updates signed with your key.
# Look anywhere in the new <item>: embedded release notes push the enclosure (which carries
# the signature) well below <sparkle:version>.
new_item() {
    awk -v b="<sparkle:version>$app_build</sparkle:version>" \
        '/<item>/{buf=""} {buf=buf $0 "\n"} /<\/item>/{if (index(buf, b)) printf "%s", buf}' "$1"
}
if ! new_item "$staging/appcast.xml" | grep -q 'sparkle:edSignature='; then
    echo "The new entry wasn't signed (does your Keychain key match SUPublicEDKey?)." >&2
    echo "appcast.xml was left unchanged." >&2
    exit 70
fi

cp "$staging/appcast.xml" "$ROOT/appcast.xml"
echo
echo "Updated appcast.xml with Lodge $version. Next: commit it, upload the zip and dmg"
echo "to the v$version GitHub release, then push (see RELEASING.md)."
