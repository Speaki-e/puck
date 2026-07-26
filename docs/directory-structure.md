# pet-app 디렉터리 구조 초안

이 문서는 `plan/02_pet-app.md`(1조: 강상우·박해영 기획서), `plan/01_protocol.md`, `plan/프로젝트_개요.md`를 근거로 pet-app 저장소의 소스 트리를 설계한 초안이다. 실제 코드는 P0~P9 구현 순서(02_pet-app.md 2절)에 따라 강상우·박해영(및 위임받은 에이전트)이 채워 넣는다.

## 0. 설계 원칙

- **`project.yml`(xcodegen)이 Xcode 프로젝트의 단일 진실 소스다.** `PetAgent.xcodeproj`와 `PetAgent/Resources/Info.plist`는 둘 다 `xcodegen generate`의 생성물이며 커밋하지 않는다(`.gitignore`). `project.pbxproj`는 텍스트지만 사실상 사람이 diff/merge하기 어려운 포맷이라, 02_pet-app.md 협업 규칙 5절이 우려하는 "Xcode 프로젝트 파일 충돌"을 애초에 발생시키지 않는 방법을 택했다. 타깃/그룹/빌드 설정을 바꿀 때는 `project.yml`을 수정하고 `xcodegen generate`를 다시 실행한다.
- **레이어가 아니라 기능(F1~F11)으로 최상위 그룹을 나눈다.** MVVM의 Model/View/ViewModel 대신 Overlay/Avatar/Movement/WindowSensing/... 처럼 02_pet-app.md의 기능 단위를 그대로 폴더 경계로 삼는다. 강상우·박해영이 각자 맡은 기능 폴더 안에서 대부분의 작업을 끝낼 수 있어야 소스 레벨 충돌도 최소화된다.
- **FSM은 protocol 하나 + 상태별 파일 1개.** `Movement/StateHandler.swift`(protocol) + `Movement/States/*State.swift`(구현체 12개)로, 02_pet-app.md 3절의 상태 전이표에 있는 12개 상태(Idle/Walk/Climb/WalkOnTop/Fall/Land/MoveTo/Point/Type/Listen/ReactClick/ReactDrag)와 1:1 대응시켰다.
- **소켓 계약은 `Bridge/`에 격리.** `protocol` 저장소가 유일한 진실 소스이므로, `Bridge/BridgeMessages.swift`는 `protocol/swift/BridgeMessages.swift`를 수동 동기화하는 사본이라는 것을 파일 헤더에 명시했다. 이 파일 변경은 항상 protocol 저장소 스키마 변경 PR과 짝을 이뤄야 한다.
- **아바타 타입은 `AvatarPlayable` 프로토콜 뒤로 숨긴다.** FSM(`CharacterController`)은 `AvatarPlayable`만 알고 `USDZAvatar`/`VideoAvatar`/`SpriteAvatar` 중 무엇이 실제로 재생되는지 모른다(02_pet-app.md F2). `VideoAvatar`/`SpriteAvatar`는 1차 구현 범위가 아니므로 인터페이스만 유지하는 빈 스텁으로 자리만 잡아둔다.
- **도구 실행기는 도구 1개당 파일 1개.** `Tools/Handlers/`는 protocol 저장소 4절 "도구 레지스트리" 표의 pet-app 담당 도구(launch_app, list_running_apps, get_frontmost_window, find_ui_element, point_at, click_element, run_shell, run_applescript) 8개와 1:1 대응한다. 새 도구가 protocol에 추가되면 이 폴더에 파일을 1개 추가하는 것이 변경의 기본 단위가 된다.

## 1. 전체 트리

```
pet-app/
├── .gitignore
├── .gitattributes                 # usdz/wav/mp3/m4a → Git LFS
├── project.yml                    # xcodegen 스펙 (Xcode 프로젝트의 단일 진실 소스)
├── README.md
├── docs/
│   ├── directory-structure.md     # 본 문서
│   └── qa-cases.md                # 02_pet-app.md에서 언급된 QA 시나리오
├── PetAgent/                       # Xcode 앱 타깃 "PetAgent" 소스 루트 (예정)
│   ├── App/
│   │   ├── PetAgentApp.swift
│   │   ├── AppDelegate.swift
│   │   └── MenuBarController.swift
│   ├── Overlay/                    # F1 (강상우)
│   │   ├── OverlayWindow.swift
│   │   ├── OverlayWindowController.swift
│   │   ├── ScreenManager.swift
│   │   ├── ScreenSpaceMapper.swift
│   │   ├── ClickThroughController.swift
│   │   └── PetARView.swift
│   ├── Avatar/                     # F2 (강상우)
│   │   ├── AvatarPlayable.swift
│   │   ├── AvatarManifest.swift
│   │   ├── AvatarLoader.swift
│   │   ├── USDZAvatar.swift
│   │   ├── VideoAvatar.swift        # 후순위 스텁
│   │   ├── SpriteAvatar.swift       # 후순위 스텁
│   │   └── AvatarImportValidator.swift
│   ├── Movement/                   # F3 (박해영)
│   │   ├── GlobalScreenSpace.swift
│   │   ├── CharacterController.swift
│   │   ├── StateHandler.swift
│   │   ├── WanderScheduler.swift
│   │   └── States/
│   │       ├── IdleState.swift
│   │       ├── WalkState.swift
│   │       ├── ClimbState.swift
│   │       ├── WalkOnTopState.swift
│   │       ├── FallState.swift
│   │       ├── LandState.swift
│   │       ├── MoveToState.swift
│   │       ├── PointState.swift
│   │       ├── TypeState.swift
│   │       ├── ListenState.swift
│   │       ├── ReactClickState.swift
│   │       └── ReactDragState.swift
│   ├── WindowSensing/              # F4 (박해영)
│   │   ├── WindowInfo.swift
│   │   ├── WindowListWatcher.swift
│   │   ├── LandingSurfaceResolver.swift
│   │   ├── AccessibilityPermission.swift
│   │   ├── UIElementInspector.swift
│   │   └── ScreenCaptureFallback.swift
│   ├── Audio/                      # F5 (강상우)
│   │   ├── SFXPlayer.swift
│   │   ├── PlayerNodePool.swift
│   │   ├── SoundTable.swift
│   │   └── FocusModeObserver.swift
│   ├── Input/                      # F6 (박해영)
│   │   ├── GlobalHotkeyManager.swift
│   │   ├── HotkeyBindings.swift
│   │   ├── TextInputBubbleWindow.swift
│   │   └── TextInputBubbleView.swift
│   ├── Voice/                      # F7 (박해영)
│   │   ├── VoiceInputController.swift
│   │   ├── SpeechRecognitionService.swift
│   │   └── MicrophonePermission.swift
│   ├── Pointing/                   # F10 (박해영)
│   │   ├── PointingController.swift
│   │   ├── ClickDetector.swift
│   │   └── SyntheticClick.swift
│   ├── Tools/                      # F11 (박해영)
│   │   ├── ToolExecutor.swift
│   │   ├── ToolExecutionLogger.swift
│   │   └── Handlers/
│   │       ├── LaunchAppHandler.swift
│   │       ├── ListRunningAppsHandler.swift
│   │       ├── GetFrontmostWindowHandler.swift
│   │       ├── FindUIElementHandler.swift
│   │       ├── PointAtHandler.swift
│   │       ├── ClickElementHandler.swift
│   │       ├── RunShellHandler.swift
│   │       └── RunAppleScriptHandler.swift
│   ├── Bridge/                     # 소켓 서버 (박해영, protocol 3장 계약)
│   │   ├── BridgeServer.swift
│   │   ├── BridgeConnection.swift
│   │   ├── BridgeMessages.swift     # protocol/swift/BridgeMessages.swift 동기화 사본
│   │   └── EventRouter.swift
│   ├── Settings/                   # 공통
│   │   ├── SettingsStore.swift
│   │   ├── SettingsView.swift
│   │   └── AvatarManagementView.swift
│   ├── Diagnostics/                # 공통
│   │   ├── PermissionOnboarding.swift
│   │   └── AppLogger.swift
│   └── Resources/
│       ├── Info.plist              # xcodegen 생성물, 커밋 안 함 (project.yml이 source of truth)
│       ├── Assets.xcassets/
│       │   ├── Contents.json
│       │   └── AppIcon.appiconset/Contents.json
│       └── Avatars/
│           └── dummy/                # 개발용 더미 아바타 (클론 즉시 실행 보장)
│               ├── manifest.json
│               ├── README.md         # 실 usdz/wav 자산 추가 안내
│               └── sounds/
└── PetAgentTests/
    ├── Movement/StateTransitionTests.swift
    ├── Avatar/AvatarManifestParsingTests.swift
    ├── WindowSensing/GlobalScreenSpaceTests.swift
    └── Bridge/BridgeMessageCodableTests.swift
```

## 2. 폴더별 상세

| 폴더 | 기능 코드 | 담당 | 02_pet-app.md 근거 절 | 비고 |
|---|---|---|---|---|
| `App/` | 공통 | 강상우/박해영 | 4절(수명주기: AppKit, LSUIElement) | 앱 시작 시 권한 자가진단 → Overlay → BridgeServer → GlobalHotkeyManager 초기화 순서를 여기서 조정 |
| `Overlay/` | F1 | 강상우 | 3절 F1 | alpha halo 대응 4단계 절차의 실험 지점(`PetARView`), 클릭 통과 히트박스 토글(`ClickThroughController`) |
| `Avatar/` | F2 | 강상우 | 3절 F2 | `AvatarPlayable`이 FSM과 구현체 사이의 유일한 경계. `VideoAvatar`/`SpriteAvatar`는 인터페이스만 |
| `Movement/` | F3 | 박해영 | 3절 F3 | `States/`는 상태 전이표(Idle→Walk→Climb→WalkOnTop→Fall→Land, MoveTo→Point/Idle 등)와 1:1 |
| `WindowSensing/` | F4 | 박해영 | 3절 F4 | 레벨1(`WindowListWatcher`, `LandingSurfaceResolver`) / 레벨2(`AccessibilityPermission`, `UIElementInspector`, `ScreenCaptureFallback`) 구분 유지 |
| `Audio/` | F5 | 강상우 | 3절 F5 | FSM 상태명과 소켓 이벤트명을 동일 키로 조회하는 `SoundTable`이 핵심 |
| `Input/` | F6 | 박해영 | 3절 F6 | 전역 단축키(`GlobalHotkeyManager`)와 텍스트 입력 말풍선(`TextInputBubbleWindow`)은 별도 파일로 분리 — 후자만 `canBecomeKey` |
| `Voice/` | F7 | 박해영 | 3절 F7 | PTT 키 이벤트와 녹음 수명주기를 `VoiceInputController` 한 클래스가 전부 소유 (설계 요구사항) |
| `Pointing/` | F10 | 박해영 | 3절 F10 | `SyntheticClick`은 승인 게이트를 통과했다는 전제 하의 실행만 담당 (승인 자체는 ai-module 책임) |
| `Tools/` | F11 | 박해영 | 3절 F11, protocol 4절 | `Handlers/`는 도구 레지스트리 표와 1:1. 새 도구 추가 시 파일 1개 추가가 기본 변경 단위 |
| `Bridge/` | 소켓 서버 | 박해영 | 3절 F11, protocol 2·3절 | `BridgeMessages.swift`는 protocol 저장소 스키마의 수동 동기화 사본 — 두 저장소를 함께 수정해야 함 |
| `Settings/` | 공통 | 강상우/박해영 | 4절(설정 UI: SwiftUI) | 오버레이 자체는 순수 AppKit 유지, 설정 화면만 `NSHostingView`로 SwiftUI 임베드 |
| `Diagnostics/` | 공통 | 강상우/박해영 | 6절 리스크(CGEvent tap 권한 리셋) | 시작 시 권한 자가진단 + 재안내 UI가 리스크 대응책의 구현 지점 |
| `Resources/Avatars/dummy/` | F2 | 강상우 | "아바타 리소스 소비" 절 | M-A 마일스톤(소켓 없이 단독 실행)을 위한 최소 자산. 실 usdz/wav는 추후 Git LFS로 추가 |
| `PetAgentTests/` | 테스트 | 강상우/박해영 | — | 좌표계 변환, manifest 파싱, FSM 전이, 소켓 메시지 Codable처럼 순수 로직 위주로 우선 커버 |

## 3. 아직 없는 것 / 다음 단계

- **`.xcodeproj`는 커밋하지 않는다.** `project.yml`을 수정한 뒤 `xcodegen generate`(사전에 `brew install xcodegen`)를 실행하면 `PetAgent.xcodeproj`와 `PetAgent/Resources/Info.plist`가 재생성된다. 타깃/그룹 추가, 빌드 설정 변경은 전부 `project.yml` PR로 한다 — 협업 규칙(02_pet-app.md 5절: "구조 변경 PR은 즉시 머지")이 우려하던 지점이 파일 자체가 아니라 `project.yml`이라는 짧은 diff로 옮겨졌다.
- **로직은 순서대로 구현 중.** 모든 `.swift` 파일은 파일 헤더 주석(담당/기능 코드/한 줄 설명)으로 시작하며, 02_pet-app.md 2절의 P0~P9 순서(단, 렌더링에 의존하지 않는 모듈을 먼저 구현하는 순서로 재배열됨 — 4절 표 참고)대로 채워 나간다.
- **Git LFS 설정 필요.** `.gitattributes`에 `*.usdz`, `*.wav`, `*.mp3`, `*.m4a` 추적 규칙은 넣어뒀지만, 실제로 `git lfs install` 및 LFS 자산 추가는 강상우가 더미 아바타 실 자산을 넣는 시점에 진행한다.
- **`protocol` 저장소 확정 대기.** `Bridge/BridgeMessages.swift`, `Avatar/AvatarManifest.swift`의 필드는 `plan/01_protocol.md`에 적힌 초안 스키마를 반영했다. `프로젝트_개요.md` 4절의 "첫 주 전원 합의 사항"(소켓 스키마·manifest 스키마 확정)이 끝나면 protocol 저장소의 실제 파일과 다시 대조해야 한다.

## 4. 구현 순서(P0~P9)와 폴더 매핑

02_pet-app.md 2절의 구현 순서를 폴더 기준으로 다시 정리하면:

| 순서 | 항목 | 주로 건드리는 폴더 |
|---|---|---|
| P0 | F1 오버레이+렌더링 | `Overlay/` |
| P1 | F2 아바타 로더 + F3 FSM 골격 | `Avatar/`, `Movement/` |
| P2 | F3 화면 내 이동, 멀티 디스플레이 | `Movement/`, `Overlay/ScreenManager.swift` |
| P3 | F4 레벨1 + 창 위 이동 | `WindowSensing/`, `Movement/States/ClimbState.swift` 등 |
| P4 | F5 SFX | `Audio/` |
| P5 | F6 전역 단축키 + 텍스트 입력 | `Input/` |
| P6 | F7 PTT+STT | `Voice/` |
| P7 | 소켓 서버 + F11 실행기 | `Bridge/`, `Tools/` |
| P8 | F4 레벨2 + F10 포인팅 | `WindowSensing/UIElementInspector.swift`, `Pointing/` |
| P9 | F10 click_element, 아바타 교체 UI | `Pointing/SyntheticClick.swift`, `Settings/AvatarManagementView.swift` |
