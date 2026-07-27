//
//  LaunchAppHandler.swift
//  PetAgent
//
//  F11 · owner: Haeyoung Park
//  NSWorkspace.openApplication -> returns pid, triggers the pet's MoveTo
//
//  After a successful launch the pet walks over to greet the new window —
//  the M-1 milestone's visible half ("펫이 해당 창으로 이동"). Finding that
//  window means waiting for it to appear in F4's list, which is bootstrap
//  knowledge, so it is delegated through `onAppLaunched`.

import AppKit

/// args: `{"app_name": "Safari"}` or `{"bundle_id": "com.apple.Safari"}`.
final class LaunchAppHandler: ToolHandler {
    let toolName = "launch_app"

    /// Called with the pid of a successfully launched app. The tool_result is
    /// sent independently of this — the agent shouldn't wait on the pet's walk.
    var onAppLaunched: ((pid_t) -> Void)?

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
                self.onAppLaunched?(app.processIdentifier)
            } else {
                completion(.failure(.executionFailed(error?.localizedDescription ?? "launch failed")))
            }
        }
    }
}
