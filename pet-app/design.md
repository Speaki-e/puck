# Puck 디자인 시스템 (현재 구현 기준)

> **디자인 시스템 v2 — 2026-08-14.** 아래 문서는 이전 팔레트/테마 체계(호박 주황 accent +
> 다크/화이트/글래스 3무드)를 전면 교체한 결과를 기록한다. 근거/배경은 `docs/decisions.md`의
> 2026-08-14 항목 참고 — 교체 사유는 기술적 결함이 아니라 아트디렉션 전면 재조정이었다.
> `.glass` 테마는 폐기됐다(macOS 26+ 전용 기능 유지보수 비용 대비 실익이 낮다는 판단,
> `docs/decisions.md`).
>
> 별도 사실 하나 더: F13 클라이언트 창의 사이드바/탑바/메시지 목록은 이 v2 작업보다 하루 앞선
> 2026-08-13에 이미 `chat-web/`(React/Tailwind/shadcn)로 옮겨갔고 `ChatView.swift`/
> `ClientSidebarView.swift`는 삭제됐다(`docs/decisions.md` "PuckClient's chat UI moved to
> web"). `ClientWindowView.swift`가 실제로 그리는 건 `ClientChatWebView`(그 chat-web을 호스팅하는
> WKWebView) + 조건부 네이티브 `EditorPaneView`(§9.5) + 상시 `ClientStatusBarView`(§4.5) 셋뿐이다.
> 이번 v2는 그 레이아웃 재설계를 하지 않았다(스코프 밖, 위 스펙 §6) — 아래 §6 이하가 여전히
> 사이드바/말풍선 레이아웃을 서술하는 건 그 이전 상태의 기록이고, 지금 pet-app Swift 코드가
> 아니라 chat-web 쪽 이야기다. `ClientPalette`/`ClientTheme`의 실제 현재 소비처는 Settings
> 화면(`Puck/Settings/*.swift`)과 네이티브 에디터 뷰(`Puck/ClientWindow/Editor/*.swift`,
> `StatusDotView`/`ClientStatusBarView`) — chat-web/workspace의 CSS도 같은 원시값을 공유한다
> (§2 참고, 확인함).
>
> **v3 — 2026-08-15 클라이언트 레이아웃 재작업.** 바로 위 문단이 "이번 v2는 그 레이아웃
> 재설계를 하지 않았다"고 적어둔 그 레이아웃을, v3가 다시 손댔다 — 여전히 전부 `chat-web/`
> 쪽이고 pet-app Swift 코드(§1-3, §5, §9.5)는 그대로다. Swift 쪽 변경은 셋뿐이다:
> `ChatSession.lastActivityAt`/`lastRunOk`(세션 활동 시각·마지막 실행 결과), `StatusDotView`의
> `pulses` 파라미터, `ClientStatusBarView`가 그리는 내용(§4.5). 아래 §6은 이제 **v3 기준 현재
> 상태**로 다시 썼다 — 사이드바가 워크스페이스 트리로, 상단 pill 탑바가 탭 스트립으로, 툴
> 호출/결과 두 줄이 카드 하나로 바뀐 게 핵심이다. §4.5도 v3에서 바뀐 부분(펄스 긴장 해소,
> 상태 바 실제 표시 내용)을 반영해 갱신했다.

F13 클라이언트 창의 디자인이 확정된 상태를 **코드에 실제로 존재하는 값 그대로** 기록한 문서다.
새 디자인 제안이 아니라 현황 스냅샷이며, 값이 바뀌면 이 문서가 아니라 아래 소스가 먼저 바뀐다.

| 역할 | 파일 |
|---|---|
| 색 토큰 (2세트: light/dark) | `Puck/ClientWindow/ClientPalette.swift` |
| 타입·간격·모양 토큰 | `Puck/ClientWindow/ClientTheme.swift` |
| 테마 선택/동기화 | `Puck/ClientWindow/ClientThemeStyle.swift` |
| 팔레트 주입 | `Puck/ClientWindow/ClientPaletteEnvironment.swift` |
| 상태 점 컴포넌트 | `Puck/ClientWindow/StatusDotView.swift` |
| 상태 바 | `Puck/ClientWindow/ClientStatusBarView.swift` |

원칙 하나: **뷰는 시스템 색/폰트를 직접 쓰지 않는다.** 전부 `ClientPalette`(색)와 `ClientTheme`(그 외)에서 나온다.

---

## 1. 테마 — light / dark

`ClientThemeStyle`은 이제 정말 라이트/다크 축이다(v1은 독립적으로 아트디렉션된 3개 무드 — 다크,
화이트, 글래스 — 였다). `.glass`는 v2에서 완전히 삭제됐다.

| 값 | 표시명 | colorScheme |
|---|---|---|
| `.light` | 화이트 | light |
| `.dark` | 다크 | dark |

- 기본값(파싱 실패 시 폴백)은 `.dark` — 이 앱이 원래 갖고 있던 룩.
- 저장 위치는 Puck 쪽 `SettingsStore`(`Puck.clientThemeStyle`). 채팅 창 안이 아니라 **메뉴막대 → Puck 설정 → "채팅 테마"** 에서 바꾼다.
- PuckClient는 별도 프로세스라 UserDefaults를 못 읽는다. `ClientThemeStyle.crossProcessChangeNotification`으로 브로드캐스트하되 **값을 notification userInfo에 실어 보낸다** — `UserDefaults.set()` 직후 다른 프로세스에서 읽으면 아직 옛 값일 수 있는 실제 레이스가 있었다.
- 앱 전체 외관(`AppAppearance`: system/light/dark, 펫 오버레이·노치·설정창)은 이것과 **별개 설정**이다.

## 2. 색 토큰

`ClientPalette`는 12개 프로퍼티 — 10개 저장 필드 + 2개 계산 프로퍼티. 계산 프로퍼티는 다른 필드를
재사용해서 절대 따로 어긋나지 않는다: `statusIdle { textSecondary }`, `statusActive { accent }`.

`background` `surface` `surfaceBorder` `textPrimary` `textSecondary` `accent` `onAccent`
`statusSuccess` `statusError` `statusWarning` (저장) · `statusIdle` `statusActive` (계산)

### light

| 토큰 | 값 |
|---|---|
| background | `#fafafa` |
| surface | `#ffffff` |
| surfaceBorder | `#e5e5e5` |
| textPrimary | `#1a1a1a` |
| textSecondary | `#6b6b6b` |
| accent | `#ed8c33` |
| onAccent | `#ffffff` |

### dark

| 토큰 | 값 |
|---|---|
| background | `#0a0a0a` |
| surface | `#131313` |
| surfaceBorder | `#242424` |
| textPrimary | `#ededed` |
| textSecondary | `#7a7a7a` |
| accent | `#ed8c33` |
| onAccent | `#161616` (거의 검정 — 이 팔레트에서는 흰색보다 accent 위 대비/무드가 낫다) |

v2 값은 Orca 레퍼런스 기반으로 새로 잡은 값이다(`docs/decisions.md`의 2026-08-14 항목 참고)
— v1처럼 workspace CSS를 그대로 옮겨온 게 아니라, **세 소비처(`ClientPalette.swift`,
`chat-web/src/styles.css`, `workspace/src/renderer/styles.css`)를 같은 값으로 동시에 갈아끼웠다.**
실제로 확인한 결과 `chat-web/src/styles.css`의 `--ink`/`--mute`/`--hairline`/`--canvas`/`--surface`/
`--brand`와 `workspace/src/renderer/styles.css`의 동일 변수들이 위 표와 정확히 같은 hex를 쓴다(light
변형도 동일 — workspace/chat-web은 이전엔 다크 전용이었는데 v2에서 라이트 세트가 새로 추가됐다).

### 상태 색 (v2 신규)

| 토큰 | 값 | 비고 |
|---|---|---|
| `statusSuccess` | `#3fb950` | light/dark 공통(테마 무관 고정) |
| `statusError` | `#f85149` | light/dark 공통 |
| `statusWarning` | `#e3b341` | light/dark 공통 |
| `statusIdle` | `textSecondary` 재사용 | 계산 프로퍼티 |
| `statusActive` | `accent` 재사용 | 계산 프로퍼티 |

`statusSuccess`/`statusError`/`statusWarning`은 accent와 마찬가지로 라이트/다크 두 팔레트에서 값이
동일하다(테마가 바뀌어도 안 바뀐다). 오늘 기준 실제 소비처는 둘뿐이다: `statusWarning`은
`ConflictBannerView`(디스크 변경 경고 아이콘)에서 직접 쓰고, 나머지 네 값은 `StatusDotView`/
`DotStatus`를 거쳐 `ClientStatusBarView`(§4.5)에서 쓰인다.

### accent 사용 규칙

accent는 **여전히 유일하게 튀는 색**이고 값도 안 바뀌었다(`#ed8c33`, light/dark 공통, chat-web
`--brand`/workspace `--brand`와도 동일 — 확인함). 다만 구체적으로 어디에 칠해지는지(전송 버튼,
활성 행, 말풍선 배경 등)는 이제 chat-web 쪽 React 컴포넌트의 영역이고, 이번 v2 재작성은 화면
레이아웃을 다시 건드리지 않았다(스코프 밖, 위 스펙 §6). v1 문서가 나열했던
`accent.opacity(0.14)`류 구체 수치는 이미 정확하지 않았다 — 실제로 확인해보니 chat-web은 opacity
대신 `--brand-soft`(`#3d2612`) 같은 별도 고정 토큰을 쓰는 쪽으로 이미 바뀌어 있었다. 그래서 여기선
그 수치를 다시 단정하지 않는다.

## 3. 타이포그래피

전부 `Font.system`, 기본 디자인. `mono`만 monospaced로 예외. v1의 11개 토큰 중 6개만 남았다(Task 3,
쓰는 곳이 없어진 토큰은 이름만 남겨두지 않고 그대로 삭제).

| 토큰 | 정의 | 용도 |
|---|---|---|
| `sectionHeader` | caption · semibold | 설정창 섹션 제목(`SettingsSection`) |
| `workspaceName` | callout · medium | 설정창 헤더의 앱 이름 |
| `sessionTitle` | footnote | 범용 라벨 — 설정 행 라벨, 에디터 빈 상태/로딩 메시지 |
| `toolLabel` | footnote · medium | 충돌 배너(`ConflictBannerView`) 제목 |
| `mono` | caption · monospaced | 상태 바의 워크스페이스명, 설정 슬라이더 라이브 값, 이미지 미리보기 캡션 |
| `caption` | caption2 | 탭 스트립 파일명, 파일트리 행, 충돌 배너 부제 |

전부 시스템 텍스트 스타일 기반이라 **동적 타입(사용자 글자 크기)을 따라간다.**

## 4. 간격·크기·모양

```
spacingSmall    4      cardCornerRadius   6
spacingMedium   8      rowCornerRadius    4
spacingLarge   12
windowMinWidth 960     windowMinHeight  640
```

v1의 11개 메트릭 중 7개만 남았다 — 사이드바 폭/말풍선 최대폭/아바타 크기는 그 값을 쓰던 뷰(구
ChatView 계열)와 함께 삭제됐다.

- 코너 라운딩은 v2에서 한 단계 더 줄었다(`cardCornerRadius` 12→6, `rowCornerRadius` 6→4) — chat-web/workspace의 `--radius` 계열도 같은 방향으로 같이 줄었다(`ClientTheme.swift`의 코드 주석 기준, Task 6).
- 모양은 `ClientTheme.Shapes`에 `card`/`row` 두 개만 선언돼 있다(둘 다 `style: .continuous`) — v1에 있던 `bubble`/`panel` 모양은 그걸 쓰던 뷰와 함께 없어졌다.
- `spacingSmall`/`spacingMedium`/`spacingLarge`는 `ClientWindow/Editor/*`뿐 아니라 `Puck/Settings/*`, `PuckClient/AgentSettingsView.swift`에서도 쓰인다 — ClientWindow 폴더 전용 토큰이 아니라 Puck 쪽 UI 전반의 공용 간격 스케일이다.
- `windowMinWidth`/`windowMinHeight`는 SwiftUI `.frame(minWidth:)`(`ClientWindowView.swift`)와 AppKit `NSWindow.minSize`(`PuckClient/AppDelegate.swift`)가 **같은 상수 하나**를 읽는다.

## 4.5 상태 표현 (신규) — `StatusDotView` / `ClientStatusBarView`

이 절은 v2에서 새로 생긴 것(Task 4-5) — v1 문서에는 없었다.

**`DotStatus`**(`Puck/ClientWindow/StatusDotView.swift`)는 4개 case다: `idle`/`active`/`success`/`error`,
각각 `palette.statusIdle`/`statusActive`/`statusSuccess`/`statusError`로 매핑된다. `StatusDotView`는
지름 6pt(호출부에서 override 가능) 원 하나를 그리고, **`.active`일 때만 펄스**한다(불투명도
1↔0.4, `.easeInOut(duration: 0.9).repeatForever(autoreverses: true)`) — idle/success/error는 정지된
상태를 나타내므로 모션이 없다.

**`ClientStatusBarView`**는 `ClientWindowView`의 콘텐츠 아래(항상 표시되는 얇은 바, height 22,
`palette.surface` 배경 + 위쪽 1px `palette.surfaceBorder` 헤어라인)에 상태 점 + 프로젝트 경로 +
세로 헤어라인 구분선 + 모델 이름, 이렇게 네 조각을 왼쪽부터 순서대로 보여준다(v3, Task 3 —
이전엔 워크스페이스 이름 하나뿐이었다). 프로젝트 경로는 `abbreviatedPath(_:home:)`로 홈 디렉터리
접두사만 `~`로 줄인 값(`/Users/x/dev/p` → `~/dev/p`, 경로 경계에서만 치환하므로 `/Users/xyz`가
홈이 `/Users/x`일 때 잘못 잘리지 않는다)이고, 프로젝트가 없는 워크스페이스(`projectPath == nil`)는
그 워크스페이스 이름("일상 대화" 등)을 그대로 쓴다. 모델 이름은 `AgentConfiguration.load().model`을
매 렌더마다 새로 읽는다 — 스토어에서 주입받지 않는 이유는 코드 주석 그대로: 모델이 바뀌려면
리빌드나 `.env` 수정이 필요하지, 이 뷰가 실시간으로 관찰해야 할 값이 아니기 때문. 두 텍스트 모두
`ClientTheme.Typography.mono` + `palette.textSecondary`. `dotStatus(for:)`가 `EditorAvailability`를 `DotStatus`로 매핑한다:
`.noProject → .idle`, `.ready → .success`, `.unavailable → .error`. **`.active`는 이 매핑에서 절대
나오지 않는다** — 상태 바 자체는 idle/success/error 세 값만 보여준다.

이름에 대한 코드 주석을 그대로 옮기면: "Reports the active workspace's editor/project status --
deliberately not called 'connection', since that term means the pet-app↔workspace bridge socket
elsewhere in this codebase and this bar doesn't observe that." 즉 이 바가 보여주는 건 브릿지 소켓
연결 여부가 **아니라** 에디터/프로젝트 상태다 — 이름을 헷갈리지 않게 의도적으로 고른 것.

**두 번째 소비처, 그리고 v3에서 해소된 긴장**: `EditorTabStripView`가 더러워진(unsaved) 파일 탭
옆에 `StatusDotView(status: .active, palette: palette, diameter: 5, pulses: false)`를 붙인다. v2
문서가 여기 적어뒀던 긴장 — `.active`는 원래 "실행 중" 같은 **짧게 지속되는 진행 상태**를 위해
설계됐는데, dirty 플래그는 사용자가 저장하기 전까지 무기한 지속되면서도 계속 펄스했다 — 는 v3
(Task 2)에서 `StatusDotView`에 `pulses: Bool = true` 파라미터를 추가하는 것으로 풀렸다.
`EditorTabStripView`는 이제 `pulses: false`를 넘겨서, 색은 `.active`(accent)를 그대로 쓰되 애니메이션
없이 정지해 있다. 즉 세션 어휘에서 `.active`의 의미는 이제 확실히 "지금 진짜로 실행 중"(짧게
지속) 하나로 좁혀졌고, dirty 표시처럼 무기한 지속되는 상태는 `.active`의 색만 빌리되 펄스는 끈
별도 표현으로 분리됐다 — 이 구분은 chat-web 쪽 `StatusDot`(아래 §6의 "사이드바 구성"/"탭
스트립" 절, `sessionDotState`)에서도 그대로 지켜진다: 실행 중일 때만 `active`(펄스), 마지막
실행 결과는 `ok`/`error`(정지), 아직 한 번도 실행 안 했으면 `idle`(정지)이다.

## 5. 표면

`GlassSurface.swift`는 Task 1-2 수정 라운드에서 **완전히 삭제됐다**(단순화된 게 아니라 파일 자체가
없어짐). 대체할 공용 `themedSurface`류 함수도 새로 만들어지지 않았다 — 팔레트가 라이트/다크
둘뿐이고 둘 다 항상 플랫이라 분기할 게 없기 때문이다. 호출부마다 필요한 만큼만 직접 조합한다:

```
배경만                    .background(palette.surface)
                          (EditorTabStripView, FileTreeView)

배경 + 테두리 카드         .background(palette.surface)
                          .clipShape(ClientTheme.Shapes.card)
                          .overlay(ClientTheme.Shapes.card.stroke(palette.surfaceBorder))
                          (ConflictBannerView — 이 패턴의 유일한 사용처)

배경 + 위쪽 헤어라인만     .background(palette.surface)
                          .overlay(alignment: .top) {
                              Rectangle().fill(palette.surfaceBorder).frame(height: 1)
                          }
                          (ClientStatusBarView)
```

`VisualEffectBackground`(`NSVisualEffectView` 래퍼)도 이번 라운드에서 **완전히 삭제됐다** — 확인
결과 아무 뷰도 쓰지 않는 죽은 코드였고, 원래 (이미 삭제된) 사이드바 배경용으로 만들어졌던 것으로
보인다. `GlassSurface.swift`(SwiftUI 쪽 절반, 이미 삭제됨)와 같은 이유로 같이 삭제됐다.

## 6. 레이아웃

> **이 절은 v3(2026-08-15) 기준 현재 상태다.** 여기 서술하는 화면은 전부 `chat-web/`
> (React/Tailwind/shadcn)이 그린다 — pet-app Swift에는 이 레이아웃 코드가 없다. 창 크롬(아래
> 첫 항목)만 예외로 Swift(`PuckClient/AppDelegate.swift`) 소관이다.

### 창 크롬 (Swift)

`.titled + .closable + .resizable + .miniaturizable + .fullSizeContentView`, `titlebarAppearsTransparent = true`, `titleVisibility = .hidden`. 콘텐츠가 타이틀바 아래까지 올라가 사이드바 배경이 신호등까지 닿는다.

> 알려진 미해결 이슈: 신호등 주변 색이 어긋나 보이는 문제. `isOpaque = false` + `backgroundColor = .clear`를 시도했으나 **더 나빠져서 되돌렸다.** 이 트릭은 진짜 borderless 창(오버레이/노치/입력 버블)에만 통하고, `.titled` 창은 네이티브 타이틀바 컨테이너가 콘텐츠 위에 따로 있어서 창을 비불투명으로 만들면 그 레이어의 반투명이 데스크톱을 비친다.

### 골격

```
App.tsx
├ Sidebar                    220 / 68 (접힘), 우측 1px hairline, bg-surface
└ 메인 컬럼 (flex-1)
  ├ h-7 스페이서             신호등 자리 비우기 (Sidebar도 같은 값)
  ├ TabStrip                 h-34, bg-surface, 아래 1px hairline
  ├ ChatTranscript
  ├ RunningStatusLine        실행 중일 때만
  ├ ApprovalBanner           승인 대기 중일 때만
  └ ChatInputBar
ClientStatusBarView (Swift)  창 전체 폭, h-22 — §4.5
```

사이드바 폭은 `EXPANDED_WIDTH = 220` / `COLLAPSED_WIDTH = 68`(v2 이전 Swift 값 그대로 승계),
접기 전환은 `transition-[width] duration-[180ms] ease-in-out`.

### 사이드바 구성 (v3에서 전면 교체)

**워크스페이스 트리**다. v2까지는 워크스페이스 스위처(팝오버)로 하나를 고른 뒤 그 워크스페이스의
세션만 평평하게 나열했는데, 이제 **모든 워크스페이스를 펼쳐서 세션을 그 아래 중첩**한다. 다른
워크스페이스의 세션을 보려고 팝오버를 열 필요가 없다.

- 워크스페이스 그룹 = 캐럿 + 이름 + 세션 수, `projectPath`가 있으면 그 아래 mono 소자 한 줄
- 접기/펼치기는 그룹 단위 로컬 상태(`collapsedWorkspaceIds`), 영속화하지 않는다
- 새 채팅은 **그룹별 호버 버튼**(`SquarePen`)이고 `newSession(workspace.id, "새 채팅")`을 부른다
  — v2에서 스위처 팝오버가 갖고 있던 동작이 여기로 옮겨왔다
- 세션 행 = `StatusDot` + 제목 + 상대 시간(`relativeTime`), 활성 행은 `bg-brand/14`
- `WorkspaceSwitcher.tsx`/`SessionList.tsx`는 삭제됐다

**활성 행 판정은 `state.activeSession`에서 읽는다** — `state.activeSessionId`가 아니다. 후자는
hydrate/워크스페이스 목록 푸시 때만 갱신되고 `switchSession`마다 갱신되지 않아서, 탭으로 세션을
바꾸면 엉뚱한 행이 강조된다. 게다가 워크스페이스별로 스코프를 걸어(`workspace.id === activeWorkspaceId`)
다른 워크스페이스의 동명 세션 id가 잘못 강조되는 것도 막는다. `App.tsx`의 메시지 라우팅도 같은
이유로 같은 값을 쓴다(아래 참고).

### 탭 스트립 (v3 신규)

상단 pill 하나뿐이던 탑바(`TopBar.tsx`/`SessionSelector.tsx`, 둘 다 삭제)를 대체한다.

- 탭 = `StatusDot` + 제목(`max-w-[200px] truncate`) + `×`, 탭 자체는 `max-w-[260px]`
- 활성 탭은 `bg-canvas`(본문과 같은 색으로 이어짐) + 상단 2px `bg-brand` 인디케이터
- 우측 끝 `+`(w-30)는 새 세션, 그 옆에 `EditorToggleButton`·`SettingsButton`
- **열린 탭 목록은 렌더러 로컬 상태다.** 사이드바든 탭이든 세션을 고르면 없으면 추가되고 있으면
  활성화된다. `×`는 **탭만 닫고 세션은 지우지 않는다** — 세션은 사이드바에 그대로 남는다.
  활성 탭을 닫으면 이웃 탭이 활성화된다

### 채팅 영역

- 트랜스크립트/빈 상태/입력바 모두 720px로 중앙 정렬
- 메시지 라우팅(`sendMessage`/`cancelRun`/`respondApproval`)은 `state.activeSession.workspaceId`/`.id`를
  쓴다. v3 이전엔 `state.activeWorkspaceId`/`activeSessionId`를 썼는데, 위 사이드바 항목이 설명한
  staleness 때문에 **세션을 바꾼 뒤 보낸 메시지가 이전 세션으로 가는 실제 버그**였다. 탭이 생기며
  전환이 일상 경로가 되자 드러났다(Task 7에서 수정)
- `state.activeWorkspaceId`/`activeSessionId` 필드 자체는 리듀서에 남아 있다 — 다른 소비처가 있어서
  제거하지 않았고, 라우팅에만 쓰지 않는다

### 툴 호출 표현 (v3에서 카드 하나로 병합)

v2까지 툴 호출(`ToolCallCard`)과 툴 결과(`ToolResultRow`)가 별도 표면 두 개였는데, `ChatSession.swift`가
둘이 같은 `tool_use` id를 공유한다고 명시하고 있어 **호출 하나당 카드 하나**로 합쳤다.
`ChatTranscript`가 id로 짝지어 넘기고, `ToolResultRow`는 짝을 못 찾은 경우의 방어적 폴백으로만 남아
`ToolCallCard`가 export하는 `KVRows`를 공유한다(스타일 중복 없음).

- 헤더: `StatusDot` + 도구명(mono, `text-ink`)
- 본문: `키: 값` 나열 — 키 `text-faint`, 값 `text-mute`, 전부 mono
- 카드: `bg-surface` + `border-hairline` + `rounded-md`

### 실행 상태 줄 (v3 신규)

`RunningStatusLine` — 활성 세션이 실행 중일 때만 나타난다. 좌측에 스피너 + "실행 중… `esc` 로 중단",
우측에 프로젝트 경로(mono, `text-faint`).

**모델 이름은 여기 없다.** `model={null}`로 넘어가고 경로만 그린다 — 모델은 브릿지에 실려 있지 않고
네이티브 상태 바(§4.5)만 `AgentConfiguration`에서 직접 읽는다. 웹 쪽으로 끌어오는 건 의도적으로
미뤄둔 **후속 과제**이지 누락이 아니다.

### 말풍선

사용자/어시스턴트가 **같은 채움**을 쓰고, 구분은 아바타+이름 행과 정렬로만 한다.

### 빈 상태

호박 마크 + 인사말 2줄. 프롬프트 추천 카드와 마크 뒤 글로우는 없다.

## 7. 상태 표현 규칙

| 상태 | 표현 |
|---|---|
| 활성(세션/워크스페이스 행) | `accent.opacity(0.14)` 채움 + accent 아이콘 |
| 호버(세션 행) | `surfaceBorder.opacity(0.6)` 채움 |
| 호버(설정 액션 행) | `.quaternary` 채움 |
| 호버(새 채팅) | `opacity 0.8` |
| 비활성(전송 버튼) | 회색 원(`surfaceBorder`) → 활성 시 accent 채움. 투명도 페이드가 아니다 |
| 실행 중 | 세션 행에 `ProgressView`, 입력바 전송 버튼이 정지 버튼으로 교체 |

## 8. 접근성

아이콘만 있는 버튼은 전부 `.accessibilityLabel` + `.help`를 단다 — 사이드바 접기/펼치기, 새 채팅, 워크스페이스 전환(`accessibilityValue`에 현재 이름), 세션 전환, 설정.
접힘 상태에서 글자 하나뿐인 워크스페이스 버튼처럼, 화면에 읽을 텍스트가 없는 컨트롤이 판정 기준이다.

## 9. 설정창 (같은 토큰, 다른 형태)

`SettingsComponents.swift`. pokoPet 메뉴막대 팝오버가 레퍼런스이고, 360×560 단일 패널이다.

**섹션마다 카드를 두지 않는다** — 패널이 유일한 표면이고 나머지는 그 위에 바로 얹힌다. 이전의 GlassCard 스택이 "슬래브 더미"처럼 보였던 원인이라 걷어냈다.

- `SettingsSection` — 회색 소제목만, 배경 없음
- `SettingsRow` — 라벨 좌 / 컨트롤 우
- `SettingsStackedRow` — 넓은 컨트롤(슬라이더·세그먼트)용, 라벨 위 컨트롤 아래. 우측에 라이브 값(mono)
- `ToyTile` — 그리드 타일. 채움은 아이템 **자기 아트워크의 틴트**(`0.14`, 꺼내둔 상태면 `0.28` + 1.5pt 링). 이 창에서 색이 살아남는 유일한 자리이며 앱 accent와 무관
- `SettingsActionRow` — 텍스트 + 셰브론, 호버 전까지 버튼 크롬 없음

## 9.5 코드 에디터 표면 (2026-08-14 신규)

`Puck/ClientWindow/Editor/`(파일트리·탭·`CodeEditSourceEditor` 호스팅)는 chrome(파일트리 행, 탭, 빈 상태, 충돌 배너)에 §2의 `ClientPalette`를 그대로 쓴다 — 새 표면이라고 별도 색 체계를 만들지 않았다.

구문 강조만 예외다. `CodeEditorHostView.theme(for:)`가 `ClientPalette`에서 **5개 필드**
(`background`/`surface`(lineHighlight로)/`textPrimary`/`textSecondary`/`accent`)를 물려받는다 —
그중 `accent`는 insertionPoint·selection(25% 알파)·strings·characters 네 자리에 재사용되고,
`textSecondary`는 invisibles와 comments(이탤릭)에 재사용된다. 그 위에 코드 전용으로 고정된 3색
(키워드 보라·타입 청록·리터럴 녹색, 팔레트 무관 고정 hex)을 얹는다. 코드 색 팔레트는 UI 색 토큰
10개보다 훨씬 많은 구분이 필요해서 나온 의도적 예외이지, 누락이 아니다.

**미검증 항목**: 이 3색(보라/청록/녹색)은 `.dark`(어두운 배경) 기준으로 고른 값이라 `.light` 팔레트(흰 배경)에서도 대비가 충분한지 실제로 확인된 적이 없다 — 렌더링해서 눈으로 봐야 판단 가능한 사안이라 이번 정리에서는 건드리지 않았다.

## 10. 이 문서에 없는 것

- 펫 오버레이(F1)·텍스트 입력 버블(F6)은 `ClientTheme` 토큰을 쓰지 않는 별개 표면이다.
- ~~에디터 뷰(`EditorWebView`)는 아직 어디에도 호스팅되지 않는다~~ — **2026-08-14 해소**. `EditorWebView`(workspace가 서빙하는 웹 뷰) 자체는 삭제되고 네이티브 `Puck/ClientWindow/Editor/`로 대체됐다(위 9.5절, `docs/decisions.md` 참고). "에디터는 따로 할거라 토글 빼"는 그 사이 임시 상태를 설명하던 문장이라 더 이상 유효하지 않다.
- `onAccent`(§2)는 `ClientPalette`에 정의돼 있지만, 실제로 확인해보니 pet-app Swift 뷰 중 이 필드를 읽는 곳이 **아직 없다** — accent 위에 텍스트/아이콘을 얹는 자리가 지금 pet-app 네이티브 코드엔 없다(chat-web 쪽엔 있을 수 있으나 확인 안 함). v1에서 `success`/`failure`/`warning`이 시스템 색 그대로였던 것과 비슷한 모양의, 정의는 됐지만 아직 안 쓰이는 필드.
- chat-web의 세션 전환(세션 스위처) UI는 이번 계획에서 한 번도 들여다보지 않았다(Task 7 노트) — `EditorTabStripView`(§4.5, §5)에 적용한 탭 스트립 패턴과 시각적으로 맞는지는 검증되지 않은 별도 후속 과제다.
