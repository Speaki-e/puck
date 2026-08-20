# Verification and release gates

This file is the current source of truth for deciding whether Puck is ready to
ship. The M-A and M-B labels mentioned in the 2026-08-12 audit belong to the
retired five-repository architecture. They are historical evidence, not current
completion badges.

## Automated gate

Run from a clean checkout:

```sh
sh pet-app/scripts/test.sh
```

The gate passes only when the command exits with status 0, Xcode reports no
test failures, and the separate PuckClient scheme builds. The same command runs
on every pull request and every push to `main` through the `macOS tests` GitHub
Actions workflow.

The suite includes two architecture regressions that matter to the current
single-repository app:

- `IdleFrameRatePolicyTests` keeps the CALayer/FSM heartbeat at 30 Hz while
  active and 15 Hz after sustained idle. This replaces the obsolete
  RealityKit-era 60 Hz assumption without disabling timer-driven behavior.
- `AcpAgentProcessSandboxTests` launches a real child process, proves it can
  write inside the selected project, and proves an attempted sibling write
  does not create a file. Protocol event checks remain as defense in depth.

## Manual release smoke test

Automated tests cannot prove that permissions, vendor logins, animation, and
window interaction work in a signed desktop session. Before a release, record
one pass of every item below on the supported macOS version:

- Build and install both apps from a clean checkout with
  `pet-app/scripts/install.sh`.
- Launch Puck and PuckClient; confirm the pet moves, becomes idle, and resumes
  smoothly after interaction.
- Send one chat turn through each model provider that the release supports.
- Open a project, read and edit a file in the native editor, then run
  `code_editor` on that project.
- Ask `code_editor` to write to a sibling directory and confirm the operation
  is denied and no file is created there.
- Trigger an approval-required tool and confirm allow and deny both resume the
  waiting turn correctly.
- Remove or hide an optional vendor CLI and confirm the UI reports that only
  `code_editor` is unavailable rather than breaking the rest of the app.

## Evidence record

| Gate | Latest evidence | Status |
|---|---|---|
| Full automated suite | Local run on 2026-08-19 via `pet-app/scripts/test.sh` | Pass |
| 2D frame policy regression | Focused XCTest run on 2026-08-19 | Pass |
| ACP filesystem containment | Real child-process XCTest run on 2026-08-19 | Pass |
| Clean-checkout CI | Workflow added; first remote run not yet available | Pending |
| Signed-app manual smoke test | No current recording attached | Pending |

A release is ready only when every row is `Pass`. For remote or manual runs,
replace the pending text with a durable link to the workflow run or recording;
do not infer a pass from an older architecture's badge.
