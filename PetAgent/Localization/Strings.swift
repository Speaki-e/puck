//
//  Strings.swift
//  PetAgent
//
//  Shared · owner: 박해영 (Haeyoung Park)
//  All user-facing text in the Settings window, the merged Avatar tab, and
//  the menu bar, in both languages -- byeolki: "한국어 언어모드도
//  만들어주고". A flat key/table lookup rather than Apple's .lproj/
//  Localizable.strings + Bundle mechanism, because the language here is an
//  in-app setting the user can flip live, not a fixed-at-launch system
//  locale -- there is no real bundle to swap.
//
//  Format-string keys (ending in "Format") take %1$@, %2$@, ... via
//  String(format:) at the call site -- positional specifiers because
//  Korean word order for these doesn't always match English's.
//

import Foundation

enum L10nKey: String, CaseIterable, Hashable {
    /// Section headers in the menu bar panel. `tabAvatar` went with the tabs
    /// themselves -- AvatarManagementView titles its own sections now.
    case tabGeneral, tabSound, tabMovement

    case languageLabel
    case appearanceLabel, appearanceSystem, appearanceLight, appearanceDark
    case accessibilityLabel, accessibilityGranted, accessibilityNotGranted
    case openSystemSettingsButton, accessibilityExplanation

    case volumeLabel, muteLabel, autoMuteLabel

    case avoidClimbingLabel, speedLabel, toySizeLabel, toyPumpkin, toyWand

    case avatarsHeader, importAvatarButton, importPanelPrompt
    case sizeHeader
    case emotionsHeader, emotionsExplanation, mappedLabel, notMappedLabel
    case chooseImageButton, choosePanelPrompt
    case customEmotionPlaceholder, addButton

    /// "%1$@ of %2$@ mapped" -- the collapsed emotion list's summary.
    case mappedCountFormat

    /// What the pet says when it needs a permission it doesn't have.
    case permissionNeededBubble

    // F15: the agent's API key, entered here rather than in a .env.
    case agentHeader, apiKeyLabel, apiKeySave, apiKeyClear
    case apiKeySavedFormat, apiKeySourceFormat, apiKeyMissing, apiKeySaveFailed, apiKeyExplanation
    case installedFormat
    case installedMissingRecommendedFormat
    case failedToInstallFormat
    case rejectedMissingRequiredFormat
    case failedToValidateFormat
    case updatedEmotionFormat
    case failedToSetEmotionFormat

    /// The panel's action rows. Settings and Switch Avatar are gone with the
    /// NSMenu: the panel *is* settings, and it opens on the avatar section.
    case menuToys, menuHide, menuShow, menuQuit
    /// F13 (2026-07-30): PetAgentClient is a separate Dock-resident app now
    /// -- this menu item activates/launches it, replacing the old
    /// Option+Shift+Space-opens-the-client-window behavior.
    case menuOpenClient
}

enum Strings {
    static func text(_ key: L10nKey, _ language: AppLanguage) -> String {
        table[key]?[language] ?? key.rawValue
    }

    private static let table: [L10nKey: [AppLanguage: String]] = [
        .tabGeneral: [.english: "General", .korean: "일반"],
        .tabSound: [.english: "Sound", .korean: "사운드"],
        .tabMovement: [.english: "Movement", .korean: "이동"],

        .languageLabel: [.english: "Language", .korean: "언어"],
        .appearanceLabel: [.english: "Appearance", .korean: "모양"],
        .appearanceSystem: [.english: "System", .korean: "시스템"],
        .appearanceLight: [.english: "Light", .korean: "라이트"],
        .appearanceDark: [.english: "Dark", .korean: "다크"],
        .accessibilityLabel: [.english: "Accessibility", .korean: "손쉬운 사용"],
        .accessibilityGranted: [.english: "Granted", .korean: "허용됨"],
        .accessibilityNotGranted: [.english: "Not granted", .korean: "허용 안 됨"],
        .openSystemSettingsButton: [.english: "Open System Settings…", .korean: "시스템 설정 열기…"],
        .accessibilityExplanation: [
            .english: "Needed for global hotkeys, reading other apps' UI, and synthetic clicks.",
            .korean: "전역 단축키, 다른 앱의 UI 읽기, 가상 클릭 기능에 필요합니다.",
        ],

        .volumeLabel: [.english: "Volume", .korean: "음량"],
        .muteLabel: [.english: "Mute", .korean: "음소거"],
        .autoMuteLabel: [
            .english: "Auto-mute during Focus (best-effort, may not detect reliably)",
            .korean: "포커스 모드에서 자동 음소거 (최선 노력 기반, 정확하지 않을 수 있음)",
        ],

        .avoidClimbingLabel: [
            .english: "Don't climb over the focused window",
            .korean: "포커스된 창 위로는 올라가지 않기",
        ],
        .speedLabel: [.english: "Speed", .korean: "이동 속도"],
        .toySizeLabel: [.english: "Toy size", .korean: "장난감 크기"],
        .toyPumpkin: [.english: "Pumpkin", .korean: "호박"],
        .toyWand: [.english: "Wand", .korean: "지팡이"],

        .avatarsHeader: [.english: "Avatars", .korean: "아바타"],
        .importAvatarButton: [.english: "Import Avatar Package…", .korean: "아바타 패키지 가져오기…"],
        .importPanelPrompt: [.english: "Import", .korean: "가져오기"],
        .sizeHeader: [.english: "Size", .korean: "크기"],
        .emotionsHeader: [.english: "Emotions", .korean: "감정 표현"],
        .emotionsExplanation: [
            .english: "Maps a socket event (agent thinking, task failed, task done) to an image. Falls back to idle if unmapped.",
            .korean: "소켓 이벤트(생각 중, 작업 실패, 작업 완료)를 이미지에 매핑합니다. 매핑되지 않으면 대기 이미지로 대체됩니다.",
        ],
        .mappedLabel: [.english: "Mapped", .korean: "매핑됨"],
        .notMappedLabel: [.english: "Not mapped", .korean: "매핑 안 됨"],
        .chooseImageButton: [.english: "Choose Image…", .korean: "이미지 선택…"],
        .choosePanelPrompt: [.english: "Choose", .korean: "선택"],
        .customEmotionPlaceholder: [.english: "Custom emotion name", .korean: "사용자 지정 감정 이름"],
        .addButton: [.english: "Add", .korean: "추가"],

        .mappedCountFormat: [
            .english: "%1$@ of %2$@ mapped",
            .korean: "%2$@개 중 %1$@개 매핑됨",
        ],

        .permissionNeededBubble: [
            .english: "I need permission for that — could you allow it in the window I'm pointing at?",
            .korean: "그거 하려면 권한이 필요해요. 제가 가리키는 창에서 허용해 주세요!",
        ],

        .agentHeader: [.english: "Agent", .korean: "에이전트"],
        .apiKeyLabel: [.english: "OpenAI API key", .korean: "OpenAI API 키"],
        .apiKeySave: [.english: "Save", .korean: "저장"],
        .apiKeyClear: [.english: "Remove", .korean: "삭제"],
        .apiKeySavedFormat: [.english: "Saved to %1$@", .korean: "%1$@에 저장했어요"],
        .apiKeySourceFormat: [.english: "In use, from %1$@", .korean: "사용 중 — 출처: %1$@"],
        .apiKeyMissing: [.english: "No key set — the pet can't run commands yet.", .korean: "키가 없어요 — 아직 명령을 수행할 수 없습니다."],
        .apiKeySaveFailed: [.english: "Couldn't write the key file.", .korean: "키 파일을 저장하지 못했어요."],
        .apiKeyExplanation: [
            .english: "Stored in a .env file readable only by you. An OPENAI_API_KEY environment variable, or a .env next to the project, takes precedence over this field.",
            .korean: "본인만 읽을 수 있는 .env 파일에 저장됩니다. 환경변수 OPENAI_API_KEY나 프로젝트 폴더의 .env가 있으면 그쪽이 우선합니다.",
        ],
        .installedFormat: [.english: "Installed '%1$@'.", .korean: "'%1$@' 설치 완료."],
        .installedMissingRecommendedFormat: [
            .english: "Installed '%1$@' — missing recommended clips (falls back to idle): %2$@",
            .korean: "'%1$@' 설치 완료 — 권장 클립 누락(대기 이미지로 대체): %2$@",
        ],
        .failedToInstallFormat: [
            .english: "Failed to install '%1$@': %2$@",
            .korean: "'%1$@' 설치 실패: %2$@",
        ],
        .rejectedMissingRequiredFormat: [
            .english: "Rejected — missing required clip file(s): %1$@",
            .korean: "거부됨 — 필수 클립 파일 누락: %1$@",
        ],
        .failedToValidateFormat: [.english: "Failed to validate: %1$@", .korean: "유효성 검사 실패: %1$@"],
        .updatedEmotionFormat: [.english: "Updated '%1$@'.", .korean: "'%1$@' 업데이트 완료."],
        .failedToSetEmotionFormat: [
            .english: "Failed to set '%1$@': %2$@",
            .korean: "'%1$@' 설정 실패: %2$@",
        ],

        .menuToys: [.english: "Toys", .korean: "장난감"],
        .menuHide: [.english: "Hide", .korean: "숨기기"],
        .menuShow: [.english: "Show", .korean: "보이기"],
        .menuQuit: [.english: "Quit PetAgent", .korean: "PetAgent 종료"],
        .menuOpenClient: [.english: "Open PetAgent Chat", .korean: "PetAgent 채팅 열기"],
    ]
}
