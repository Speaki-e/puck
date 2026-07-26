//
//  TypeState.swift
//  PetAgent
//
//  F3 · owner: Haeyoung Park
//  Type state's StateHandler implementation
//
//  Entered via MoveTo(editor window) on a code_editor session event (any
//  current state can be interrupted into this).
//  TODO(P7): typing SFX loop, a short hop on tool_call detail.path changes.

final class TypeState: StateHandler {
    let name = "Type"
    let clipKey = "type"
    let loopsClip = true
}
