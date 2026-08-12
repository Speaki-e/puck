# Puck 디자인 시스템 (현재 구현 기준)

F13 클라이언트 창의 디자인이 확정된 상태를 **코드에 실제로 존재하는 값 그대로** 기록한 문서다.
새 디자인 제안이 아니라 현황 스냅샷이며, 값이 바뀌면 이 문서가 아니라 아래 소스가 먼저 바뀐다.

| 역할 | 파일 |
|---|---|
| 색 토큰 (3세트) | `Puck/ClientWindow/ClientPalette.swift` |
| 타입·간격·모양 토큰 | `Puck/ClientWindow/ClientTheme.swift` |
| 테마 선택/동기화 | `Puck/ClientWindow/ClientThemeStyle.swift` |
| 표면(글래스/플랫) 분기 | `Puck/ClientWindow/GlassSurface.swift` |
| 팔레트 주입 | `Puck/ClientWindow/ClientPaletteEnvironment.swift` |

원칙 하나: **뷰는 시스템 색/폰트를 직접 쓰지 않는다.** 전부 `ClientPalette`(색)와 `ClientTheme`(그 외)에서 나온다.

---

## 1. 테마 — light / dark / glass

`ClientThemeStyle`은 라이트/다크 축이 아니라 **독립적으로 아트디렉션된 3개의 무드**다("다크, 화이트, 글래스").

| 값 | 표시명 | colorScheme | 표면 |
|---|---|---|---|
| `.light` | 화이트 | light | 플랫 + 1px 보더 |
| `.dark` | 다크 | dark | 플랫 + 1px 보더 |
| `.glass` | 글래스 | dark (고정) | 실제 `glassEffect` |

- 글래스에 라이트 변형은 없다. 반투명은 어두운 바탕 위에서만 제대로 읽힌다.
- 기본값(파싱 실패 시 폴백)은 `.dark` — 이 앱이 원래 갖고 있던 룩.
- 저장 위치는 Puck 쪽 `SettingsStore`(`Puck.clientThemeStyle`). 채팅 창 안이 아니라 **메뉴막대 → Puck 설정 → "채팅 테마"** 에서 바꾼다.
- PuckClient는 별도 프로세스라 UserDefaults를 못 읽는다. `ClientThemeStyle.crossProcessChangeNotification`으로 브로드캐스트하되 **값을 notification userInfo에 실어 보낸다** — `UserDefaults.set()` 직후 다른 프로세스에서 읽으면 아직 옛 값일 수 있는 실제 레이스가 있었다.
- 앱 전체 외관(`AppAppearance`: system/light/dark, 펫 오버레이·노치·설정창)은 이것과 **별개 설정**이다.

## 2. 색 토큰

11개 필드로 고정. 팔레트마다 전부 채운다.

`background` `surface` `surfaceBorder` `textPrimary` `textSecondary` `accent` `onAccent` `success` `failure` `warning` `usesGlassSurfaces`

### light — Figma "Gray" 스케일 픽셀 매칭

| 토큰 | 값 |
|---|---|
| background / surface | `#FFFFFF` |
| surfaceBorder | `#EEE9F0` (Gray/+5) |
| textPrimary | `#332B36` (Gray/-3) |
| textSecondary | `#695E6E` (Gray/0) |
| accent | `rgb(0.80, 0.42, 0.12)` |

### dark — workspace(Electron 클라이언트 창)의 실제 팔레트와 픽셀 단위로 일치

workspace가 디자인 기준이 됐다(`docs/decisions.md` 2026-08-12). 아래 값은 workspace의
`src/renderer/styles.css` `--canvas`/`--surface`/`--hairline`/`--ink`/`--mute`/`--blue`를 그대로 옮긴 것이다.

| 토큰 | 값 |
|---|---|
| background | `#090909` (workspace `--canvas`) |
| surface | `#111111` (workspace `--surface`) |
| surfaceBorder | `#292929` (workspace `--hairline`) |
| textPrimary | `#ededed` (workspace `--ink`) |
| textSecondary | `#777777` (workspace `--mute`) |
| accent | `#3291ff` (workspace `--blue`) |

### glass

**아직 워크스페이스 전환 이전 값 그대로다** (2026-08-12 `.dark` 갱신 때 `.glass`는 건드리지 않음) —
background `#161616`, `surface`/`surfaceBorder`는 `white.opacity(0.06 / 0.12)`, 텍스트는 `white` /
`white.opacity(0.6)`, `usesGlassSurfaces = true`. 즉 지금은 `.dark`와 `.glass`의 background가
**서로 다르다**(`#090909` vs `#161616`) — 예전엔 같았지만 이 문서가 그 사실을 자동으로 보장해주진
않는다. `.glass`의 accent도 여전히 호박 주황(`rgb(0.93, 0.55, 0.20)`)이다.
단 `surface`/`surfaceBorder`는 **macOS 26 미만 폴백(`.regularMaterial`)의 틴트일 뿐**이고, macOS 26+에서는 무시되고 진짜 `glassEffect`가 그려진다.

### accent 사용 규칙

accent는 **의도적으로 유일하게 튀는 색**이다. 쓰는 곳은 다음뿐:

- 전송 버튼 (보낼 내용이 있을 때만 채워짐)
- 워크스페이스 아바타 원
- 활성 사이드바 행 / 팝오버 행 (`accent.opacity(0.14)`)
- 메시지 말풍선 배경 (`accent.opacity(0.06)`)
- 사용자 아바타 배경 (`accent.opacity(0.16)`)

`.dark`만 workspace의 파란 accent(`#3291ff`)로 바뀌었다. `.light`/`.glass`는 예전 값(호박 주황 계열)
그대로다 — 세 팔레트가 서로 다른 accent를 쓰는 상태이니 새로 손댈 때는 팔레트별로 확인할 것.

## 3. 타이포그래피

전부 `Font.system`, 기본 디자인. workspace가 Geist(그로테스크 산세리프)를 쓰지만 pet-app이 그 폰트
파일을 번들하지 않아서(2026-08-12), `design: .rounded`를 걷어내고 시스템 기본을 그 대체로 쓴다 —
SF Rounded의 "친근한 챗앱" 톤은 더 이상 없다. `mono`만 monospaced로 예외.

| 토큰 | 정의 | 용도 |
|---|---|---|
| `greeting` | largeTitle · bold | 빈 상태 인사말 |
| `greetingSubtitle` | body | 인사말 아래 한 줄 |
| `workspaceName` | body · medium | 워크스페이스명, 세션 선택 pill, 새 채팅 |
| `sessionTitle` | callout | 세션 행, 설정 행 라벨 |
| `toolLabel` | callout · medium | 툴 호출 라벨 |
| `summary` | callout · semibold | 완료 요약 |
| `messageBody` | body | 메시지 본문, 입력 필드 |
| `sectionHeader` | caption · semibold | 섹션 헤더, 배너 |
| `caption` | caption | 디스클레이머, 인라인 액션 |
| `senderLabel` | caption2 · semibold | "나" / 앱 이름 |
| `mono` | caption · monospaced | 툴 인자·결과, 승인 요약 |

전부 시스템 텍스트 스타일 기반이라 **동적 타입(사용자 글자 크기)을 따라간다.** 고정 pt 폰트는 아바타 글리프 두 곳(11pt, `Image(systemName:)`)뿐.

## 4. 간격·크기·모양

```
spacingSmall   6      bubbleCornerRadius  10
spacingMedium  10     cardCornerRadius    12
spacingLarge   16     rowCornerRadius      6
                      panel corner        12
sidebarWidthExpanded   220      contentMaxWidth   720
sidebarWidthCollapsed   68      bubbleMaxWidth    420
railButtonSize          36      avatarSize         22
windowMinWidth         960      windowMinHeight   640
```

- 사이드바 220/68은 Figma 레퍼런스 실측값(이 부분은 workspace 전환과 무관하게 유지).
- 코너 라운딩은 2026-08-12부로 workspace의 실제 radii(`src/renderer/styles.css`: 패널 12px, 버튼/행 6px)를 따른다 — 예전엔 Figma 레퍼런스의 24/24/12를 썼다.
- 모양은 전부 `style: .continuous`이고 `ClientTheme.Shapes`(`bubble`/`card`/`row`/`panel`)에 한 번만 선언한다 — 코너 스타일이 표면마다 어긋나면 창이 한 시스템으로 안 보인다.
- `bubbleMaxWidth`(420)가 `contentMaxWidth`(720)보다 훨씬 좁은 건 의도다. 창이 넓어도 한 줄이 길면 읽기 나빠진다.
- `windowMinWidth/Height`는 SwiftUI `.frame(minWidth:)`와 AppKit `NSWindow.minSize`가 **같은 상수 하나**를 읽는다. 기본 창 크기(`PuckClient/AppDelegate.swift`)도 1440x900으로 커졌다 — 에디터 패널이 열리면 사이드바+파일트리+Monaco+채팅이 폭을 다투기 때문.

## 5. 표면 — 글래스 대 플랫

호출부는 항상 `themedSurface(palette, in: shape)` 하나만 쓴다. 분기는 이 함수 안에서 끝난다.

```
themedSurface ─ usesGlassSurfaces ─ true  → glassSurface  ─ macOS 26+ → glassEffect(.regular)
                                                          └ 그 미만  → .regularMaterial
               └                    false → borderedSurface (surface 채움 + surfaceBorder 1px)
```

배포 타깃이 macOS 14인데 `glassEffect`는 26+라, `#available`을 호출부마다 흩뿌리지 않고 여기 한 곳에서만 게이트한다. 사이드바 배경만 예외로 `VisualEffectBackground(material: .sidebar)`(글래스) / `background.brightness(-0.02)`(플랫)를 직접 쓴다.

## 6. 레이아웃

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
| 툴 결과 | 성공/실패 원형 아이콘(`success`/`failure`) + mono 텍스트, `card` 표면 |
| 승인 요청 | `warning` 색 라벨 |
| 완료 | seal / 경고 아이콘 + `summary` 폰트 |

승인 배너의 기본 액션은 **색이 아니라 굵기**로 표시한다(허용 = semibold, 거부 = `failure` 색).

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

## 10. 이 문서에 없는 것

- 펫 오버레이(F1)·텍스트 입력 버블(F6)은 `ClientTheme` 토큰을 쓰지 않는 별개 표면이다.
- 에디터 뷰(`EditorWebView`)는 아직 어디에도 호스팅되지 않는다("에디터는 따로 할거라 토글 빼").
- 다크/글래스 팔레트의 `success`/`failure`/`warning`은 아직 시스템 색(`.green`/`.red`/`.orange`) 그대로다. 라이트 테마도 동일.
