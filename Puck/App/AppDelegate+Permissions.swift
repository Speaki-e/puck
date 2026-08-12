//
//  AppDelegate+Permissions.swift
//  Puck
//
//  Shared · owner: 강상우 (Sangwoo Kang) / 박해영 (Haeyoung Park)
//  Launch-time TCC permission self-check and re-prompt (microphone, speech
//  recognition, Accessibility).
//

extension AppDelegate {
    // MARK: - Permissions

    /// PermissionOnboarding existed but nothing ever called it: launch only
    /// logged `currentStatus()` and moved on, so the app never asked for
    /// anything. Microphone and speech recognition stayed `notDetermined`
    /// forever — VoiceInputController would try to record and fail silently —
    /// and Accessibility could only be granted by hand, which is exactly the
    /// flow that breaks on stale System Settings entries.
    func requestPermissions() {
        AppLogger.shared.log(.info, "Launch permission status: \(PermissionOnboarding.currentStatus())")

        // Only prompts the ones still undecided; already-answered permissions
        // (granted or denied) are left alone rather than re-asked every launch.
        PermissionOnboarding.requestUndecidedPermissions { status in
            AppLogger.shared.log(.info, "Permission status after prompting: \(status)")
        }

        // Accessibility can't be requested silently — the only way to ask is
        // macOS's own modal. Ask once and then stay quiet: prompting on every
        // launch means anyone who dismisses it, or who is part-way through
        // granting it in System Settings, gets the dialog again next time.
        // Settings has a button for granting it later.
        if PermissionPromptPolicy.shouldPromptForAccessibility(
            isTrusted: AccessibilityPermission.isTrusted(prompt: false),
            hasAskedBefore: settingsStore.hasRequestedAccessibility
        ) {
            settingsStore.hasRequestedAccessibility = true
            _ = AccessibilityPermission.isTrusted(prompt: true)
        }
    }
}
