#!/bin/bash
# Runs the license state tests on Linux (or anywhere with a Swift toolchain).
# The Lodge app target needs macOS, Sparkle, and AppKit, so this compiles only
# Lodge/License.swift plus LodgeTests/LicenseTests.swift.
set -euo pipefail

if ! command -v swift >/dev/null 2>&1; then
    echo "test-license-linux: Swift 6.1 or later is required. The swift command was not found." >&2
    exit 69
fi
swift_version="$(swift --version 2>/dev/null | sed -n 's/.*Swift version \([0-9][0-9]*\.[0-9][0-9]*\).*/\1/p' | head -1)"
swift_major="${swift_version%%.*}"
swift_minor="${swift_version#*.}"
swift_minor="${swift_minor%%.*}"
if [[ -z "$swift_version" || "$swift_major" -lt 6 || ( "$swift_major" -eq 6 && "$swift_minor" -lt 1 ) ]]; then
    echo "test-license-linux: Swift 6.1 or later is required. Found: ${swift_version:-unknown}." >&2
    echo "Install a Swift 6.1+ toolchain and put it on PATH, then run this script again." >&2
    exit 69
fi

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

mkdir -p "$WORK/Sources/LodgeLicense" "$WORK/Tests/LodgeLicenseTests"
cp "$ROOT/Lodge/License.swift" "$WORK/Sources/LodgeLicense/License.swift"
cp "$ROOT/LodgeTests/LicenseTests.swift" "$WORK/Tests/LodgeLicenseTests/LicenseTests.swift"
cat > "$WORK/Package.swift" <<'EOF'
// swift-tools-version:5.9
import PackageDescription
let package = Package(
    name: "LodgeLicenseTests",
    targets: [
        .target(name: "LodgeLicense"),
        .testTarget(name: "LodgeLicenseTests", dependencies: ["LodgeLicense"]),
    ]
)
EOF

# The Info.plist feed and the legacy appcast are not part of the Swift tests.
grep -q 'https://pub-dc943f7d0c2042e992edc65b72cb7efe.r2.dev/lodge/appcast.xml' "$ROOT/Lodge/Info.plist"
grep -q '9Y5ssl+tCdpqaggzyIUbmUkGlcm77uCP8TvU4QcjmR4=' "$ROOT/Lodge/Info.plist"
grep -q 'https://pub-dc943f7d0c2042e992edc65b72cb7efe.r2.dev/lodge/Lodge-1.0.dmg' "$ROOT/appcast.xml"
if grep -q '\.zip' "$ROOT/appcast.xml"; then
    echo "appcast.xml still names a zip" >&2
    exit 1
fi
item_count="$(grep -c '<item>' "$ROOT/release/appcast.xml" || true)"
if [[ "$item_count" != "1" ]]; then
    echo "release/appcast.xml should have exactly one item (found ${item_count:-0})" >&2
    exit 1
fi
grep -q '<sparkle:version>7</sparkle:version>' "$ROOT/release/appcast.xml"
grep -q 'url="https://pub-dc943f7d0c2042e992edc65b72cb7efe.r2.dev/lodge/Lodge-1.0.dmg"' "$ROOT/release/appcast.xml"
if ! grep -q 'sparkle:edSignature="[^"][^"]*"' "$ROOT/release/appcast.xml"; then
    echo "release/appcast.xml enclosure is missing an edSignature" >&2
    exit 1
fi

cd "$WORK"
swift test
