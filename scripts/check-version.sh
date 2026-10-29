#!/bin/bash
# Makes sure every place that names the current Lodge version names the one being released.
#
#   scripts/check-version.sh 1.0
#   LODGE_SKIP_DOC_CHECK=1 scripts/check-version.sh 1.0   # project only, skip README/site
#
# Fails (exit 1) unless:
#   - every MARKETING_VERSION in Lodge.xcodeproj/project.pbxproj (app and test targets) is <version>
#   - README.md mentions <version>
#   - docs/index.html says "Install Lodge <version>" and its footer says "Lodge <version> ·"
#   - neither README.md nor docs/index.html names any other x.y.z version, or "Lodge x.y[.z]"
#     with another version
# <version> may be x.y (1.0) or x.y.z (1.0.1).
#
# scripts/make-dmg.sh and scripts/make-appcast.sh run this first, so a release can't be
# packaged or signed until the README and the site are bumped. See RELEASING.md, step 1.
set -euo pipefail


version="${1:-}"
version="${version#v}"
if [[ ! "$version" =~ ^[0-9]+\.[0-9]+(\.[0-9]+)?$ ]]; then
    echo "Usage: $0 <version>   e.g. $0 1.0" >&2
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

# 2. The README and the site must name this version, and no other version as current.
#    Set LODGE_SKIP_DOC_CHECK=1 to skip this part (for example while the docs are being
#    rewritten separately); the project check above always runs.
if [[ "${LODGE_SKIP_DOC_CHECK:-0}" == "1" ]]; then
    echo "check-version: LODGE_SKIP_DOC_CHECK=1, skipping README.md and docs/index.html." >&2
else
    grep -qF "$version" README.md || fail "README.md doesn't mention $version."
    grep -qF "Install Lodge $version<" docs/index.html || fail "docs/index.html doesn't say \"Install Lodge $version\"."
    grep -qF "Lodge $version ·" docs/index.html || fail "docs/index.html's footer doesn't say \"Lodge $version ·\"."
    # Any x.y.z, or any "Lodge x.y" / "Lodge x.y.z", other than this version is stale.
    for file in README.md docs/index.html; do
        while IFS=: read -r line found; do
            [[ "$found" == "$version" ]] && continue
            fail "$file:$line still names $found (releasing $version)."
        done < <( { grep -n -o -E '(^|[^0-9.])[0-9]+\.[0-9]+\.[0-9]+([^0-9.]|$)' "$file" || true
                    grep -n -o -E 'Lodge [0-9]+\.[0-9]+(\.[0-9]+)?' "$file" || true; } \
                 | sed -E 's/^([0-9]+):[^0-9]*([0-9]+\.[0-9]+(\.[0-9]+)?).*/\1:\2/' | sort -u)
    done
fi

if (( problems > 0 )); then
    echo "check-version: $problems problem(s). Update them for $version before releasing (RELEASING.md, step 1)." >&2
    exit 1
fi
if [[ "${LODGE_SKIP_DOC_CHECK:-0}" == "1" ]]; then
    echo "check-version: Lodge $version is named in the project (docs not checked)."
else
    echo "check-version: Lodge $version is named in the project, README.md and docs/index.html."
fi
