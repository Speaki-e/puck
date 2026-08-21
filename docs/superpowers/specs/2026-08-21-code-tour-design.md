# 펫이 코드를 안내하는 리뷰 투어 (`show_code`)

날짜: 2026-08-21
상태: 설계 확정, 구현 전

사용자가 채팅으로 "이 함수 설명해줘"라고 하면, 펫이 에디터 패인 앞으로 걸어가
해당 코드를 가리키며 한 줄씩 소개한다. 긴 설명은 채팅에 쌓이고, 펫은 각 지점에서
짧게 말한다.

## 1. 왜

에이전트는 이미 코드를 읽고(`read_file`) 파일을 열 수 있지만(`open_in_editor`),
설명은 전부 채팅 안에서 끝난다. 사용자는 채팅과 에디터를 번갈아 보며 "몇 번째
줄 얘기지?"를 스스로 맞춰야 한다.

펫은 이미 좌표를 가리킬 수 있다(`point_at`). 없는 것은 **코드 위치와 펫을 잇는
경로** 하나뿐이다.

## 2. 범위

들어가는 것:

- 새 툴 `show_code(path, start_line, end_line, caption)` — 한 번 호출 = 한 지점
- 에디터가 해당 줄 범위를 선택·하이라이트하고 화면에 드러냄
- 펫이 에디터 패인으로 이동해 가리키고, 캡션을 말풍선으로 말함

들어가지 않는 것:

- VS Code·Xcode 등 외부 에디터 (§8)
- 사용자가 코드를 선택해서 시작하는 UI 경로 — 시작은 채팅뿐
- 코드를 고치는 리뷰. 이 기능은 **설명만** 한다. 수정은 `code_editor`의 몫

## 3. 핵심 결정: 상태 머신이 아니라 툴 반복

투어를 "펫의 새 FSM 상태"로 만들지 않는다. 투어는 **모델이 `show_code`를 N번
부르는 것**이고, 각 호출이 한 지점이다.

이유는 순서 제어가 공짜로 따라오기 때문이다. `point_at`은 펫이 실제로 도착해
Point 상태에 진입해야 `ok`를 돌려준다(protocol section 4). `show_code`가 그
응답을 기다리므로 모델은 앞서 나갈 수 없고, 투어 순서가 저절로 지켜진다.
별도의 순서·취소·승인 배관이 필요 없다 — 기존 툴 루프가 전부 갖고 있다.

## 4. 왜 줄 단위 정밀 조준을 하지 않는가

`CodeEditSourceEditor`의 `SourceEditorState`는 `cursorPositions`와
`scrollPosition`만 공개한다. "N번째 줄의 화면 사각형"은 공개 API에 없다.
얻으려면 벤더 패키지 내부 `NSTextView`를 파고들어야 한다.

대신 **하이라이트가 정밀도를 담당한다**. 에디터가 그 줄 범위를 선택하면 파란
하이라이트가 정확히 그 코드를 가리킨다. 펫은 에디터 패인을 가리키고, 둘이 합쳐
지시가 완성된다.

`point_at`은 어차피 대상 옆 60pt에 서서(`standOffset`) 대상을 가리는 것을
피한다. 줄 하나를 픽셀 단위로 짚는 연출이 아니다.

이 선택은 되돌릴 수 있다. 좌표를 만드는 곳이 §5-2 한 군데뿐이라, 나중에 정밀
조준으로 올리려면 거기만 바꾸면 된다.

## 5. 구성 요소

### 5-1. `show_code` 툴 — `AgentRunner`

`read_file`과 동일한 패턴. 클로저 타입별칭으로 위임하고, 프로젝트가 바인딩된
워크스페이스에서만 모델에게 노출한다.

```swift
typealias AgentCodeTourStop = (
    _ path: String, _ startLine: Int, _ endLine: Int, _ caption: String
) async -> DispatchedToolResult
```

승인 게이트 없음. 파일을 읽고 펫을 움직일 뿐이라 `point_at`과 같은 등급이다.

### 5-2. `CodeTourDelegate` — `Puck/Agent/`

`EditorFileDelegate` 옆에, 같은 이유로 같은 곳에 둔다: `PuckTests`는 `Puck`
타깃만 의존하므로 테스트가 필요한 것은 여기 있어야 한다.

한 지점의 절차:

1. `EditorPaneStorePool.shared.store(forWorkspace:root:)` → `store.reveal(path:lines:)`
2. `store.paneScreenFrame` 읽기 (AppKit 화면 좌표, bottom-left). `nil`이면 패인이
   화면에 없다는 뜻이므로 §6의 가시성 복구를 먼저 밟는다
3. `GlobalScreenSpace`로 정규화 좌표(top-left)로 변환
4. `dispatcher.execute("point_at", frame)` → 펫 이동·가리킴
5. `point_at`이 `ok`로 응답한 **뒤에** `.event(.petSays(caption))` 브로드캐스트
6. 반환

**4와 5의 순서가 중요하다.** 말풍선을 먼저 띄우면 펫이 걸어가는 동안 8초가 흐르고,
도착할 때쯤 캡션이 사라진다. `point_at`의 `ok`는 "펫이 실제로 가리키기 시작한
시점"이므로, 그때 말하게 하면 §5-5가 노리는 대로 가리키는 동작과 말이 같이
끝난다. 걸어가는 동안은 조용하고, 도착해서 소개한다 — 연출로도 이쪽이 맞다.

### 5-3. 좌표계 — `GlobalScreenSpace`를 PuckClient 타깃에 추가

`point_at`은 정규화 좌표(top-left 원점, CGWindowList 공간)를 받는다.
`NSView.convertToScreen`은 AppKit 좌표(bottom-left)를 준다. 변환기
`GlobalScreenSpace`는 `Puck/Movement`에 있고 PuckClient 타깃에 없다.

`project.yml`의 PuckClient sources에 그 **파일 하나만** 추가한다.
`import CoreGraphics`만 쓰는 자족적 값 타입이고, 이 파일은 이미
`SettingsComponents.swift`·`AppLogger.swift`처럼 필요한 파일을 하나씩 이유와
함께 추가하는 방식을 쓴다. 뒤집기 공식을 두 곳에 복제하는 것보다 낫다.

### 5-4. 에디터 — `EditorPaneStore` / `CodeEditorHostView`

```swift
@Published private(set) var reveal: RevealRequest?    // (path, startLine, endLine, token)
func reveal(path: String, lines: ClosedRange<Int>)    // 탭 열기 + 요청 발행
@Published private(set) var paneScreenFrame: CGRect?  // AppKit 화면 좌표
```

- `CodeEditorHostView`가 `reveal`을 관찰해
  `state.cursorPositions = [CursorPosition(start:end:)]` 설정 → 에디터가 스크롤 +
  하이라이트
- **`token`이 필요한 이유**: 같은 범위를 두 번 요청해도 발화해야 한다. 사용자가
  스크롤로 놓친 뒤 "다시 보여줘"가 죽으면 안 된다
- `paneScreenFrame`은 작은 `NSViewRepresentable`이 레이아웃·창 이동 시 갱신.
  에디터가 `.detached`면 분리 창의 좌표를 발행한다

### 5-5. `pet_says` 이벤트 — `BridgeMessages` / `EventRouter`

```swift
case petSays(text: String)   // BridgeEvent
```

`EventRouter.reaction`이 `EventReaction(bubbleText: text)`를 돌려주면 끝이다.
`applyEventReaction`이 이미 `bubbleText`를 `showNoticeBubble`로 넘기므로
`AppDelegate`는 손대지 않는다.

말풍선 수명은 `PointingController.defaultTimeout`(8초)에 맞춘다 — 가리키는
동작과 말이 같이 끝나야 "가리키며 말한다"가 성립한다.

캡션은 160자에서 자른다. `AgentRunner`가 DoneRow 캡션에 쓰는 상한과 같다.
긴 문장은 채팅에 있고 말풍선은 한 줄이다.

## 6. 실패 처리

**원칙: 부분 실패는 투어를 죽이지 않는다.** `AppDelegate+Bridge`의 "Independence
principle: pet-app still works as a pure desktop pet even if the socket can't be
set up"의 거울상이다. 펫이 못 와도 하이라이트와 채팅 설명은 나간다.

| 상황 | 처리 |
|---|---|
| 프로젝트 미바인딩 | 툴을 아예 노출하지 않음 (`read_file`과 같은 규칙) |
| 파일 없음 / 프로젝트 밖 | `WorkspaceFileService`의 경로 봉쇄가 처리. `store.lastError` → 실패 |
| 줄 번호 초과 | 파일 길이로 클램프. `start`가 파일 길이를 넘을 때만 실패 |
| 에디터가 `.hidden` | `revealInEditor(workspaceId:)` + `showWindow()`로 먼저 띄움 |
| 에디터가 `.detached` | 분리 창 좌표 사용 |
| 창이 최소화/다른 Space | `showWindow()` 후에도 화면 밖이면 그 지점만 실패. 안 보이는 곳을 가리키는 것보다 이유를 말하는 게 낫다 |
| 펫 연결 끊김 | 하이라이트는 하고 `ok` + detail로 "펫은 못 왔음". 설명은 채팅에 정상 도착 |
| 사용자 중지 | `tool_cancel` → `point_at`의 취소 경로가 포인팅을 멈춤. `cancelled` 반환 |

연속된 지점은 기존 `pendingPointTracker.replace`가 처리한다 — 두 번째
`point_at`이 첫 번째를 대체하고, 대체된 쪽 콜백도 흘리지 않는다.

다음 지점의 캡션이 이전 것을 덮는 것은 말풍선 세대 태깅(`noticeBubbleGeneration`,
커밋 `b9fa613b`)이 처리한다. 이전 지점의 만료 타이머가 다음 캡션을 조기에 닫던
버그가 이미 고쳐져 있고, 이 기능이 정확히 그 경로를 밟는다.

## 7. 테스트

유닛 테스트로 가능한 것 (모두 `Puck` 타깃이라 `@testable import Puck`로 닿는다):

- `CodeTourDelegate` — 줄 번호 클램프, 프로젝트 미바인딩, 경로 봉쇄, 펫 끊김 시 저하 동작
- `EditorPaneStore.reveal` — 같은 범위를 두 번 요청해도 토큰이 올라 재발화하는지
- `EventRouter` — `petSays` → `bubbleText` 매핑
- `BridgeMessageCodableTests` — `pet_says` 왕복 인코딩 (기존 파일에 추가)
- `GlobalScreenSpace` — 변환 테스트가 이미 있다

유닛 테스트로 불가능한 것: 펫이 실제로 걸어가 그 자리를 가리키는지. 살아있는 두
앱과 화면이 필요하다. `docs/verification.md`에 수동 검증 행을 추가한다 — 이
저장소가 이미 쓰는 방식이다.

## 8. 열린 항목

- **외부 에디터**: VS Code·Xcode는 AX 트리에 "몇 번째 줄이 어디"를 노출하지 않아
  창 단위까지만 가리킬 수 있다. 별도 기능으로 미룬다
- **줄 단위 정밀 조준**: §4 참조. 좌표를 만드는 §5-2 한 군데만 바꾸면 되므로
  이 설계를 되돌리지 않고 얹을 수 있다
- **`DetachedEditorWindow` 연출**: 에디터를 분리 창으로 띄우면 펫의 기존 창
  올라타기(`WalkOnTopState`)를 재사용해 연출이 살아난다. 사용자 레이아웃을 임의로
  바꾸는 것이라 이번 범위에서 뺐다
- **`docs/verification.md`의 기존 `Pending` 2행**: 클린 체크아웃 CI 최초 원격
  실행, 서명 앱 수동 스모크. 그 문서 규칙이 "모든 행이 Pass여야 릴리스 준비"인데
  이 기능이 행을 하나 더 늘린다
