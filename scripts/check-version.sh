#!/bin/bash
# Makes sure every place that names the current Lodge version names the one being released.
#
#   scripts/check-version.sh 1.0.3
#
# Fails (exit 1) unless:
#   - every MARKETING_VERSION in Lodge.xcodeproj/project.pbxproj (app and test targets) is <version>
#   - README.md mentions <version>
#   - docs/index.html says "Install Lodge <version>" and its footer says "Lodge <version> ·"
#   - neither README.md nor docs/index.html names any other x.y.z version, except the ones in
#     HISTORICAL_VERSIONS below (1.0.0 is named on purpose: it can't update itself, so its
#     users are told to download the current version by hand once).
#
# scripts/make-dmg.sh and scripts/make-appcast.sh run this first, so a release can't be
# packaged or signed until the README and the site are bumped. See RELEASING.md, step 1.
set -euo pipefail

HISTORICAL_VERSIONS=("1.0.0")

version="${1:-}"
version="${version#v}"
if [[ ! "$version" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
    echo "Usage: $0 <version>   e.g. $0 1.0.3" >&2
    exit 64
fi
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"
problems=0
fail() { echo "check-version: $*" >&2; problems=$((problems + 1)); }

# 1. The Xcode project.
while read -r found; do
    [[ "$found" == "$version" ]] || fail "Lodge.xcodeproj/project.pbxproj has MARKETING_VERSION = $found, not $version."
done < <(grep -o 'MARKETING_VERSION = [^;]*' Lodge.xcodeproj/project.pbxproj | sed 's/.*= //' | sort -u)

# 2. The README and the site must name this version...
grep -qF "$version" README.md || fail "README.md doesn't mention $version."
grep -qF "Install Lodge $version" docs/index.html || fail "docs/index.html doesn't say \"Install Lodge $version\"."
grep -qF "Lodge $version ·" docs/index.html || fail "docs/index.html's footer doesn't say \"Lodge $version ·\"."

# 3. ...and no other version as current.
for file in README.md docs/index.html; do
    while IFS=: read -r line found; do
        [[ "$found" == "$version" ]] && continue
        for old in "${HISTORICAL_VERSIONS[@]}"; do [[ "$found" == "$old" ]] && continue 2; done
        fail "$file:$line still names $found (releasing $version)."
    done < <(grep -n -o -E '(^|[^0-9.])[0-9]+\.[0-9]+\.[0-9]+([^0-9.]|$)' "$file" \
             | sed -E 's/^([0-9]+):[^0-9]*([0-9]+\.[0-9]+\.[0-9]+).*/\1:\2/')
done

if (( problems > 0 )); then
    echo "check-version: $problems problem(s). Update them for $version before releasing (RELEASING.md, step 1)." >&2
    exit 1
fi
echo "check-version: Lodge $version is named in the project, README.md and docs/index.html."
