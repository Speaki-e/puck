//
//  SettingsView.swift
//  PetAgent
//
//  Shared · owner: Sangwoo Kang / Haeyoung Park
//  SwiftUI settings screen, embedded via NSHostingView (overlay itself stays pure AppKit)
//

import SwiftUI

struct SettingsView: View {
    let store: SettingsStore

    @State private var volume: Double
    @State private var isMuted: Bool
    @State private var autoMuteOnFocus: Bool
    @State private var avoidClimbingFocusedWindow: Bool
    @State private var walkSpeedMultiplier: Double

    init(store: SettingsStore) {
        self.store = store
        _volume = State(initialValue: Double(store.volume))
        _isMuted = State(initialValue: store.isMuted)
        _autoMuteOnFocus = State(initialValue: store.autoMuteOnFocus)
        _avoidClimbingFocusedWindow = State(initialValue: store.avoidClimbingFocusedWindow)
        _walkSpeedMultiplier = State(initialValue: store.walkSpeedMultiplier)
    }

    var body: some View {
        Form {
            Section("Sound") {
                Slider(value: $volume, in: 0...1) { Text("Volume") }
                    .onChange(of: volume) { store.volume = Float($0) }
                Toggle("Mute", isOn: $isMuted)
                    .onChange(of: isMuted) { store.isMuted = $0 }
                Toggle("Auto-mute during Focus (best-effort, may not detect reliably)", isOn: $autoMuteOnFocus)
                    .onChange(of: autoMuteOnFocus) { store.autoMuteOnFocus = $0 }
            }
            Section("Permissions") {
                // The launch prompt only appears once, so this is the way back
                // for anyone who dismissed it or revoked the grant later.
                LabeledContent("Accessibility") {
                    Text(AccessibilityPermission.isTrusted(prompt: false) ? "Granted" : "Not granted")
                        .foregroundStyle(.secondary)
                }
                Button("Open System Settings…") {
                    AccessibilityPermission.openSystemSettings()
                }
                Text("Needed for global hotkeys, reading other apps' UI, and synthetic clicks.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            Section("Movement") {
                Toggle("Don't climb over the focused window", isOn: $avoidClimbingFocusedWindow)
                    .onChange(of: avoidClimbingFocusedWindow) { store.avoidClimbingFocusedWindow = $0 }
                HStack {
                    Slider(value: $walkSpeedMultiplier, in: 0.25...3.0) { Text("Speed") }
                        .onChange(of: walkSpeedMultiplier) { store.walkSpeedMultiplier = $0 }
                    Text(String(format: "%.2fx", walkSpeedMultiplier))
                        .monospacedDigit()
                        .frame(width: 48, alignment: .trailing)
                }
            }
        }
        .padding()
        .frame(width: 340)
    }
}
