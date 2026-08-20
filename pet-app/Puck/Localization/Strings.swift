//
//  Strings.swift
//  Puck
//
//  Shared · owner: 박해영 (Haeyoung Park)
//  All user-facing text in the Settings window, the merged Avatar tab, and
//  the menu bar, in Korean only. A flat key/table lookup rather than Apple's .lproj/
//  Localizable.strings + Bundle mechanism, because the language here was an
//  in-app setting the user could flip live, not a fixed-at-launch system
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

    case appearanceLabel, appearanceSystem, appearanceLight, appearanceDark
    /// The client (chat) window's own theme, kept in sync with the menu bar
    /// settings the way Shady-style apps do. A separate setting from `appearanceLabel` above (that
    /// one is system-wide light/dark/system; this one is the client
    /// window's own light/dark ClientThemeStyle).
    case clientThemeLabel
    case accessibilityLabel, accessibilityGranted, accessibilityNotGranted
    case openSystemSettingsButton, accessibilityExplanation

    case volumeLabel, muteLabel, autoMuteLabel, muteComplaintLabel

    case avoidClimbingLabel, speedLabel, toySizeLabel, toyPumpkin, toyWand

    case avatarsHeader, importAvatarButton, importPanelPrompt
    /// Picking a different installed avatar as a preset.
    case avatarSelectButton
    /// The avatar package format needs to be explained to end users too --
    /// condensed from
    /// docs/avatar-spec.md for end users, not the full creator-facing spec.
    case avatarPackageFormatExplanation
    case sizeHeader
    case emotionsHeader, emotionsExplanation, mappedLabel, notMappedLabel
    case chooseImageButton, choosePanelPrompt
    case customEmotionPlaceholder, addButton

    /// "%1$@ of %2$@ mapped" -- the collapsed emotion list's summary.
    case mappedCountFormat

    /// What the pet says when it needs a permission it doesn't have.
    case permissionNeededBubble

    // F15: the agent's API key, entered here rather than in a .env.
    case agentHeader, apiKeySave, apiKeyClear
    case apiKeySavedFormat, apiKeySourceFormat, apiKeyMissing, apiKeySaveFailed
    /// F15 (task 4): which LLM host the agent talks to. `apiKeyLabelFormat`
    /// and `apiKeyExplanationFormat` take the selected `AgentProvider`'s
    /// name/env-var so the key field always names the provider it is
    /// actually editing, instead of always saying "OpenAI".
    case providerLabel, apiKeyLabelFormat, apiKeyExplanationFormat
    /// The model name, for the providers where one is ours to choose, and the
    /// coding-agent CLI, for the provider that runs one. Both were previously
    /// reachable only through an environment variable.
    case modelLabel, modelExplanationFormat, modelReset
    case codingAgentLabel, cliProviderExplanation
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
    /// F13 (2026-07-30): PuckClient is a separate Dock-resident app now
    /// -- this menu item activates/launches it, replacing the old
    /// Option+Shift+Space-opens-the-client-window behavior.
    case menuOpenClient
}

enum Strings {
    static func text(_ key: L10nKey) -> String {
        table[key] ?? key.rawValue
    }

    private static let table: [L10nKey: String] = [
        .tabGeneral: "일반",
        .tabSound: "사운드",
        .tabMovement: "이동",

        .appearanceLabel: "테마",
        .appearanceSystem: "시스템",
        .appearanceLight: "라이트",
        .appearanceDark: "다크",
        .clientThemeLabel: "채팅 테마",
        .accessibilityLabel: "손쉬운 사용",
        .accessibilityGranted: "허용됨",
        .accessibilityNotGranted: "허용 안 됨",
        .openSystemSettingsButton: "시스템 설정 열기…",
        .accessibilityExplanation: "전역 단축키, 다른 앱의 UI 읽기, 가상 클릭 기능에 필요합니다.",

        .volumeLabel: "음량",
        .muteLabel: "음소거",
        .autoMuteLabel: "포커스 모드에서 자동 음소거 (최선 노력 기반, 정확하지 않을 수 있음)",
        .muteComplaintLabel: "음소거하면 투덜대기",

        .avoidClimbingLabel: "포커스된 창 위로는 올라가지 않기",
        .speedLabel: "이동 속도",
        .toySizeLabel: "장난감 크기",
        .toyPumpkin: "호박",
        .toyWand: "지팡이",

        .avatarsHeader: "아바타",
        .importAvatarButton: "아바타 패키지 가져오기…",
        .avatarSelectButton: "선택",
        .avatarPackageFormatExplanation:
            "아바타 패키지는 폴더 하나입니다: manifest.json과 동작별 투명 배경 PNG(idle은 필수, walk·climb·fall 등은 권장), 그리고 선택적으로 .wav 파일이 담긴 sounds/ 폴더로 구성됩니다. 이미지는 긴 변 기준 1024px 내외, 파일당 약 500KB 이하를 권장합니다.",
        .importPanelPrompt: "가져오기",
        .sizeHeader: "크기",
        .emotionsHeader: "감정 표현",
        .emotionsExplanation: "소켓 이벤트(생각 중, 작업 실패, 작업 완료)를 이미지에 매핑합니다. 매핑되지 않으면 대기 이미지로 대체됩니다.",
        .mappedLabel: "매핑됨",
        .notMappedLabel: "매핑 안 됨",
        .chooseImageButton: "이미지 선택…",
        .choosePanelPrompt: "선택",
        .customEmotionPlaceholder: "사용자 지정 감정 이름",
        .addButton: "추가",

        .mappedCountFormat: "%2$@개 중 %1$@개 매핑됨",

        .permissionNeededBubble: "그거 하려면 권한이 필요해요. 제가 가리키는 창에서 허용해 주세요!",

        .agentHeader: "에이전트",
        .providerLabel: "AI 공급자",
        .apiKeyLabelFormat: "%1$@ API 키",
        .apiKeySave: "저장",
        .apiKeyClear: "삭제",
        .apiKeySavedFormat: "%1$@에 저장했어요",
        .apiKeySourceFormat: "사용 중 — 출처: %1$@",
        .apiKeyMissing: "키가 없어요 — 아직 명령을 수행할 수 없습니다.",
        .apiKeySaveFailed: "키 파일을 저장하지 못했어요.",
        .apiKeyExplanationFormat:
            "본인만 읽을 수 있는 .env 파일에 저장됩니다. 환경변수 %1$@나 프로젝트 폴더의 .env가 있으면 그쪽이 우선합니다.",
        .modelLabel: "모델",
        .modelReset: "기본값",
        .modelExplanationFormat: "비워 두고 저장하면 기본값 %1$@을(를) 씁니다. 환경변수 %2$@가 있으면 그쪽이 우선합니다.",
        .codingAgentLabel: "코딩 CLI",
        .cliProviderExplanation:
            "선택한 CLI와 안정적인 설정 토큰 또는 API 키를 씁니다. 펫 도구는 MCP로 연결되고, 선택한 프로젝트 안의 파일 작업은 샌드박스 안에서 실행됩니다.",
        .installedFormat: "'%1$@' 설치 완료.",
        .installedMissingRecommendedFormat: "'%1$@' 설치 완료 — 권장 클립 누락(대기 이미지로 대체): %2$@",
        .failedToInstallFormat: "'%1$@' 설치 실패: %2$@",
        .rejectedMissingRequiredFormat: "거부됨 — 필수 클립 파일 누락: %1$@",
        .failedToValidateFormat: "유효성 검사 실패: %1$@",
        .updatedEmotionFormat: "'%1$@' 업데이트 완료.",
        .failedToSetEmotionFormat: "'%1$@' 설정 실패: %2$@",

        .menuToys: "장난감",
        .menuHide: "숨기기",
        .menuShow: "보이기",
        .menuQuit: "Puck 종료",
        .menuOpenClient: "Puck 채팅 열기",
    ]
}
