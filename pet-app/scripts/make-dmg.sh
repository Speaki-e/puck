#!/bin/sh
# Builds Puck + PuckClient in Release and packs both into one .dmg, ready to
# attach to a GitHub release.
#
# The two apps are one product: they speak a private protocol to each other
# over bridge.sock and neither is useful alone, so they ship together in one
# image rather than as two downloads that can drift apart.
#
# Nothing here touches /Applications or the running pair -- that is
# install.sh's job. This only writes build/Puck-<version>.dmg.
#
# Signing: the same identity install.sh uses, which for a personal team is an
# "Apple Development" certificate. That is enough to run *here* and not enough
# to hand to anybody else: an Apple Development signature is only valid on
# devices registered to the team, and a downloaded app is quarantined on top
# of that. Shipping this to other people needs a Developer ID Application
# certificate and notarisation -- set SIGN_IDENTITY to use one:
#
#   SIGN_IDENTITY="Developer ID Application: NAME (TEAMID)" scripts/make-dmg.sh
#
# and then notarise and staple the .dmg (xcrun notarytool submit --wait,
# xcrun stapler staple).
set -e
cd "$(dirname "$0")/.."

if [ -z "${DEVELOPMENT_TEAM}" ]; then
    DEVELOPMENT_TEAM=$(security find-certificate -c "Apple Development" -p 2>/dev/null \
        | openssl x509 -noout -subject 2>/dev/null \
        | tr ',' '\n' | sed -n 's/.*OU=\([A-Z0-9]*\).*/\1/p' | head -1)
fi
if [ -z "${DEVELOPMENT_TEAM}" ]; then
    echo "error: no Apple Development certificate found and DEVELOPMENT_TEAM is unset." >&2
    exit 1
fi
export DEVELOPMENT_TEAM

xcodegen generate

# Same one-off as install.sh: SwiftTerm ships a Metal shader, and a machine
# that has never built one dies with "cannot execute tool 'metal'".
if ! xcrun -f metal > /dev/null 2>&1; then
    echo "note: downloading the Metal toolchain (once per machine)"
    xcodebuild -downloadComponent MetalToolchain
fi

DERIVED=$(mktemp -d)
STAGE=$(mktemp -d)
BUILD_LOG=$(mktemp)
trap 'rm -f "$BUILD_LOG"; rm -rf "$DERIVED" "$STAGE"' EXIT

SIGN_ARGS=""
if [ -n "${SIGN_IDENTITY}" ]; then
    # An explicit identity means a distribution build: manual signing, or
    # Xcode picks the development certificate back up on its own.
    SIGN_ARGS="CODE_SIGN_STYLE=Manual CODE_SIGN_IDENTITY=${SIGN_IDENTITY}"
    echo "note: signing with ${SIGN_IDENTITY}"
else
    echo "note: signing with team ${DEVELOPMENT_TEAM} (development identity -- see the header)"
fi

for scheme in Puck PuckClient; do
    # shellcheck disable=SC2086 -- SIGN_ARGS is deliberately word-split.
    if ! xcodebuild build \
        -project Puck.xcodeproj \
        -scheme "$scheme" \
        -configuration Release \
        -destination 'platform=macOS' \
        -derivedDataPath "$DERIVED" \
        -skipPackagePluginValidation \
        DEVELOPMENT_TEAM="$DEVELOPMENT_TEAM" \
        $SIGN_ARGS \
        > "$BUILD_LOG" 2>&1
    then
        echo "error: $scheme failed to build." >&2
        cat "$BUILD_LOG" >&2
        exit 1
    fi
done

PRODUCTS="$DERIVED/Build/Products/Release"
# The resources the code looks up by name at runtime. A .dmg is the one place
# a missing one cannot be fixed by rebuilding, so it is checked before the
# image is written rather than discovered by whoever downloads it.
scripts/check-resources.sh "$PRODUCTS"

for app in Puck PuckClient; do
    if [ ! -d "$PRODUCTS/$app.app" ]; then
        echo "error: $app.app is missing from the build output." >&2
        exit 1
    fi
    if ! codesign --verify --strict "$PRODUCTS/$app.app" 2>/dev/null; then
        echo "error: the $app.app that was just built is not correctly signed." >&2
        exit 1
    fi
    cp -R "$PRODUCTS/$app.app" "$STAGE/"
done

# Drag-to-install: the window shows both apps and the folder they go in.
ln -s /Applications "$STAGE/Applications"

VERSION=$(/usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" \
    "$PRODUCTS/Puck.app/Contents/Info.plist" 2>/dev/null || echo "0.0")
mkdir -p build
DMG="build/Puck-$VERSION.dmg"
rm -f "$DMG"

# UDZO: compressed and read-only, which is what a download should be.
hdiutil create \
    -volname "Puck $VERSION" \
    -srcfolder "$STAGE" \
    -fs HFS+ \
    -format UDZO \
    -ov \
    "$DMG" > /dev/null

echo "built: $DMG ($(du -h "$DMG" | cut -f1))"
if [ -z "${SIGN_IDENTITY}" ]; then
    echo "warning: signed for development only -- this will not launch on anyone else's Mac." >&2
    echo "         See the header for what distributing it actually needs." >&2
fi
