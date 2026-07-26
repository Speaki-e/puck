//
//  PointAtHandler.swift
//  PetAgent
//
//  F11 · owner: Haeyoung Park
//  Delegates a MoveTo+Point command to the F3 FSM (tool execution = pet action, a special case)
//
//  TODO(P8): implement once Pointing/PointingController.swift exists — this
//  handler should trigger PointingController.point(at:) and reply with
//  tool_result(ok) at the point where Point actually starts (per protocol
//  4절: "Point 시작 시점에 tool_result(ok) 반환"), not on Point ending.
