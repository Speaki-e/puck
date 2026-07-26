//
//  LaunchAppHandler.swift
//  PetAgent
//
//  F11 · owner: Haeyoung Park
//  NSWorkspace.openApplication -> returns pid, triggers the pet's MoveTo
//
//  TODO(P8+): trigger the pet's MoveTo toward the launched app's window once
//  it appears (needs F4 window tracking wired to this handler's completion).

import AppKit

/// args: `{"app_name": "Safari"}` or `{"bundle_id": "com.apple.Safari"}`.
final class LaunchAppHandler: ToolHandler {
    let toolName = "launch_app"

    func execute(args: JSONValue, completion: @escaping (Result<JSONValue?, ToolExecutionError>) -> Void) {
        guard case .object(let fields) = args else {
            completion(.failure(.executionFailed("launch_app requires an args object")))
            return
        }

        let appURL: URL?
        if case .string(let bundleID) = fields["bundle_id"] {
            appURL = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID)
        } else if case .string(let appName) = fields["app_name"] {
            // NSWorkspace has no modern by-display-name lookup API; fullPath(forApplication:)
            // is deprecated but remains the practical way to resolve a plain app name.
            appURL = NSWorkspace.shared.fullPath(forApplication: appName).map(URL.init(fileURLWithPath:))
        } else {
            appURL = nil
        }

        guard let appURL else {
            completion(.failure(.executionFailed("could not resolve app_name/bundle_id")))
            return
        }

        NSWorkspace.shared.openApplication(at: appURL, configuration: NSWorkspace.OpenConfiguration()) { app, error in
            if let app {
                completion(.success(.object(["pid": .number(Double(app.processIdentifier))])))
            } else {
                completion(.failure(.executionFailed(error?.localizedDescription ?? "launch failed")))
            }
        }
    }
}
