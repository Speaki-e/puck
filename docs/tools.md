# Tool registry

Source of truth for the data: [`../src/types/tools.ts`](../src/types/tools.ts) (`TOOL_REGISTRY`).
This document explains it; the registry data is normative — ai-module imports it rather
than hardcoding a copy.

| Tool | Params | Executor | Approval | timeout_sec | Summary |
|---|---|---|---|---|---|
| launch_app | `app_name` or `bundle_id` (`bundle_id` wins if both given) | pet-app | not required | 15 | Launch an app, return its pid |
| list_running_apps | – | pet-app | not required | 5 | List running apps |
| get_frontmost_window | – | pet-app | not required | 5 | Info about the frontmost window |
| find_ui_element | `pid` + (`role` or `title_contains`) | pet-app | not required | 15 | Query Accessibility, returns `{role,title,frame,enabled}` (not found is `ok=true data=null`, not a failure) |
| point_at | `frame` | pet-app | not required | 30 | Pet walks to the coordinate and points. Replies once Point actually starts |
| click_element | `frame` | pet-app | required | 15 | Synthesized CGEvent click at frame's center. System dialogs reply `not_supported_target` |
| run_shell | `command` | pet-app | required (whitelist exceptions) | 60 | Run a shell command, returns stdout/stderr/exit code |
| run_applescript | `script` | pet-app | required | 60 | Run an AppleScript |
| code_editor | `task` (natural language), `project_path` | workspace | uses ACP's internal approval flow | 600 | Delegate a coding task to Claude Code, returns a summary |
| open_in_editor | `path` | workspace | not required | 10 | Open a file as a Monaco tab |
| read_file | `path` | workspace | not required | 10 | Return a file's contents (read-only) |

## `frame` coordinate convention

Every `frame` (`{"x":_,"y":_,"width":_,"height":_}`) is in Quartz global screen
coordinates — primary display top-left origin, Y down, points. Same space as
CGWindowList/Accessibility APIs. `find_ui_element`'s response and `point_at`/`click_element`'s
arguments all use this space (**not** AppKit's bottom-left origin).

## Response (`tool_result.data`) shapes

`timeout_sec` is not carried on the wire (see [socket.md](socket.md): the *sender* owns the
timeout). A receiver still needs a bound that is not tighter than the registry's, so Swift
consumers read [`../swift/ToolTimeouts.swift`](../swift/ToolTimeouts.swift), a mirror of this
column. Change a timeout here and in `src/types/tools.ts` and that mirror together.

The table above is the normative param/executor/approval/timeout contract; this section
fills in a gap the table doesn't cover — what each tool's success payload actually looks
like. Most tools return an object or `null`. One does not:

| Tool | `data` on success |
|---|---|
| launch_app | `{ pid: number }` |
| list_running_apps | `Array<{ pid, name, bundle_id }>` |
| get_frontmost_window | `null` if none, else `{ owner_name, title, frame }` |
| find_ui_element | `null` if not found, else `{ role, title, frame?, enabled? }` |
| point_at | `null` |
| click_element | `null`. Spec: returns `not_supported_target` for system dialog targets, falling back to `point_at` plus user guidance. **Not yet implemented in pet-app** as of this writing — classifying "is this a system security dialog" needs AX role/owner inspection pet-app doesn't have yet, so it currently always attempts the click regardless of target. |
| run_shell | `{ stdout, stderr, exit_code }` |
| **run_applescript** | **a bare string** — the script's result, e.g. `"data":"some result"`. This is the one tool whose payload is not an object; consumers must not assume `tool_result.data` is always an object or null. |
| code_editor | TBD — workspace hasn't shipped this yet |
| open_in_editor | TBD — workspace hasn't shipped this yet |
| read_file | TBD — workspace hasn't shipped this yet |

The three `workspace`-executed tools are marked TBD because the workspace repo has no
implementation yet as of this writing — don't treat those response shapes as settled
contract. Update this table (and `tools.ts`'s `responseNote` field) once workspace ships
them.

## Notes

- Tool `description` text shown to the model is owned by ai-module (정가은), but any
  addition/change to the tool list, its params, or its executor must land here first via PR.
- `click_element`'s description must include the fallback guidance: it does not work on
  system permission dialogs, so fall back to `point_at` plus a prompt for the user to click
  manually in that case.
