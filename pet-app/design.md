# Puck 디자인 시스템 (현재 구현 기준)

> **디자인 시스템 v2 — 2026-08-14.** 아래 문서는 이전 팔레트/테마 체계(호박 주황 accent +
> 다크/화이트/글래스 3무드)를 전면 교체한 결과를 기록한다. 근거/레퍼런스(Orca)는
> `docs/superpowers/specs/2026-08-14-design-system-v2-design.md` 참고 — 교체 사유는 기술적
> 결함이 아니라 아트디렉션 전면 재조정이었다. `.glass` 테마는 폐기됐다(macOS 26+ 전용 기능
> 유지보수 비용 대비 실익이 낮다는 판단, `docs/decisions.md`).
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

v2 값은 Orca 레퍼런스 기반으로 새로 잡은 값이다(`docs/superpowers/specs/2026-08-14-design-system-v2-design.md`
§1) — v1처럼 workspace CSS를 그대로 옮겨온 게 아니라, **세 소비처(`ClientPalette.swift`,
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
`palette.surface` 배경 + 위쪽 1px `palette.surfaceBorder` 헤어라인)에 워크스페이스 이름(mono)과
상태 점 하나를 보여준다. `dotStatus(for:)`가 `EditorAvailability`를 `DotStatus`로 매핑한다:
`.noProject → .idle`, `.ready → .success`, `.unavailable → .error`. **`.active`는 이 매핑에서 절대
나오지 않는다** — 상태 바 자체는 idle/success/error 세 값만 보여준다.

이름에 대한 코드 주석을 그대로 옮기면: "Reports the active workspace's editor/project status --
deliberately not called 'connection', since that term means the pet-app↔workspace bridge socket
elsewhere in this codebase and this bar doesn't observe that." 즉 이 바가 보여주는 건 브릿지 소켓
연결 여부가 **아니라** 에디터/프로젝트 상태다 — 이름을 헷갈리지 않게 의도적으로 고른 것.

**두 번째 소비처, 그리고 아직 해소되지 않은 긴장**: `EditorTabStripView`(Task 7)가 더러워진(unsaved)
파일 탭 옆에 `StatusDotView(status: .active, ..., diameter: 5)`를 붙인다. 디자인 리뷰에서 지적된
지점: 원래 스펙(위 design spec §4)에서 `.active`는 "실행 중" 같은 **짧게 지속되는 진행 상태**를
위해 설계됐는데, dirty 플래그는 사용자가 저장하기 전까지 무기한 지속될 수 있고 그동안 계속
펄스한다 — 세션 내내 켜져 있는 게 가능한 유일한 `.active` 사용처다. 이게 명백히 잘못됐다는
뜻은 아니다("저장 안 한 파일이 있다"는 신호 자체는 유용하다) — 다만 `.active`의 원래 의미에서
꽤 벌어져 있고, 이 문서를 쓰는 시점까지 그대로 남아 있는 **열린 질문**이다. 계속 펄스하게 둘지,
dirty 표시는 펄스 없는 다른 표현으로 바꿀지는 별도 결정이 필요하다.

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

`VisualEffectBackground`(`Puck/ClientWindow/VisualEffectBackground.swift`, `NSVisualEffectView`
래퍼)는 파일 자체는 아직 남아 있지만, 실제로 확인해보니 **현재 아무 뷰도 이걸 쓰지 않는다** —
원래 (이미 삭제된) 사이드바 배경용으로 만들어졌던 것으로 보이는 죽은 코드다. 왜 같이 정리되지
않았는지는 이번 v2 스코프 밖이라 확인하지 않았다.

## 6. 레이아웃

> 아래 이 절부터 §9까지는 위 배너에서 이미 밝혔듯 **2026-08-13 chat-web 이전 상태의 기록**이다.
> 사이드바/탑바/말풍선은 지금 pet-app Swift 코드에 없고 `chat-web/`(React/Tailwind/shadcn)로
> 옮겨갔다 — 이번 v2 작업은 그 레이아웃을 다시 서술하거나 검증하지 않았다(스코프 밖).

### 창 크롬

`.titled + .closable + .resizable + .miniaturizable + .fullSizeContentView`, `titlebarAppearsTransparent = true`, `titleVisibility = .hidden`. 콘텐츠가 타이틀바 아래까지 올라가 사이드바 배경이 신호등까지 닿는다.

> 알려진 미해결 이슈: 신호등 주변 색이 어긋나 보이는 문제. `isOpaque = false` + `backgroundColor = .clear`를 시도했으나 **더 나빠져서 되돌렸다.** 이 트릭은 진짜 borderless 창(오버레이/노치/입력 버블)에만 통하고, `.titled` 창은 네이티브 타이틀바 컨테이너가 콘텐츠 위에 따로 있어서 창을 비불투명으로 만들면 그 레이어의 반투명이 데스크톱을 비친다.

### 골격

```
HStack(spacing: 0)
├ ClientSidebarView              220 / 68, 우측 1px hairline
└ VStack(spacing: 0)             minWidth 420
  ├ topBar                       세션 선택 pill · (spacer) · 설정 기어
  ├ Divider().opacity(0.5)
  └ ChatView
```

- 상단 여백 28pt는 투명 타이틀바/신호등을 비우는 값. 사이드바도 같은 28pt `Color.clear`로 시작한다.
- 사이드바는 메인 컬럼과 **같은 흰색**이고 hairline으로만 구분한다 — 더 어두운 채움이 아니다(Figma 그대로).
- 접기/펼치기 토글은 사이드바 우상단(푸터 아님). 펼침이면 워크스페이스 옆에 나란히, 접힘이면 세로로 쌓는다(68pt엔 한 줄에 둘이 안 들어간다).
- 접기 애니메이션은 `.easeInOut(duration: 0.18)`.

### 사이드바 구성

워크스페이스 스위처(팝오버) → 새 채팅 버튼 → `채팅 N개` 섹션 헤더 → 세션 목록.
접힘 상태에선 세션 목록이 사라진다. 세션 전환은 사이드바를 펼치거나 상단바 pill로 한다.

### 채팅 영역

- 트랜스크립트/빈 상태/입력바 모두 `contentMaxWidth` 720으로 중앙 정렬.
- 입력바는 `safeAreaInset(edge: .bottom)`이다 — VStack 행이 아니라. 트랜스크립트가 입력 카드 **아래로 스크롤해 지나가야** 고정된 것처럼 읽힌다.
- 입력 컨테이너만 `Capsule()`(레퍼런스의 `rounded-[9999px]`), 나머지 카드/버블은 24 라운딩.
- 그 아래 "…는 실수를 할 수 있어요." 디스클레이머 캡션.

### 말풍선

사용자/어시스턴트가 **같은 채움**(`accent.opacity(0.06)`)을 쓰고, 구분은 오직 아바타+이름 행과 정렬(좌/우)로만 한다. 텍스트는 양쪽 다 `textPrimary` — 이 정도로 옅은 채움은 흰 글씨를 못 버틴다.
어시스턴트 말풍선은 호버 시 아래에 복사 pill이 페이드인한다(`.easeInOut(0.12)`). 위 행을 밀지 않도록 오버레이가 아니라 아래에 덧붙인다.

### 타임라인 엔트리별 표현

| 엔트리 | 표현 |
|---|---|
| 사용자/어시스턴트 메시지 | MessageBubble |
| 툴 호출 | `DisclosureGroup` + 렌치 아이콘, 인자는 mono, `card` 표면 |
| 툴 결과 | 성공/실패 원형 아이콘(`statusSuccess`/`statusError`) + mono 텍스트, `card` 표면 |
| 승인 요청 | `statusWarning` 색 라벨 |
| 완료 | seal / 경고 아이콘 + `summary` 폰트 |

승인 배너의 기본 액션은 **색이 아니라 굵기**로 표시한다(허용 = semibold, 거부 = `statusError` 색).

### 빈 상태

호박 마크 72×72 + 인사말 2줄. 그게 전부다. 프롬프트 추천 카드와 마크 뒤 글로우는 제거됐다.

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
