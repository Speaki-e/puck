#!/bin/sh
# Builds Puck + PuckClient signed with your Apple Development
# certificate and installs both into /Applications.
#
# Why not just run the Debug build out of DerivedData: macOS ties TCC grants
# (Accessibility above all) to the code signature, and an *ad-hoc* signature
# changes on every build -- so every rebuild silently revoked Accessibility
# and the global hotkey stopped working until it was re-granted by hand.
# Signing with a real (even free, personal-team) Apple Development identity
# keeps the signature stable, so the grant survives rebuilds. Grant it once
# to /Applications/Puck.app and this script can then reinstall as often
# as it likes.
#
# DEVELOPMENT_TEAM is read from the environment if set, otherwise taken from
# the Apple Development certificate in your keychain.
set -e
cd "$(dirname "$0")/.."

if [ -z "${DEVELOPMENT_TEAM}" ]; then
    DEVELOPMENT_TEAM=$(security find-certificate -c "Apple Development" -p 2>/dev/null \
        | openssl x509 -noout -subject 2>/dev/null \
        | tr ',' '\n' | sed -n 's/.*OU=\([A-Z0-9]*\).*/\1/p' | head -1)
fi

if [ -z "${DEVELOPMENT_TEAM}" ]; then
    echo "error: no Apple Development certificate found and DEVELOPMENT_TEAM is unset."
    echo "       Sign in to Xcode with an Apple ID (Settings > Accounts) to get one;"
    echo "       an ad-hoc build works too, but loses Accessibility on every rebuild."
    exit 1
fi
export DEVELOPMENT_TEAM
echo "note: signing with team ${DEVELOPMENT_TEAM}"

xcodegen generate

DERIVED=$(mktemp -d)
for scheme in Puck PuckClient; do
    xcodebuild build \
        -project Puck.xcodeproj \
        -scheme "$scheme" \
        -configuration Release \
        -destination 'platform=macOS' \
        -derivedDataPath "$DERIVED" \
        -skipPackagePluginValidation \
        DEVELOPMENT_TEAM="$DEVELOPMENT_TEAM" \
        > /dev/null
done

# Quit before replacing: copying over a running bundle leaves the old process
# running against files that no longer exist. Wait for them to actually go --
# a fixed sleep raced the old Puck's shutdown, and the new one then found
# bridge.sock's lock file still held ("BridgeServer failed to start:
# alreadyRunning") and came up with no socket at all.
pkill -x PuckClient || true
pkill -x Puck || true
for _ in $(seq 1 50); do
    pgrep -x Puck > /dev/null || break
    sleep 0.2
done

# Resources the code looks up by name at runtime, per app. A missing one is
# not a build error -- Bundle.url(forResource:) just returns nil and the
# feature fails at the moment someone uses it. That is exactly how PuckClient
# shipped without the ACP agents while Puck.app carried the copies it never
# uses: the Puck target sources the whole Puck/ folder and picked them up
# implicitly, PuckClient lists files one by one and had not been told.
#
# The unit tests cannot catch this. They resolve against the test bundle,
# which is built from the Puck target and therefore always has everything.
check_resource() {
    if [ ! -e "$DERIVED/Build/Products/Release/$1.app/Contents/Resources/$2" ]; then
        echo "error: $1.app is missing Resources/$2" >&2
        echo "       Add it to that target's sources in project.yml." >&2
        exit 1
    fi
}
# PuckClient runs code_editor and shows the editor pane, so it needs both.
check_resource PuckClient acp-claude.mjs
check_resource PuckClient acp-codex.mjs
check_resource PuckClient FileIcons/icon-map.json
check_resource Puck Avatars

for app in Puck PuckClient; do
    rm -rf "/Applications/$app.app"
    cp -R "$DERIVED/Build/Products/Release/$app.app" /Applications/
done

# Un-register the copies we just built before deleting them, and any other
# copy of these bundle ids lying around (Xcode's own DerivedData, earlier runs
# of this script).
#
# Why this matters: LaunchServices indexes every app bundle it sees, keyed by
# bundle id, and both CompanionAppLauncher and `open -b` ask it -- not us --
# which copy to launch. Left alone it accumulated 18 registrations pointing at
# deleted mktemp dirs plus a live Xcode build, and picked whichever it liked:
# the pet would launch a *stale* client, which is what made a fresh icon look
# like it hadn't updated at all. /Applications has to be the only answer.
LSREGISTER="/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister"
if [ -x "$LSREGISTER" ]; then
    "$LSREGISTER" -dump 2>/dev/null \
        | grep -oE "/[^ ]*/(Puck|PuckClient)\.app" \
        | sort -u \
        | grep -v '^/Applications/' \
        | while IFS= read -r stale; do "$LSREGISTER" -u "$stale" 2>/dev/null || true; done
    "$LSREGISTER" -f /Applications/Puck.app /Applications/PuckClient.app 2>/dev/null || true
fi

rm -rf "$DERIVED"

open /Applications/Puck.app
echo "installed: /Applications/Puck.app, /Applications/PuckClient.app"
