# pet-app

macOS 데스크톱 펫 앱 (Swift). 펫 렌더링/움직임 + 시스템 도구 실행기 + 음성/텍스트 입력을 담당한다. `Speaki-e` 프로젝트(가칭 PetAgent)의 메인앱 저장소로, 전체 조망은 `plan/프로젝트_개요.md`, 본 저장소 상세 기획은 `plan/02_pet-app.md`를 따른다.

- **독립성 원칙**: `workspace`와의 로컬 소켓이 연결되어 있지 않아도 순수 데스크톱 펫으로 완전히 동작해야 한다.
- **의존 계약**: `protocol` 저장소(소켓 스키마, 도구 레지스트리, 아바타 manifest 스키마)만 참조하며, 다른 저장소 코드를 직접 참조하지 않는다.
- **아바타/사운드 리소스**는 팀 외부에서 제작·공급된다. 이 저장소는 `protocol`의 manifest 스키마를 만족하는 아바타 패키지를 소비하기만 하고, 개발용 더미 아바타 1개만 포함한다.

## 담당

| 사람 | 모듈 |
|---|---|
| 강상우 | F1 투명 오버레이 렌더링, F2 아바타 로더, F5 SFX, 아바타 수입 규격 검증기 |
| 박해영 | F3 움직임 FSM, F4 창 인식, F6 전역 단축키, F7 PTT+STT, F10 포인팅, F11 시스템 도구 실행기 |

## 현재 상태

기능별 폴더 구조가 잡혀 있고, 렌더링(F1)에 의존하지 않는 모듈부터 순서대로 구현 중이다. 전체 구조와 설계 근거, 진행 순서는 [`docs/directory-structure.md`](docs/directory-structure.md)를 참고한다.

Xcode 프로젝트(`.xcodeproj`)는 커밋하지 않는다 — [xcodegen](https://github.com/yonaskolb/XcodeGen)으로 `project.yml`에서 생성한다. 타깃 구조를 바꿀 때는 Xcode에서 직접 프로젝트 파일을 만지지 말고 `project.yml`을 수정한 뒤 재생성한다 (`project.pbxproj` 병합 충돌 방지).

## 클론 → 실행

1. `brew install xcodegen` (없다면).
2. 저장소 루트에서 `xcodegen generate` — `PetAgent.xcodeproj`와 `PetAgent/Resources/Info.plist`가 생성된다.
3. `PetAgent.xcodeproj`를 Xcode 15+ 로 연다.
4. 최초 실행 시 요구되는 TCC 권한을 허용한다: Accessibility(단축키·UI 조회·클릭 합성), 마이크, 음성 인식, Screen Recording(선택, 폴백용).
5. 빌드 후 실행하면 `PetAgent/Resources/Avatars/dummy/`의 더미 아바타로 소켓 연결 없이 바로 동작해야 한다 (M-A 마일스톤 기준).
6. `workspace` 저장소를 함께 실행하면 로컬 Unix 소켓(`~/Library/Application Support/PetAgent/bridge.sock`)으로 연동된다.

CLI에서 빌드/테스트만 확인하려면: `xcodebuild -project PetAgent.xcodeproj -scheme PetAgent build` / `xcodebuild -project PetAgent.xcodeproj -scheme PetAgent test`.

## 스택 요약

Swift 5.10+ / macOS 14+, AppKit(메뉴바 상주, LSUIElement) + RealityKit(ARView `.nonAR`, USDZ), CGWindowList + AXUIElement(창 인식), CGEvent.tapCreate(전역 입력), SFSpeechRecognizer(STT), AVAudioEngine(SFX), Network.framework `NWListener`(UDS 소켓 서버). 상세는 `plan/02_pet-app.md` 4절.

## 문서

- [`docs/directory-structure.md`](docs/directory-structure.md) — 디렉터리 구조 초안과 설계 근거
- [`docs/qa-cases.md`](docs/qa-cases.md) — 마일스톤별 QA 시나리오
- `plan/02_pet-app.md`, `plan/01_protocol.md`, `plan/프로젝트_개요.md` — 상위 기획 문서 (Speaki-e 저장소)
