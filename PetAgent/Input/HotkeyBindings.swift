//
//  HotkeyBindings.swift
//  PetAgent
//
//  F6 · owner: Haeyoung Park
//  Default bindings (PTT/text input/character summon) + user config + conflict detection
//

import CoreGraphics

/// A key combo: a virtual key code (CGKeyCode; 49 = Space) plus modifier flags.
struct HotkeyBinding: Equatable {
    let keyCode: CGKeyCode
    let modifierFlags: CGEventFlags

    /// Real CGEvents carry extra flag bits (e.g. .maskNonCoalesced) unrelated
    /// to the modifier combo the user actually pressed — only compare these.
    static let relevantModifierMask: CGEventFlags = [.maskCommand, .maskShift, .maskAlternate, .maskControl]

    func matches(keyCode: CGKeyCode, modifierFlags: CGEventFlags) -> Bool {
        self.keyCode == keyCode
            && modifierFlags.intersection(Self.relevantModifierMask)
                == self.modifierFlags.intersection(Self.relevantModifierMask)
    }
}

/// The three configurable hotkeys from plan/02_pet-app.md F6. Conflict
/// checking exists because these are user-remappable — the plan explicitly
/// calls for "충돌 검사" (conflict checking) in the key-capture UI.
struct HotkeyBindings: Equatable {
    var pushToTalk: HotkeyBinding
    var textInput: HotkeyBinding
    var characterSummon: HotkeyBinding

    /// Space = keyCode 49. PTT = Option+Space (hold), text input =
    /// Option+Shift+Space, character summon = Option+Cmd+Space.
    static let defaults = HotkeyBindings(
        pushToTalk: HotkeyBinding(keyCode: 49, modifierFlags: [.maskAlternate]),
        textInput: HotkeyBinding(keyCode: 49, modifierFlags: [.maskAlternate, .maskShift]),
        characterSummon: HotkeyBinding(keyCode: 49, modifierFlags: [.maskAlternate, .maskCommand])
    )

    /// Pairs of binding names that collide (same key + relevant modifiers).
    func conflicts() -> [(String, String)] {
        let all: [(name: String, binding: HotkeyBinding)] = [
            ("pushToTalk", pushToTalk),
            ("textInput", textInput),
            ("characterSummon", characterSummon),
        ]

        var found: [(String, String)] = []
        for i in all.indices {
            for j in all.indices where j > i {
                if all[i].binding.matches(keyCode: all[j].binding.keyCode, modifierFlags: all[j].binding.modifierFlags) {
                    found.append((all[i].name, all[j].name))
                }
            }
        }
        return found
    }
}
