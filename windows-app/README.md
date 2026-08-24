# Puck for Windows

This directory is the Windows-native product shell for Puck. The macOS apps remain under `pet-app/` and are intentionally untouched.

## Architecture

- **Electron main process** owns Windows-only capabilities: windows, file-system access, Git, and ConPTY-backed PowerShell through `node-pty`.
- **React renderer** owns the client UI.
- **Monaco Editor** replaces the macOS-only CodeEditSourceEditor dependency.
- **xterm.js** renders the terminal while `node-pty` runs `pwsh.exe`/`powershell.exe` in the selected workspace.
- A second transparent, always-on-top Electron window is the Windows pet surface. It is deliberately separate from the client window so desktop-control/animation work can evolve without destabilising the editor.
- Renderer code has no Node.js access. Privileged operations are exposed through the narrow `preload.cjs` IPC bridge and file access is constrained to the active workspace.

## Current Windows milestone

Working in this branch:

- choose/refresh a workspace folder;
- recursive Explorer tree with common generated folders ignored;
- open multiple text files in Monaco tabs;
- edit and save with `Ctrl+S`;
- Git branch/change count in the status bar;
- integrated PowerShell terminal using a real Windows PTY;
- transparent always-on-top pet surface that can reopen the client;
- NSIS + portable `.exe` packaging;
- Windows GitHub Actions build.

The right-side Agent panel is the intentional seam for the next porting step. The existing Swift `AgentHost`, local-socket bridge, Accessibility/AppleScript tools and sprite physics are macOS-specific and must not be copied behind fake compatibility shims. They will be ported to Windows APIs/Node processes separately.

## Development

Requirements: Windows 10/11, Node.js 22+, npm, Git. Visual Studio Build Tools may be required if `node-pty` has to build locally.

```powershell
cd windows-app
npm install
npm run dev
```

## Verify

```powershell
npm run typecheck
npm run build
npm run dist
```

Installer/portable outputs are written by electron-builder under `windows-app/release/`.
