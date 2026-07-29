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
    case settingsWindowTitle
    case tabGeneral, tabSound, tabMovement, tabAvatar

    case languageLabel
    case appearanceLabel, appearanceSystem, appearanceLight, appearanceDark
    case accessibilityLabel, accessibilityGranted, accessibilityNotGranted
    case openSystemSettingsButton, accessibilityExplanation

    case volumeLabel, muteLabel, autoMuteLabel

    case avoidClimbingLabel, speedLabel, toySizeLabel

    case avatarsHeader, importAvatarButton, importPanelPrompt
    case sizeHeader
    case emotionsHeader, emotionsExplanation, mappedLabel, notMappedLabel
    case chooseImageButton, choosePanelPrompt
    case customEmotionPlaceholder, addButton

    case installedFormat
    case installedMissingRecommendedFormat
    case failedToInstallFormat
    case rejectedMissingRequiredFormat
    case failedToValidateFormat
    case updatedEmotionFormat
    case failedToSetEmotionFormat

    case menuSettings, menuSwitchAvatar, menuThrowBall, menuHide, menuShow, menuQuit
}

enum Strings {
    static func text(_ key: L10nKey, _ language: AppLanguage) -> String {
        table[key]?[language] ?? key.rawValue
    }

    private static let table: [L10nKey: [AppLanguage: String]] = [
        .settingsWindowTitle: [.english: "PetAgent Settings", .korean: "PetAgent 설정"],
        .tabGeneral: [.english: "General", .korean: "일반"],
        .tabSound: [.english: "Sound", .korean: "사운드"],
        .tabMovement: [.english: "Movement", .korean: "이동"],
        .tabAvatar: [.english: "Avatar", .korean: "아바타"],

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

        .menuSettings: [.english: "Settings…", .korean: "설정…"],
        .menuSwitchAvatar: [.english: "Switch Avatar…", .korean: "아바타 변경…"],
        .menuThrowBall: [.english: "Throw Ball", .korean: "공 던지기"],
        .menuHide: [.english: "Hide", .korean: "숨기기"],
        .menuShow: [.english: "Show", .korean: "보이기"],
        .menuQuit: [.english: "Quit PetAgent", .korean: "PetAgent 종료"],
    ]
}
