//
//  CompanionAppLauncher.swift
//  PetAgent
//
//  Shared · owner: 박해영 (Haeyoung Park)
//  PetAgent (the pet) and PetAgentClient (the Dock-resident chat window,
//  2026-07-30) are now separate apps that should come up together --
//  byeolki: "둘이 같이 가야하는거임". Each launches the other on its own
//  startup if it isn't already running. isRunning/launch are injected so
//  the decision is testable without NSWorkspace/NSRunningApplication.
//

import AppKit

enum CompanionAppLauncher {
    static func launchIfNeeded(
        bundleIdentifier: String,
        isRunning: (String) -> Bool = { !NSRunningApplication.runningApplications(withBundleIdentifier: $0).isEmpty },
        launch: (String) -> Void = { id in
            guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: id) else { return }
            NSWorkspace.shared.openApplication(at: url, configuration: NSWorkspace.OpenConfiguration(), completionHandler: nil)
        }
    ) {
        guard !isRunning(bundleIdentifier) else { return }
        launch(bundleIdentifier)
    }
}
