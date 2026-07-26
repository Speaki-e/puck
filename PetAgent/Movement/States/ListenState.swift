//
//  ListenState.swift
//  PetAgent
//
//  F3 · owner: Haeyoung Park
//  Listen state's StateHandler implementation
//
//  Entered on PTT keyDown from any current state; on keyUp, returns to
//  whichever state was active before (F7 VoiceInputController owns that).
//  TODO(P6): listen_start SFX on enter.

final class ListenState: StateHandler {
    let name = "Listen"
    let clipKey = "listen"
    let loopsClip = true
}
