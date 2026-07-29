//
//  CharacterController.swift
//  PetAgent
//
//  F3 · owner: 박해영 (Haeyoung Park)
//  Drives update(dt) every frame; runs and transitions the current StateHandler.
//

import Foundation

/// The minimal interface F5 (Audio/SFXPlayer) will implement. Kept here so the
/// FSM doesn't need to know about the concrete SFX implementation.
protocol SFXTriggering: AnyObject {
    /// Triggers the sound mapped to an FSM clip key or socket event name key
    /// (silent if the manifest's sounds table has no match). `loop` mirrors
    /// AvatarPlayable.play(clip:loop:) — a looping trigger (e.g. "walk")
    /// keeps playing until a *different* loop key is triggered, at which
    /// point F5 fades the old one out (02_pet-app.md F5: "루프 사운드(walk)는
    /// 상태 유지 중 반복, exit()에서 페이드아웃"). One-shot (loop: false)
    /// triggers (react_click, task_success, ...) never interrupt a loop.
    func trigger(_ key: String, loop: Bool)
}

/// Drives and transitions the current StateHandler. On every state entry,
/// AvatarPlayable.play and SFXTriggering.trigger are always called together
/// from the same spot (enterCurrentState) — 02_pet-app.md F3's shared "enter()" requirement.
final class CharacterController {
    private(set) var currentState: StateHandler
    private let body: CharacterBody
    private let sfxPlayer: SFXTriggering

    /// StateKind -> the one long-lived instance for that kind. States are
    /// reused rather than recreated so their timers survive (see EventRouter's
    /// note); a kind with nothing registered is simply not reachable.
    private var states: [StateKind: StateHandler] = [:]

    /// Where the pet may roam, and what it lands on. Set at bootstrap and
    /// refreshed when the display configuration or window list changes.
    var roamableArea: CGRect = .zero
    /// Kept in sync with the live avatar's rendered height -- see
    /// StateContext.avatarHeight.
    var avatarHeight: CGFloat = 0
    var landingY: (CGPoint) -> CGFloat = { _ in .zero }
    /// Refreshed from F4 every frame by the bootstrap wiring.
    var windows: () -> [WindowInfo] = { [] }

    /// A state asking to be replaced. Applied after update() returns so a
    /// state never swaps itself out mid-frame.
    private var pendingTransition: StateKind?

    /// Seconds since the current state was entered -- reset on every
    /// transition, fed to AvatarPlayable.updateBounce so the 2D bounce
    /// motion (BouncePreset) knows where in its cycle to be (02_pet-app.md F2).
    private var stateElapsedTime: TimeInterval = 0

    init(initialState: StateHandler, body: CharacterBody, sfxPlayer: SFXTriggering) {
        self.currentState = initialState
        self.body = body
        self.sfxPlayer = sfxPlayer
        enterCurrentState()
    }

    func register(_ state: StateHandler, as kind: StateKind) {
        states[kind] = state
    }

    /// Transition by kind — how states and EventRouter reactions ask, since
    /// neither holds concrete instances.
    func transition(to kind: StateKind) {
        guard let state = states[kind] else {
            // Silent otherwise: a StateKind added later without a matching
            // register(_:as:) call at bootstrap would strand the pet in its
            // current state with zero diagnostic.
            AppLogger.shared.log(.error, "transition(to:) requested unregistered StateKind \(kind) -- ignored")
            return
        }
        transition(to: state)
    }

    /// Allows transitioning from any state to any state (tools/events/PTT/click
    /// can all interrupt at any time — see the section 3 transition table).
    func transition(to newState: StateHandler) {
        guard newState !== currentState || newState.restartsOnReentry else { return }
        currentState.exit()
        currentState = newState
        enterCurrentState()
    }

    func update(dt: TimeInterval) {
        let context = StateContext(
            body: body,
            roamableArea: roamableArea,
            avatarHeight: avatarHeight,
            windows: windows(),
            landingY: landingY,
            requestTransition: { [weak self] kind in self?.pendingTransition = kind }
        )
        currentState.update(dt: dt, context: context)
        stateElapsedTime += dt
        body.updateBounce(clip: currentState.clipKey, elapsed: stateElapsedTime)

        if let kind = pendingTransition {
            pendingTransition = nil
            transition(to: kind)
        }
    }

    private func enterCurrentState() {
        stateElapsedTime = 0
        if !currentState.preservesUpsideDown {
            body.isUpsideDown = false
        }
        body.play(clip: currentState.clipKey, loop: currentState.loopsClip)
        // Use clipKey (e.g. "walk"), not name (e.g. "Walk") — the manifest sounds
        // table is keyed by lowercase clip/event names (protocol section 6), so
        // triggering with the capitalized FSM state name would never match.
        sfxPlayer.trigger(currentState.clipKey, loop: currentState.loopsClip)
        currentState.enter()
    }
}
