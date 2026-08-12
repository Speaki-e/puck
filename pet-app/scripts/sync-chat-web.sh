#!/bin/sh
# Builds ../chat-web and copies its static dist/ into PuckClient's bundle
# resources (PuckClient/Resources/ChatWeb), the same folder-resource pattern
# project.yml already uses for Avatars/Toys. Run before generate.sh/xcodebuild
# whenever chat-web's source changes -- Xcode has no idea chat-web exists as
# a build dependency, so this has to be a separate, explicit step.
set -e
cd "$(dirname "$0")/.."

CHAT_WEB_DIR="../chat-web"
DEST="PuckClient/Resources/ChatWeb"

if [ ! -d "$CHAT_WEB_DIR" ]; then
    echo "error: $CHAT_WEB_DIR not found (expected at ../chat-web relative to pet-app)" >&2
    exit 1
fi

(cd "$CHAT_WEB_DIR" && pnpm install --silent && pnpm run build)

rm -rf "$DEST"
mkdir -p "$DEST"
cp -R "$CHAT_WEB_DIR/dist/." "$DEST/"

echo "synced $CHAT_WEB_DIR/dist -> $DEST"
