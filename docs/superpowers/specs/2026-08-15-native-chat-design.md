# chat-web을 걷어내고 채팅 UI를 애플 기본형 SwiftUI로

- 날짜: 2026-08-15
- 상태: 방향 승인됨 (byeolki: "iOS 기본 제공 탬플릿 같은거 써서", "없앤다 — 전체 네이티브")
- 성공 기준: 채팅 창의 모든 기능이 네이티브로 동작하고, `chat-web/`이 사라지고,
  **npm 없이 레포가 빌드된다.**

## 1. 왜

chat-web이 선택된 이유는 `docs/decisions.md:346`에 남아 있다 — 네이티브 SwiftUI
반복으로는 "특정 비주얼 타깃(Orca/Zed 풍, 미니멀, shadcn)"을 합리적인 속도로 맞출
수 없었기 때문이다. 목표가 **애플 기본형**으로 바뀌면 그 이유가 그대로 무효가 된다.
스톡 SwiftUI처럼 보이게 만드는 데 가장 빠른 건 스톡 SwiftUI다.

같은 문서가 chat-web을 "`ClientWindowStore`/`ChatSession`이 그대로 진실의 원천이고,
그것들은 두 번째 UI 소비자를 얻을 뿐"이라고 적어놨다. **상태는 이미 전부 Swift에
있다.** 이건 아키텍처 작업이 아니라 뷰 교체다.

## 2. 실제 작업량

`chat-web/src`는 2,926줄이지만 그중 ~1,100줄이 shadcn `ui/` 프리미티브다 —
`dropdown-menu`(267), `alert-dialog`(199), `select`(190), `dialog`(166),
`avatar`(112), `card`(103), `popover`(89), `button`(67), `slider`(57),
`tooltip`(55), `scroll-area`(55), `badge`(49), `switch`(33). 전부 SwiftUI에 기본
대응물이 있어서 **포팅 대상이 아니라 삭제 대상**이다 (`Menu`, `.alert`, `Picker`,
`.sheet`, `Button`, `Slider`, `.help`, `ScrollView`, `Toggle`).

또 ~240줄(`usePuckBridge`, `puck-bridge`, `dev-mock-bridge`, `bridge-types`)은
브리지 배선이라 웹뷰와 함께 소멸한다. `chat-reducer.ts`(177)는 `ClientWindowStore`의
중복 미러라 역시 소멸한다.

**남는 진짜 포팅 대상은 ~700줄의 앱 고유 뷰뿐이다.**

| chat-web | 줄 | 네이티브 대응 |
|---|---|---|
| `Sidebar.tsx` | 158 | `List(selection:)` — 워크스페이스 섹션 + 세션 행 |
| `TabStrip.tsx` | 110 | 세션 탭 바 (§4 참고) |
| `ChatTranscript.tsx` | 84 | `ScrollViewReader` + `ForEach(session.timeline)` |
| `ToolCallCard.tsx` | 77 | `DisclosureGroup` |
| `ChatInputBar.tsx` | 68 | `TextField(axis: .vertical)` + 전송 버튼 |
| `App.tsx` | 66 | `ChatPaneView` |
| `NewWorkspaceDialog.tsx` | 59 | `.sheet` + 기존 `NSOpenPanel` |
| `MessageBubble.tsx` | 48 | 말풍선 뷰 |
| `ToolResultRow.tsx` | 34 | 결과 행 |
| `EditorToggleButton.tsx` | 33 | 툴바 `Button` |
| `RunningStatusLine.tsx` | 17 | `ProgressView` + 텍스트 |
| `status-dot.tsx` | 23 | 이미 있음 — `StatusDotView.swift` |

## 3. 교체 지점은 하나

`ClientWindowView.swift`가 `ClientChatWebView(bridge:)`를 새 `ChatPaneView(store:)`로
바꾸는 것이 전부다. 같은 파일의 `EditorPaneView`와 `ClientStatusBarView`는 이미
네이티브이고 손대지 않는다.

```
ClientWindowView
├── ChatPaneView          ← 신규 (ClientChatWebView 대체)
├── EditorPaneView        ← 그대로
└── ClientStatusBarView   ← 그대로
```

## 4. 애플 기본형이란 무엇인가 (그리고 무엇을 바꾸지 않는가)

macOS 스톡 관용구를 쓴다 — iOS 템플릿을 그대로 옮기지 않는다. 이건 macOS 앱이고,
iOS의 둥근 그룹 리스트·큰 제목·하단 탭바를 옮기면 어색해진다.

- `NavigationSplitView` — 사이드바 + 디테일
- `List(selection:)` with `Section` — 워크스페이스별 세션
- `.searchable`은 넣지 않는다 (검색 기능이 원래 없다 — YAGNI)
- `Form`/`.formStyle(.grouped)` — 설정 (별도 창, 이번 범위 밖)
- SF Symbols, 시스템 색상(`.secondary`, `.accentColor`), 시스템 머티리얼
- Dynamic Type 존중 — 고정 pt 폰트 크기를 쓰지 않는다

**바꾸지 않는 것**: 기능. 탭 스트립은 스톡 macOS 관용구가 아니지만(Mail/Notes는
사이드바만 쓴다) 이틀 전 의도적으로 추가된 것이라 **일단 유지한다.** 없애는 건
제품 결정이지 리스타일이 아니다 — §8에 후보로 남긴다.

## 5. 팔레트

`ClientPalette`/`ClientTheme`는 **남긴다.** 에디터 패인과 상태바가 이미 쓰고 있고,
이번 작업은 채팅 창을 그 환경 안으로 들여오는 것이다. 다만 새 뷰는 색을 직접
집지 않고 시스템 시맨틱 색상을 우선하며, 팔레트는 강조색과 상태 점에만 쓴다 —
스톡처럼 보이는 것의 절반은 시스템이 색을 고르게 두는 것이다.

## 6. 삭제 대상

- `chat-web/` 전체
- `Puck/ClientWindow/ClientChatWebView.swift`
- `Puck/ClientWindow/ClientChatBridge.swift`, `ClientChatBridgeMessages.swift`
  (JS↔Swift 계약 — 소비자가 사라진다)
- `pet-app/scripts/sync-chat-web.sh` — **클린 체크아웃에서 npm이 필요한 유일한 이유**
- `PuckClient/Resources/ChatWeb` 및 그 `.gitignore` 항목

## 7. 단계

각 단계 끝에서 앱이 빌드되고 동작해야 한다. 웹뷰 삭제는 마지막이다.

1. **`ChatPaneView` 골격 + 사이드바** — 워크스페이스/세션 목록, 선택. 아직
   `ClientWindowView`에 붙이지 않는다.
2. **트랜스크립트** — 6개 `ChatTimelineEntry` 케이스 전부: 사용자 메시지, 어시스턴트
   텍스트(스트리밍), 툴 호출/결과, 승인 배너, 완료. 자동 스크롤.
3. **입력 바 + 워크스페이스 생성** — 전송, 중지, 새 워크스페이스(폴더 선택).
4. **교체** — `ClientWindowView`가 `ChatPaneView`를 쓴다. 이 시점에 웹뷰 없이
   전체 기능이 동작해야 한다.
5. **삭제** — §6 전부. `install.sh` 하나로 빌드되는지 클린 클론으로 검증.

## 8. 열린 항목

- 탭 스트립을 사이드바로 흡수할지 (스톡 관용구는 사이드바만) — 별도 결정
- 설정 창을 `Form(.formStyle(.grouped))`로 정리 — 별도 작업
- `docs/decisions.md`에 이 전환 기록 추가
