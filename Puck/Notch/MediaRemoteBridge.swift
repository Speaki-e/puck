//
//  MediaRemoteBridge.swift
//  Puck
//
//  Notch · owner: 박해영 (Haeyoung Park)
//  boring.notch's original approach to system-wide Now Playing info, ported
//  -- byeolki, 2026-08-01: "다이내믹 아일랜드 걍 Boring Notch 클론코딩을
//  기반으로 하고". There is no public API for reading another app's
//  playback state; MediaRemote.framework is private. CFBundle +
//  CFBundleGetFunctionPointerForName against the framework at its fixed
//  system path is boring.notch's own pre-hardened-runtime technique --
//  no bridging header, no dlopen/dlsym. This works because Puck isn't
//  sandboxed or hardened-runtime-restricted; a notarized/App-Store build
//  would need boring.notch's newer out-of-process mediaremote-adapter
//  instead (see NowPlayingMonitor's doc comment).
//

import Foundation

final class MediaRemoteBridge {
    private typealias GetNowPlayingInfoFunction = @convention(c) (DispatchQueue, @escaping ([String: Any]) -> Void) -> Void
    private typealias RegisterForNotificationsFunction = @convention(c) (DispatchQueue) -> Void
    private typealias SendCommandFunction = @convention(c) (Int, AnyObject?) -> Void

    /// Raw MRMediaRemoteCommand values -- only the three the notch's
    /// transport controls need.
    enum Command: Int {
        case togglePlayPause = 2
        case nextTrack = 4
        case previousTrack = 5
    }

    private let getNowPlayingInfo: GetNowPlayingInfoFunction
    private let registerForNotifications: RegisterForNotificationsFunction
    private let sendCommand: SendCommandFunction

    init?() {
        guard
            let bundle = CFBundleCreate(
                kCFAllocatorDefault,
                NSURL(fileURLWithPath: "/System/Library/PrivateFrameworks/MediaRemote.framework")
            ),
            let getInfoPointer = CFBundleGetFunctionPointerForName(bundle, "MRMediaRemoteGetNowPlayingInfo" as CFString),
            let registerPointer = CFBundleGetFunctionPointerForName(
                bundle, "MRMediaRemoteRegisterForNowPlayingNotifications" as CFString
            ),
            let sendCommandPointer = CFBundleGetFunctionPointerForName(bundle, "MRMediaRemoteSendCommand" as CFString)
        else {
            return nil
        }
        getNowPlayingInfo = unsafeBitCast(getInfoPointer, to: GetNowPlayingInfoFunction.self)
        registerForNotifications = unsafeBitCast(registerPointer, to: RegisterForNotificationsFunction.self)
        sendCommand = unsafeBitCast(sendCommandPointer, to: SendCommandFunction.self)
    }

    func fetchNowPlayingInfo(completion: @escaping ([String: Any]) -> Void) {
        getNowPlayingInfo(.main, completion)
    }

    /// Arms `kMRMediaRemoteNowPlayingInfoDidChangeNotification` -- without
    /// this call the notification never fires, even though observing it
    /// doesn't itself require registration to compile.
    func registerForChangeNotifications() {
        registerForNotifications(.main)
    }

    func send(_ command: Command) {
        sendCommand(command.rawValue, nil)
    }
}
