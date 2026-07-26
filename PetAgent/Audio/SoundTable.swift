//
//  SoundTable.swift
//  PetAgent
//
//  F5 · owner: Sangwoo Kang
//  Looks up the manifest sounds table (shared key space: FSM state names + socket event names)
//

import Foundation

/// Looks up manifest.json's `sounds` table by key. The same table serves
/// both FSM clip-key triggers (walk, point, react_click, ...) and socket
/// event-name triggers (app_launch, task_success, task_fail, listen_start).
/// An unmapped key resolves to nil — silence, by design (F5: "미매핑 키 무음").
struct SoundTable: Equatable {
    let avatarDirectory: URL
    let sounds: [String: String]

    func fileURL(for key: String) -> URL? {
        guard let relativePath = sounds[key] else { return nil }
        return avatarDirectory.appendingPathComponent(relativePath)
    }
}
