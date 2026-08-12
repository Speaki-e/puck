//
//  AppDelegate+Bridge.swift
//  Puck
//
//  F11/F3 · owner: 강상우 (Sangwoo Kang) / 박해영 (Haeyoung Park)
//  Socket server setup and F11/F3 event-reaction routing into
//  character/sfx/avatar and notice bubbles.
//

import Foundation

extension AppDelegate {
    // MARK: - Bridge (socket server, F11/F3 event routing)

    func setUpBridgeServer() {
        guard let toolExecutor else { return }

        let router = BridgeMessageRouter(toolExecutor: toolExecutor)
        router.onEventReaction = { [weak self] reaction in self?.applyEventReaction(reaction) }
        // onClientUpdate/onChatEvent go unset here -- PuckClient's own
        // ClientWindowStore consumes those now (2026-07-30), fed by its own
        // BridgeSocketClient connection, not this in-process router. This
        // router's job is back to just the pet's own reactions + relaying
        // (BridgeServer.relay handles the actual forwarding to whichever
        // gui-role connections are attached).
        bridgeMessageRouter = router

        let server = BridgeServer()
        server.onFailure = { error in
            AppLogger.shared.log(.error, "BridgeServer failed: \(error)")
        }
        server.onMalformedLine = {
            AppLogger.shared.log(.warning, "BridgeServer: dropped a malformed line from a client")
        }
        server.onGUIPresenceChanged = { [weak self] hasGUI in
            guard hasGUI else { return }
            // Fires on BridgeServer's own queue, and send() takes that queue
            // synchronously -- hop off it before sending, or it deadlocks.
            DispatchQueue.main.async {
                guard let self, let pending = self.pendingClientMirror else { return }
                self.pendingClientMirror = nil
                self.bridgeServer?.send(pending, to: .gui)
            }
        }
        server.onMessage = { message, connection in
            // Delivered on BridgeServer's background queue. The router hops to
            // main before touching anything (RealityKit, NSWorkspace,
            // WindowListWatcher) — do not add main-thread work here.
            router.handle(message) { reply in connection.send(reply) }
        }

        do {
            try server.start()
            bridgeServer = server
        } catch {
            // Independence principle: pet-app still works as a pure desktop
            // pet even if the socket can't be set up.
            AppLogger.shared.log(.error, "BridgeServer failed to start: \(error)")
        }
    }

    func applyEventReaction(_ reaction: EventReaction) {
        if let kind = reaction.stateTransition {
            characterController?.transition(to: kind)
        }
        if let sfxKey = reaction.sfxKey {
            sfxPlayer?.trigger(sfxKey, loop: false)
        }
        if let emotion = reaction.emotion {
            avatar?.showEmotion(emotion)
        }
        if reaction.jump {
            characterBody?.triggerJump()
        }
        if let bubbleText = reaction.bubbleText {
            showAgentSummaryBubble(bubbleText)
        }
    }

    /// 02_pet-app.md F3: agent_done(ok=true) shows its summary in a "말풍선"
    /// -- reuses TextInputBubbleView's read-only notice mode (its own doc
    /// comment already anticipated this exact use, found via spec
    /// cross-check), same pattern as showWorkspaceOfflineBubble.
    private func showAgentSummaryBubble(_ summary: String) {
        // Longer than the 2.5s "workspace offline" notice -- a summary is
        // meant to actually be read, not just glanced at.
        showNoticeBubble(summary, for: 5.0)
    }

    /// The one timed-notice path (agent summary, workspace offline, mute
    /// sulk). Both handlers are reassigned on every show, not just set once:
    /// the bubble window is shared, so an input session's dismissal (which
    /// unpins the pet) would otherwise still be attached when a notice shows.
    func showNoticeBubble(_ message: String, for duration: TimeInterval, onExpire: (() -> Void)? = nil) {
        guard let (bubbleWindow, bubbleView) = makeBubble() else { return }

        bubbleView.onCancel = { bubbleWindow.closeAndYieldFocus() }
        // Cleared, not reassigned: onDismiss fires from resignKey, and speech
        // never takes key in the first place. Left pointing at an input
        // session's dismissal it would also unpin the pet out from under a
        // notice.
        bubbleWindow.onDismiss = nil
        bubbleView.showMessage(message)
        // Sized and placed *after* showMessage, which is what decides the
        // typography the size is measured from.
        anchorBubbleToPet(bubbleWindow, size: TextInputBubbleView.speechSize(for: message))
        bubbleWindow.showSpeech()
        DispatchQueue.main.asyncAfter(deadline: .now() + duration) { [weak bubbleWindow] in
            bubbleWindow?.closeAndYieldFocus()
            onExpire?()
        }
    }

    /// How long the pet sulks about being muted.
    private static let mutedComplaintDuration: TimeInterval = 2

    /// byeolki (2026-07-31): muting the pet mid-session gets a sulk -- the
    /// angry face plus "제 목소리가 시끄러우신거에요?" for two seconds.
    ///
    /// It has to be a bubble rather than a line: the complaint is *about*
    /// being muted, so playing it as audio is the one thing that can't work.
    ///
    /// Only on mute going ON, only from the Settings toggle (Focus's
    /// auto-mute, which sets SFXPlayer directly rather than through the
    /// store, isn't the user telling the pet to be quiet), and only when
    /// SettingsStore.isMuteComplaintEnabled is on -- byeolki, 2026-08-01:
    /// "그거 그냥 캐릭터 이동 없이 현재 캐릭터에 뜨게 해주고, 이런거 설정
    /// 가능하도록 해줘". This used to also drag the pet to center screen
    /// (moveCharacter to controller.roamableArea's midpoint); that's gone --
    /// the sulk now happens wherever the pet already is. pinCharacter is
    /// still what holds it there for the duration, since a wandering pet
    /// mid-sulk would read as broken either way.
    func showMutedComplaint() {
        guard characterController != nil else { return }

        // pinCharacter, not a raw .pinned transition -- it owns the
        // stateBeforePin bookkeeping, so a hotkey pin overlapping the sulk
        // can't corrupt that pairing. Transition first, then the emotion:
        // entering a state plays that state's own clip, which would otherwise
        // wipe the angry face immediately.
        pinCharacter()
        avatar?.showEmotion("angry")

        showNoticeBubble("제 목소리가 시끄러우신거에요?", for: Self.mutedComplaintDuration) { [weak self] in
            // Falling is also what puts the face back: entering Fall plays the
            // fall clip, so the sulk ends without anyone having to remember
            // which expression the pet was wearing before it. The pin
            // bookkeeping is discarded rather than restored -- resuming a
            // pre-sulk walk in mid-air would be wrong.
            self?.stateBeforePin = nil
            self?.characterController?.transition(to: .fall)
        }
    }
}
