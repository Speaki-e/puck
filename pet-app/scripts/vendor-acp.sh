#!/bin/sh
# Bundles the two ACP agents into single .mjs files inside Puck's resources,
# so AcpAgentProcess can run them with a plain `node <file>` and pet-app needs
# no node_modules at runtime.
#
# Why bundled rather than shipped as node_modules: the packages pull ~40 deps
# between them, and a node_modules tree inside an .app bundle is both large and
# awkward to sign. esbuild flattens each to one file (claude 2.2MB, codex
# 1.1MB), which is small enough to commit -- and committing them is the point:
# a fresh checkout builds Puck with Xcode alone, no npm step, the same way
# ChatWeb's built bundle is committed rather than built by Xcode.
#
# Run this only when bumping the pinned versions in scripts/acp/package.json,
# then commit the regenerated .mjs files. This is the one Node dependency left
# in the repo, and it is build-time only.
#
# ## codex needs the codex CLI, which is NOT vendored
#
# @agentclientprotocol/codex-acp is only a shim: it spawns the real `codex`
# binary, which ships as a 262MB per-platform native package (@openai/codex).
# Vendoring that would multiply the app's size for one optional agent, so
# AcpAgentProcess points codex-acp at the user's own install through CODEX_PATH
# instead (codex-acp reads it -- see startCodexConnection). No codex on the
# machine means the codex agent is unavailable; claude is unaffected.
set -e
cd "$(dirname "$0")/.."

VENDOR_DIR="scripts/acp"
DEST="Puck/Resources"

if ! command -v npm > /dev/null 2>&1; then
    echo "error: npm is required to regenerate the ACP bundles (build-time only)." >&2
    echo "       The committed Puck/Resources/acp-*.mjs are what the app actually ships;" >&2
    echo "       you only need this script when bumping scripts/acp/package.json." >&2
    exit 1
fi

(cd "$VENDOR_DIR" && npm install --silent --no-audit --no-fund)

ESBUILD="$VENDOR_DIR/node_modules/.bin/esbuild"

bundle() {
    package="$1"
    output="$2"
    entry="$VENDOR_DIR/node_modules/$package/dist/index.js"
    if [ ! -f "$entry" ]; then
        echo "error: $entry not found after npm install" >&2
        exit 1
    fi
    # --format=esm and the .mjs extension both matter: the packages are ESM,
    # and node decides module vs script by extension when given a bare path.
    "$ESBUILD" "$entry" \
        --bundle \
        --platform=node \
        --format=esm \
        --outfile="$DEST/$output" \
        --log-level=warning
    echo "bundled $package -> $DEST/$output"
}

mkdir -p "$DEST"
bundle "@agentclientprotocol/claude-agent-acp" "acp-claude.mjs"
bundle "@agentclientprotocol/codex-acp" "acp-codex.mjs"

# Smoke test: an agent that can't answer `initialize` is not worth shipping,
# and this catches a bundling regression (a dynamic require esbuild couldn't
# see) at build time rather than the first time someone asks for an edit.
if command -v node > /dev/null 2>&1; then
    probe='{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersion":1,"clientCapabilities":{}}}'
    if ! printf '%s\n' "$probe" | node "$DEST/acp-claude.mjs" 2>/dev/null | grep -q '"protocolVersion"'; then
        echo "error: acp-claude.mjs did not answer initialize" >&2
        exit 1
    fi
    echo "smoke test: acp-claude.mjs answers initialize"
    # codex-acp is deliberately not probed here -- it needs the codex CLI,
    # which this machine may not have, and its absence is not a bundling bug.
fi
