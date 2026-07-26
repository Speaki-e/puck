//
//  ReactClickState.swift
//  PetAgent
//
//  F3 · owner: Haeyoung Park
//  ReactClick state's StateHandler implementation
//
//  Entered when the character itself is clicked, from any current state.
//  TODO(P9): a short reaction clip, then transition back to Idle.

final class ReactClickState: StateHandler {
    let name = "ReactClick"
    let clipKey = "react_click"
    let loopsClip = false
}
