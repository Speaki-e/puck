//
//  ReactDragState.swift
//  PetAgent
//
//  F3 · owner: Haeyoung Park
//  ReactDrag state's StateHandler implementation
//
//  Entered on character drag, from any current state; follows the cursor
//  while held, transitions to Fall on drop.
//  TODO(P9): track the cursor position every frame while dragging.

final class ReactDragState: StateHandler {
    let name = "ReactDrag"
    let clipKey = "react_drag"
    let loopsClip = true
}
