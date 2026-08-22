//
//  VoiceInputController.swift
//  Puck
//
//  owner: 박해영 (Haeyoung Park)
//  Single class owning both the PTT key event and the recording lifecycle
//

import Foundation

/// What VoiceInputController needs from F7's speech recognition — kept as a
/// protocol so this class is testable without a real mic/Speech framework.
protocol SpeechRecognitionServicing: AnyObject {
    var onPartialResult: ((String) -> Void)? { get set }
    var onFinalResult: ((String) -> Void)? { get set }
    var onError: ((Error) -> Void)? { get set }
    func startStreaming()
    func stopStreaming()
}

/// Owns the PTT key event and the recording lifecycle together (deliberate
/// single-owner design per plan/02_pet-app.md F7). Holds shorter than
/// `minimumHoldDuration` still occupy the mic for their (brief) duration —
/// "마이크 점유는 홀드 구간 한정" — but their eventual final transcription is
/// discarded rather than submitted, treating them as an accidental tap.
final class VoiceInputController {
    static let minimumHoldDuration: TimeInterval = 0.3

    private let speechService: SpeechRecognitionServicing
    private let now: () -> TimeInterval
    private var pressStartUptime: TimeInterval?
    private var heldLongEnough = false
    private var isActive = false

    /// Enter Listen state + listen_start SFX (F3/F5's responsibility to react to this).
    var onListenStart: (() -> Void)?
    /// Return to whichever state was active before Listen.
    var onListenEnd: (() -> Void)?
    /// Live captions shown in the text bubble while holding.
    var onPartialText: ((String) -> Void)?
    /// The submitted transcription — protocol 3.3 user_input(source: "voice").
    var onFinalText: ((String) -> Void)?
    /// Speech-service errors (e.g. recognizer unavailable, audio engine
    /// failed to start) -- previously dropped silently, leaving the FSM
    /// stuck in ListenState with no feedback until a manual key release.
    var onError: ((Error) -> Void)?

    init(speechService: SpeechRecognitionServicing, now: @escaping () -> TimeInterval = { ProcessInfo.processInfo.systemUptime }) {
        self.speechService = speechService
        self.now = now
        speechService.onPartialResult = { [weak self] text in self?.onPartialText?(text) }
        speechService.onFinalResult = { [weak self] text in
            guard self?.heldLongEnough == true else { return }
            self?.onFinalText?(text)
        }
        speechService.onError = { [weak self] error in
            guard let self else { return }
            self.onError?(error)
            if self.isActive {
                self.isActive = false
                self.pressStartUptime = nil
                self.onListenEnd?()
            }
        }
    }

    /// Idempotent -- defense in depth alongside GlobalHotkeyManager's own
    /// key-repeat guard. A duplicate down while already active must not
    /// slide the hold-start time forward or restart streaming.
    func pushToTalkDown() {
        guard !isActive else { return }
        isActive = true
        pressStartUptime = now()
        heldLongEnough = false
        onListenStart?()
        speechService.startStreaming()
    }

    func pushToTalkUp() {
        guard isActive else { return }
        isActive = false
        defer { pressStartUptime = nil }
        if let start = pressStartUptime, now() - start >= Self.minimumHoldDuration {
            heldLongEnough = true
        }
        speechService.stopStreaming()
        onListenEnd?()
    }
}
