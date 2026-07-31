# QA scenarios

Source: the "아바타 리소스 소비" (Avatar Resource Consumption) section of `plan/02_pet-app.md`. Run each
scenario at every milestone by Team 1 (강상우 · 박해영).

- [ ] Landing on overlapping windows — with several windows overlapping, does
      the character land only on the top edge of the window that's actually
      visible at its x-coordinate (`LandingSurfaceResolver`)?
- [ ] Falling on window minimize/close — does WalkOnTop transition to Fall
      when its supporting window is minimized or closed?
- [ ] Multi-display boundaries — does movement across display boundaries in
      `GlobalScreenSpace`'s normalized coordinate space stay seamless?
- [ ] Full-screen Spaces — verify overlay window behavior (follow / stay /
      whatever the policy is) when switching to another Space, including
      full-screen apps.
- [ ] Hotkey conflicts — does `HotkeyBindings`' conflict check work when
      PTT / text input / character-summon hotkeys clash with system or other
      apps' hotkeys?
- [ ] Socket reconnection — when `workspace` reconnects with exponential
      backoff (1s -> 2s -> 4s, max 30s), does `BridgeServer`'s state
      transition correctly (connection lost -> pure pet mode -> reconnected)?

## Milestone tie-in

- Up through M-A (moving across the screen/windows without a socket), verify
  the socket-independent scenarios first (overlapping-window landing, window
  fall, multi-display, full-screen Space, hotkey conflicts) using the dummy
  development avatar (`Shaydi/Resources/Avatars/dummy/`).
- Verify the socket reconnection scenario after P7 (socket server + F11
  executor), at the point of integration with the `workspace` repo.
