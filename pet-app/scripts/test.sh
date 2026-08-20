#!/bin/bash
# Runs the whole PuckTests suite, unattended, from any directory.
#
# Why this exists rather than a bare `xcodebuild test`: the vendored
# CodeEditSourceEditor/CodeEditTextView packages carry a SwiftLint build tool
# plugin, and an untrusted plugin fails the *build* ("Plugin \"SwiftLint\" from
# package \"SwiftLintPlugin\" must be enabled before it can be used"), so
# testing is cancelled before a single test runs. Trusting it is a GUI prompt
# in Xcode, which a terminal has no way to answer. -skipPackagePluginValidation
# skips it -- the same flag scripts/install.sh already passes, and it only
# affects those vendored packages' linting, never Puck's own sources or tests.
set -euo pipefail
cd "$(dirname "$0")/.."

# Puck.xcodeproj is generated from project.yml and deliberately untracked (it
# embeds a per-developer DEVELOPMENT_TEAM), so a fresh clone -- CI included --
# has no project to test until xcodegen has run.
[ -d Puck.xcodeproj ] || scripts/generate.sh

xcodebuild test \
    -project Puck.xcodeproj \
    -scheme Puck \
    -destination 'platform=macOS' \
    -skipPackagePluginValidation \
    CODE_SIGNING_ALLOWED=NO

# PuckClient is a separate application target, so compiling PuckTests alone
# cannot prove its target membership and app entry point still build.
xcodebuild build \
    -project Puck.xcodeproj \
    -scheme PuckClient \
    -destination 'platform=macOS' \
    -skipPackagePluginValidation \
    CODE_SIGNING_ALLOWED=NO
