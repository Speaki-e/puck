# 저장소 간 protocol 버전 호환 매트릭스

TODO.md W0/공통 "저장소 간 protocol 버전 호환 매트릭스 작성" 항목의 산출물이다. 코드 변경은 없다.
이 저장소(workspace)가 쓰는 `@speaki-e/protocol` 버전과, 그 protocol을 실제로 공유하는 다른
저장소(pet-app, ai-module)가 지금 어떤 버전을 기대/반영하고 있는지 로컬에 체크아웃된 세 저장소
(`../protocol`, `../pet-app`, `../ai-module`)를 직접 열어 확인한 결과다.

## 요약

| 저장소 | protocol 소비 방식 | 현재 상태 | 비고 |
|---|---|---|---|
| `protocol` (원본) | -- (소스) | `v0.5.0`, HEAD `4244922` | 세 저장소의 스키마 원본 |
| `workspace` (이 저장소) | npm 의존성, 커밋 고정 | HEAD `4244922`와 **완전히 동일한 커밋에 고정** | `package.json`의 `github:` 참조가 protocol repo의 현재 HEAD와 정확히 일치 |
| `pet-app` | Swift 파일 4개 수동 복사(vendoring) | 현재 protocol `swift/`와 **내용상 동일**(주석/헤더만 다름) | 패키지 매니저 의존성이 아니라 사람이 복사 -- 자동 드리프트 감지 없음 |
| `ai-module` | 확인 불가 | 코드 없음(커밋 1개, `.gitignore`만) | 아래 "ai-module" 절 참고 |

## `protocol` (원본 저장소)

- `package.json`의 `version`: **`0.5.0`**.
- 최신 커밋(`main` HEAD): `4244922 feat: mirror the tool registry to Swift consumers` (2026-07-31).
- TypeScript로 스키마를 정의(`src/`)하고 `dist/`로 빌드해 npm(`@speaki-e/protocol`)으로 배포, Swift
  소비자를 위해 `swift/`에 손으로 유지보수하는 Swift 미러(`BridgeMessages.swift`, `JSONValue.swift`,
  `ToolRegistry.swift`, `ToolTimeouts.swift`)를 함께 둔다.
- 버전 히스토리(커밋 로그 기준): `0.2.0`(avatar manifest) → `0.3.0`(sessions/workspaces/editor-view
  /approval-bridge 스키마) → `0.4.0`(`text_chunk` 이벤트, tool_call/tool_result 보강) → `0.5.0`
  (`client_hello` role 핸드셰이크).

## `workspace` (이 저장소)

- `package.json`: `"@speaki-e/protocol": "github:Speaki-e/protocol#4244922fa4605645e577905ed37b33b94a5b16e5"`.
- 이 커밋 해시는 protocol 저장소의 **현재 `main` HEAD와 정확히 같다** -- 즉 지금 이 순간 기준으로는
  드리프트가 전혀 없다.
- 다만 이건 "커밋을 고정"한 것이지 "자동으로 최신을 따라간다"는 뜻이 아니다 -- protocol 저장소가
  다음 커밋을 만들면 workspace는 그 시점부터 뒤처진 채로 남는다(사람이 `pnpm update` 등으로 pin을
  올려야 한다). TODO.md의 W0 P0 항목("protocol PR: `state_snapshot`, `request_id`, 확장
  `run_cancel(run_id)` 계약 확정")이 아직 협의 중이라, 지금 pin을 올리지 않고 있는 것 자체는
  의도된 상태다.
- `isBridgeMessage`(`node_modules/@speaki-e/protocol/dist/validate.js`)로 실제 wire 메시지를
  런타임 검증하고 있어(`pet-bridge.ts`), 타입 정의와 런타임 검증이 항상 같은 커밋에서 나온다 --
  버전 불일치로 인한 "컴파일은 되는데 실제로는 다른 스키마" 문제가 구조적으로 생기기 어렵다.

## `pet-app`

pet-app은 Swift 프로젝트라 npm 패키지를 직접 의존할 수 없다. 대신 protocol 저장소의 `swift/`
디렉터리에 있는 파일 4개를 **그대로 복사**해 자기 소스 트리에 둔다(각 파일 헤더 주석에 "protocol
repo의 이 파일을 미러링한다"고 명시돼 있다):

| protocol repo | pet-app 복사본 |
|---|---|
| `swift/BridgeMessages.swift` | `Shaydi/Bridge/BridgeMessages.swift` |
| `swift/JSONValue.swift` | `Shaydi/Bridge/JSONValue.swift` |
| `swift/ToolRegistry.swift` | `Shaydi/Tools/ToolRegistry.swift` |
| `swift/ToolTimeouts.swift` | `Shaydi/Tools/ToolTimeouts.swift` |

네 파일을 `diff`로 직접 비교한 결과, **스키마/로직에는 차이가 없다** -- 다른 부분은 전부 파일 헤더
주석(프로젝트명이 protocol repo 기준 "protocol"인지 pet-app 기준 "Shaydi"인지, 작성자 표기, 2026-08-01
"PetAgent → Shaydi" 이름 변경 반영)뿐이다. 즉 지금 이 순간 pet-app의 Swift 쪽 protocol 이해는
workspace가 참조하는 것과 **같은 스키마(0.5.0, 커밋 `4244922`)**를 가리키고 있다.

**주의할 점:** 이건 npm의 lockfile 같은 강제 장치가 아니라 사람이 복사해서 유지하는 방식이다.
protocol 저장소가 `swift/` 아래 파일을 다시 바꾸면, pet-app이 그 변경을 다시 복사해오기 전까지는
드리프트가 생긴다 -- 지금은 우연히 최신이지만, 이 매트릭스가 그 사실을 자동으로 보장해주지는
않는다(재확인 방법: 이 문서의 diff 절차를 다시 실행).

## `ai-module`

**확인 불가.** 2026-08-04 기준 저장소에 커밋이 하나(`chore: add .gitignore`)뿐이고 소스 코드가
전혀 없다 -- protocol을 어떤 방식으로 소비할지(npm 의존성인지, 별도 언어라 Python/기타 미러를 두는
지), 어떤 버전을 기대하는지 확인할 대상 자체가 없다.

**코드가 생기면 다시 확인해야 할 것:**

1. `package.json`(또는 해당 언어의 의존성 매니페스트)이 `@speaki-e/protocol`을 어떤 버전/커밋으로
   고정하는지 -- workspace의 pin(`4244922...`)과 같은지, 뒤처졌는지.
2. ai-module이 실제로 협의 대기 중인 확장 계약(`state_snapshot`, `request_id`, 확장
   `run_cancel(run_id)`, `docs/session-workspace-metadata-review.md`에서 언급한 W4 공통 항목들)을
   전제로 설계돼 있는지 -- 아직 protocol PR이 안 올라간 상태이므로, ai-module 쪽 설계가 그 확장을
   먼저 가정하고 있다면 workspace/protocol과 순서를 맞춰야 한다.
3. `TOOL_REGISTRY`/`ToolTimeouts`(도구 이름, timeout, 인자 스키마)를 ai-module의 tool-use 루프가
   그대로 참조하는지, 아니면 자체 사본을 두는지 -- 자체 사본이면 pet-app과 같은 수동 동기화 문제가
   생긴다.
4. `src/main/app/agent-runtime-coordinator.ts`의 `MockAgentRuntime`이 대체하고 있는 실제 `AgentRuntime`/`ApprovalPort` 포트
   계약(`shared/ports.ts`)과 ai-module의 실제 인터페이스가 일치하는지(W6 공통 "ai-module 인터페이스가
   현재 protocol 버전과 일치하는지 리뷰"의 실행판).

## 재확인 방법 (다음에 이 문서를 갱신할 때)

```sh
# protocol 저장소의 현재 버전/커밋
cd ../protocol && git log -1 --format="%h %s" && node -p "require('./package.json').version"

# workspace가 고정한 커밋과 비교
grep '"@speaki-e/protocol"' ../workspace/package.json

# pet-app 벤더 사본과 diff
diff ../protocol/swift/BridgeMessages.swift ../pet-app/Shaydi/Bridge/BridgeMessages.swift
diff ../protocol/swift/JSONValue.swift ../pet-app/Shaydi/Bridge/JSONValue.swift
diff ../protocol/swift/ToolRegistry.swift ../pet-app/Shaydi/Tools/ToolRegistry.swift
diff ../protocol/swift/ToolTimeouts.swift ../pet-app/Shaydi/Tools/ToolTimeouts.swift

# ai-module에 코드가 생겼는지
ls ../ai-module
```
