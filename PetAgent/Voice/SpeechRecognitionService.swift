//
//  SpeechRecognitionService.swift
//  PetAgent
//
//  F7 · owner: Haeyoung Park
//  SFSpeechAudioBufferRecognitionRequest streaming, on-device first / server fallback
//
//  "On-device first, server fallback" is decided upfront via
//  SFSpeechRecognizer.supportsOnDeviceRecognition rather than reactively
//  retrying after an on-device failure — reactive retry would need to
//  pattern-match specific SFSpeechRecognizer error cases that aren't cleanly
//  documented/stable across macOS versions, so this is the more robust
//  interpretation of the plan's intent.

import Speech
import AVFoundation

final class SpeechRecognitionService: SpeechRecognitionServicing {
    var onPartialResult: ((String) -> Void)?
    var onFinalResult: ((String) -> Void)?
    var onError: ((Error) -> Void)?

    private let recognizer: SFSpeechRecognizer?
    private let audioEngine = AVAudioEngine()
    private var recognitionRequest: SFSpeechAudioBufferRecognitionRequest?
    private var recognitionTask: SFSpeechRecognitionTask?

    /// Defaults to the system locale (ko-KR on a Korean system), per
    /// plan/02_pet-app.md F7 ("언어: 시스템 로케일(ko-KR) 기본, 설정 변경").
    init(locale: Locale = .current) {
        recognizer = SFSpeechRecognizer(locale: locale)
    }

    func startStreaming() {
        guard let recognizer, recognizer.isAvailable else {
            onError?(SpeechRecognitionServiceError.recognizerUnavailable)
            return
        }

        let request = SFSpeechAudioBufferRecognitionRequest()
        request.shouldReportPartialResults = true
        request.requiresOnDeviceRecognition = recognizer.supportsOnDeviceRecognition
        recognitionRequest = request

        let inputNode = audioEngine.inputNode
        let format = inputNode.outputFormat(forBus: 0)
        inputNode.removeTap(onBus: 0)
        inputNode.installTap(onBus: 0, bufferSize: 1024, format: format) { [weak self] buffer, _ in
            self?.recognitionRequest?.append(buffer)
        }

        audioEngine.prepare()
        do {
            try audioEngine.start()
        } catch {
            onError?(error)
            return
        }

        recognitionTask = recognizer.recognitionTask(with: request) { [weak self] result, error in
            guard let self else { return }
            if let result {
                if result.isFinal {
                    onFinalResult?(result.bestTranscription.formattedString)
                } else {
                    onPartialResult?(result.bestTranscription.formattedString)
                }
            }
            if let error {
                onError?(error)
            }
        }
    }

    func stopStreaming() {
        audioEngine.stop()
        audioEngine.inputNode.removeTap(onBus: 0)
        recognitionRequest?.endAudio()
        recognitionTask?.cancel()
        recognitionRequest = nil
        recognitionTask = nil
    }
}

enum SpeechRecognitionServiceError: Error, Equatable {
    case recognizerUnavailable
}
