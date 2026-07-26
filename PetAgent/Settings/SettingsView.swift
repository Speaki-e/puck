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

    init(store: SettingsStore) {
        self.store = store
        _volume = State(initialValue: Double(store.volume))
        _isMuted = State(initialValue: store.isMuted)
        _autoMuteOnFocus = State(initialValue: store.autoMuteOnFocus)
        _avoidClimbingFocusedWindow = State(initialValue: store.avoidClimbingFocusedWindow)
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
            Section("Movement") {
                Toggle("Don't climb over the focused window", isOn: $avoidClimbingFocusedWindow)
                    .onChange(of: avoidClimbingFocusedWindow) { store.avoidClimbingFocusedWindow = $0 }
            }
        }
        .padding()
        .frame(width: 340)
    }
}
