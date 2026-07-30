#!/bin/sh
# Builds PetAgent + PetAgentClient signed with your Apple Development
# certificate and installs both into /Applications.
#
# Why not just run the Debug build out of DerivedData: macOS ties TCC grants
# (Accessibility above all) to the code signature, and an *ad-hoc* signature
# changes on every build -- so every rebuild silently revoked Accessibility
# and the global hotkey stopped working until it was re-granted by hand.
# Signing with a real (even free, personal-team) Apple Development identity
# keeps the signature stable, so the grant survives rebuilds. Grant it once
# to /Applications/PetAgent.app and this script can then reinstall as often
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
for scheme in PetAgent PetAgentClient; do
    xcodebuild build \
        -project PetAgent.xcodeproj \
        -scheme "$scheme" \
        -configuration Release \
        -destination 'platform=macOS' \
        -derivedDataPath "$DERIVED" \
        DEVELOPMENT_TEAM="$DEVELOPMENT_TEAM" \
        > /dev/null
done

# Quit before replacing: copying over a running bundle leaves the old process
# running against files that no longer exist. Wait for them to actually go --
# a fixed sleep raced the old PetAgent's shutdown, and the new one then found
# bridge.sock's lock file still held ("BridgeServer failed to start:
# alreadyRunning") and came up with no socket at all.
pkill -x PetAgentClient || true
pkill -x PetAgent || true
for _ in $(seq 1 50); do
    pgrep -x PetAgent > /dev/null || break
    sleep 0.2
done

for app in PetAgent PetAgentClient; do
    rm -rf "/Applications/$app.app"
    cp -R "$DERIVED/Build/Products/Release/$app.app" /Applications/
done
rm -rf "$DERIVED"

open /Applications/PetAgent.app
echo "installed: /Applications/PetAgent.app, /Applications/PetAgentClient.app"
