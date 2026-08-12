# ai-module 구현 TODO

> **폐기 — 2026-08-12.** 아래 B3의 (가)/(나) 결정은 결국 팀 합의가 아니라 시간이 정했다: TS
> ai-module은 착수되지 않았고, pet-app의 Swift 임시 구현(F15)이 정식 두뇌가 됐다 -- 사실상 (나)에
> 가깝지만, "protocol 계약을 현실에 맞게 고친다"보다는 "workspace가 그 계약(ai-module 실행)을
> 아예 요구하지 않도록 걷어낸다"로 풀렸다. 아래 항목들은 더 이상 다음 할 일이 아니다. 배경은
> `../docs/decisions.md`.

기준 문서: `plan/04_ai-module.md` ai-module 저장소 기획서 (3조: 문정후 + 정가은), 저장소 내 `README.md`(동일 내용)
최종 갱신: 2026-08-05

## 표기

- [x] 구현 및 검증 완료
- [~] 진행 중 / 브랜치에는 있으나 main 미병합 또는 리뷰 전
- [ ] 미착수
- 담당: `문정후`, `정가은`, `공통`

## 지금 상태 요약 (착수 전 반드시 읽을 것)

- `main` 브랜치엔 여전히 `.gitignore`, `README.md`(기획서 사본)뿐이고 실제 구현 코드는 없다.
- 하지만 `feat/a0-streaming-client` 브랜치(문정후, 2026-08-05)에 **A0가 실제로 구현돼 있다** — `src/client.ts`, `src/cli.ts`, `src/types.ts`. 공식 `@anthropic-ai/sdk` 스트리밍, `AbortSignal` 전파, 에러 종류별 메시지 분기까지 스펙대로 잘 되어 있다. 다만 **아직 main에 병합 안 됨 + PR 리뷰 전 상태**다.
- 그러니 "코드 0줄"이라는 진단은 이제 정확하지 않다 — A0는 사실상 완료 직전이고, 리뷰·병합만 남았다. 아래 TODO는 이 실제 상태를 반영해서 정리했다.

---

## P0. 지금 먼저 정리해야 할 것

### 공통

- [ ] **팀 결정 필요 (B3)**: "계약(TS+Claude)"과 "현실(pet-app의 Swift+OpenAI 임시 구현)"이 갈라져 있다. 아래 중 하나를 팀(문정후·정가은·이주한·pet-app 담당)이 상의해서 정해야 다음 단계가 명확해진다.
  - **(가) ai-module을 계약대로 TS로 계속 진행** — 완성되면 pet-app의 Swift `AgentRunner`/`GPTClient`는 폐기하거나 "소켓 미연결 시 오프라인 폴백"으로 격하. protocol·기획서·workspace 배선이 전부 이 전제로 쓰여 있어 추가 문서 수정이 가장 적다. 대신 A1~A7을 새로 만들어야 한다.
  - **(나) Swift 루프를 정본으로 인정** — `protocol/src/types/agent-interface.ts`와 `plan/04_ai-module.md`를 현실에 맞게 고치고, 이 저장소는 스코프를 축소(프롬프트·케이스 표만 담당)하거나 접는다. 이미 동작하는 코드를 살리지만, workspace가 ai-module을 git 태그로 import하는 구조 자체가 깨져서 workspace 쪽 설계를 다시 그려야 한다.
  - 참고: 문정후가 이미 A0을 TS로 시작했다는 건 (가) 방향으로 움직이고 있다는 신호일 수 있다 — 결정할 때 이 사실을 감안할 것.
  - 방치하면 같은 역할의 두뇌가 두 벌로 계속 벌어지고, workspace의 승인·세션·도구 디스패치 배선은 계속 미완으로 남는다.

### 문정후

- [ ] `feat/a0-streaming-client` 브랜치의 실수 정리: `node_modules`가 통째로 커밋에 들어가 있다(`af4b77a`). `.gitignore`에 `node_modules`가 있는지 확인하고, 이미 커밋된 것은 `git rm -r --cached node_modules`로 빼서 다시 커밋할 것
- [ ] 위 정리 후 A0 브랜치 PR 올리기 (정가은 리뷰, 협업 규칙: 문정후↔정가은 상호 PR 리뷰)

---

## B4. 결정과 무관하게 지금 바로 해도 되는 것

### 문정후

- [ ] protocol 7절 로그 포맷(`src: agent`)을 에이전트 쪽에도 남기기 — 지금 pet-app/workspace만 로그를 쓰고 있어 통합 디버깅 때 가운데(에이전트)가 비어 있다. Swift 루프에 붙이더라도 몇 줄이면 되니, (나)를 고르더라도 손해 없음. TS A0/A1 쪽에 넣는다면 여기서 바로 시작 가능

### 정가은

- [ ] 승인 화이트리스트 규칙을 README 3.3 그대로 구현 (`data/whitelist.json`)
  - 접두 매칭 금지 — `ls`로 시작한다고 통과시키면 `ls; rm -rf ~`가 통과함
  - 규칙: ① 명령 전체에 셸 메타문자(`;`, `&&`, `|`, `>`, `` ` ``, `$(`) 있으면 무조건 승인 요구, ② 메타문자 없을 때만 첫 토큰을 화이트리스트(`ls`, `cat`, `pwd`, `echo`, `git status` 등)와 완전 일치 비교
  - `open`은 화이트리스트에서 제외 — 읽기성이 아니라 임의 실행이라서
  - 지금은 승인 게이트 자체가 없어서(A6 전) 전부 승인 요구 상태라 안전하지만, 나중에 급하게 넣다가 접두 매칭으로 구현하면 뚫린다 — 규칙 자체는 미리 문서/데이터로 정의해두면 A6에서 그대로 씀
- [ ] 케이스 표(`data/cases/*.json`) 착수 — 구현 언어(TS/Swift)와 무관하게 지금 시작해도 (가)/(나) 어느 쪽이 결정되든 그대로 쓰인다. README 3.6의 예시 형식("명령 문장 → 기대 도구 호출 시퀀스") 참고

---

## A0~A8 단계별 (plan/04_ai-module.md 2절 기준)

### 문정후

- [~] **A0** Claude API 스트리밍 클라이언트 (공식 TypeScript SDK) — `feat/a0-streaming-client` 브랜치에 구현됨(`src/client.ts`: `createClient`, `AbortSignal` 전파, 에러 종류별 분기 / `src/cli.ts`: `npx tsx src/cli.ts "질문"` 형태의 최소 CLI). **main 미병합, node_modules 정리 후 PR 리뷰 필요** (검증 포인트: 텍스트 응답 스트리밍 — cli.ts로 이미 수동 확인 가능한 상태로 보임)
- [ ] **A1** tool-use 멀티턴 루프 + 목(mock) 실행기 (검증: 가짜 도구 호출 왕복) — `types.ts`에 `ToolCallInfo`/`ToolResultInfo`와 `onToolCallStart`/`onToolResult` 콜백 타입은 A0 단계에서 이미 시그니처만 미리 선언해둠("A0에서는 호출되지 않음 -- 타입만 선언"이라는 주석 있음), 실제 구현은 A1에서. **README 3.2 반영 필수 사항 두 가지**: ① 병렬 tool_use — Claude가 한 턴에 tool_use 블록을 여러 개 낼 수 있고 API는 다음 메시지에 전 id의 tool_result를 요구하므로, 실행은 수신 순서대로 순차 처리하되 하나가 실패/거부돼도 나머지 id 전부에 tool_result를 만들어 응답할 것(하나라도 빠지면 API 에러) ② `run()`의 `AbortSignal`이 abort되면 스트리밍 중단 + 진행 중 executor 호출에 signal 전파(petAppProxy는 `tool_cancel` 송신) + `onDone(ok=false)`로 종료 — mock 실행기 설계 단계에서 취소 경로를 빠뜨리면 나중에 되짚기 번거로우니 A1에서 같이 넣을 것
- [ ] **(A1 범위, 별도 검증 필요)** `open_task_session` 루프 레벨 처리 (README 3.7, 2026-07-29 신규) — 레지스트리엔 있지만 executor 디스패치를 타지 않는 유일한 도구라 tool-use 루프가 직접 처리해야 함: 새 sessionId 발급 → 3.4 세션별 히스토리에 brief를 첫 시스템 메시지로 시드 → `onSessionCreated(sessionId, title)` 콜백 발생 → tool_result(ok=true)로 루프 계속, 이 턴 이후 대화는 새 sessionId 히스토리에 기록. 지금 TODO에 문정후 쪽 구현 항목이 전혀 없었음(정가은의 프롬프트 규칙 항목만 아래에 있었음) — A1 mock 실행기 목록에서 빠뜨리기 쉬우니 처음부터 케이스에 포함할 것. 호출자(workspace)가 `onSessionCreated`를 받아 `session_create(origin=agent)`로 pet-app에 통지하는 건 workspace 쪽 책임(이미 배선됨, 워크스페이스 TODO.md 참고)
- [ ] **A2** protocol 레지스트리 import + 실행기 주입 구조 (검증: executor별 디스패치) — 도구 스키마는 하드코딩 금지, `protocol` 패키지의 `/src/types/tools.ts`(컴파일된 `dist`를 import)에서 가져올 것. 레지스트리에 없는 도구 호출 시 tool_result(error=unknown_tool) 반환(protocol 3.1 표준 코드), executor 에러 코드+detail을 tool_result로 함께 모델에 전달(코드만 넘기면 모델이 "execution_failed" 외엔 아무 안내도 못함)도 이 단계 범위
- [ ] **A3** CLI 테스트 도구 (검증: 콘솔에서 명령→도구 시퀀스 확인) — A0의 `cli.ts`가 최소 뼈대이긴 하나, A3가 요구하는 "명령→도구 시퀀스 확인"은 A1/A2(도구 호출 자체)가 있어야 의미가 생기므로 사실상 A1/A2 이후에 완성. **완료 시 README에 CLI 사용법(목 실행기 실행, 케이스 회귀 돌리기) 반영 필수** — 협업 규칙 5절 요구사항인데 아직 README에 없음
- [ ] **A5** 컨텍스트 주입, 대화 히스토리 (검증: frontmostApp 언급 케이스 응답 확인, 2번째 명령이 1번째를 기억) — sessionId로 keyed된 멀티 세션 메모리(워크스페이스당 `default` 세션 1개 + 임의 개수 작업 세션), 로컬 저장은 후순위
- [ ] **A6** 승인 게이트 + 화이트리스트 (문정후/정가은 공동, 검증: 위험 도구 콜백 대기) — 정가은이 위에서 먼저 정의해둔 화이트리스트 규칙을 그대로 연결. 거부 시 tool_result(ok=false, "denied_by_user")로 모델에만 전달 — 소켓으로 내보내는 이벤트가 아니라 모델 전용 값(README 3.3)이니 pet-app의 승인 거부 이벤트와 헷갈리지 말 것
- [ ] **A7** workspace 통합 (실제 실행기 주입, 이주한 리뷰, 검증: M-B/M-1 마일스톤) — workspace 쪽은 이미 `petAppProxy`/`editorLocal` ToolExecutor와 `MockAgentRuntime`을 실제 계약대로 배선해두고 대기 중(워크스페이스 TODO.md 참고) — `MockAgentRuntime`을 실제 ai-module로 교체하는 지점. **완료 시 git 태그 발행 필수**(협업 규칙 5절: workspace 통합 마일스톤마다 태그 필수, 인터페이스 변경이면 minor 이상)

### 정가은

- [ ] **A4** 시스템 프롬프트·도구 description 1차 + 케이스 표 1차 (검증: CLI 회귀 통과) — 핵심 규칙: 코딩 작업은 반드시 code_editor 도구로 위임(직접 파일 조작 금지, read_file은 열람 전용), click_element는 시스템 권한 다이얼로그에 안 먹히니 그 경우 point_at 안내, 응답은 짧게 결과 중심
- [ ] **A6** 승인 게이트 + 화이트리스트 (문정후와 공동, 위 항목과 동일)
- [ ] **A8** 케이스 표 확장, 프롬프트 고도화 (검증: M-2 마일스톤)
- [ ] `open_task_session` 관련 프롬프트 규칙 추가 — "일상 세션에서 코딩/작업성 요청이 명확해지면 그 자리에서 작업 도구를 바로 쓰지 말고 먼저 `open_task_session`으로 새 세션을 연 뒤 진행" (README 3.7). 잡담을 오탐(작업으로 오분기)하거나 반대로 작업인데 누락(일상 세션에 눌러앉음)하는 케이스를 케이스 표에 양쪽 다 포함해 회귀 대상으로 관리

---

## 참고: 계약 대비 pet-app Swift 임시 구현 갭 (B2)

TS ai-module이 완성되면 자연히 해소되는 항목들이지만, (가)/(나) 결정과 우선순위 판단에 참고할 것. pet-app의 `AgentRunner.swift` + `GPTClient.swift`가 지금 이 저장소 대신 실제로 동작하고 있는데, 계약과 이렇게 갈라져 있다.

| 항목 | 계약 (protocol/agent-interface, README 3장) | 현실 (pet-app Swift) |
|---|---|---|
| 모델 | Claude API + 공식 TS SDK 스트리밍 | OpenAI Chat Completions, 비스트리밍, SDK 없음 |
| 세션 | sessionId별 히스토리 분리, 세션 간 메모리 격리 | 단일 messages 배열 + reset() |
| open_task_session | 일상 세션에서 작업 요청 감지 시 자동 분기 | 미구현 (pet-app 사이드바 자동 세션 생성도 안 됨) |
| 승인 화이트리스트 | 셸 메타문자 무조건 승인 + 첫 토큰 완전 일치, data/whitelist.json | 없음 — requiresApproval이면 무조건 물어봄 (안전한 실패라 급하진 않지만 UX 부담) |
| 중단 | AbortSignal로 스트리밍 중단 + 진행 중 executor에 tool_cancel 전파 | run()에 signal 없음, 시작한 run을 취소할 방법 없음 |
| 컨텍스트 주입 | frontmostApp/openWindows/editorOpenFiles/recentActions/projectPath를 system 프롬프트에 병합 | 없음 |
| workspace 도구 | code_editor/open_in_editor/read_file 노출 | 의도적으로 제외(실행기가 없어서 타당한 판단) — 다만 코딩 작업 자체가 불가라 M-2 차단 |
| 로그 | protocol 7절 JSON Lines 포맷을 src: agent로 전건 기록 | 없음 — 세 소스를 id로 join하는 분산 디버깅이 성립 안 함 |
| 회귀 테스트 | 케이스 표(data/cases/*.json) 기반 통과율 리포트, 프롬프트 PR 게이트 | 없음 |

**이미 스펙대로 충족하고 있는 것** (Swift 쪽): 병렬 tool_use를 순차 실행하되 전 id에 tool_result를 만들어 응답(`AgentRunner.perform` 루프), `maxTurns = 10` 상한, 에러 코드+detail을 모델에 그대로 전달, 승인 거부 시 `denied_by_user`를 소켓에 안 보내고 모델에만 전달 — 이 넷은 방향(가/나) 상관없이 그대로 재사용 가능한 설계다.

---

## 완료 기준

- M-B (워크스페이스에서 AI 코딩이 동작한다, 펫 없이 단독): A0~A7 + workspace의 `MockAgentRuntime` 교체
- M-1 ("Safari 켜줘" 전 구간): A0~A7 + pet-app 연동
- M-2 (code_editor로 실제 코딩 작업): A7~A8

## 담당별 다음 순서 제안

### 문정후
1. `feat/a0-streaming-client`의 `node_modules` 제거 후 PR 올리기
2. A1 (tool-use 루프 + mock 실행기, `open_task_session` 루프 분기 포함) 착수
3. A2 → A3 순서로 이어가기
4. B4의 로그 포맷 항목은 A1 작업하면서 같이 넣는 것을 권장 (도구 호출이 생겨야 로그 찍을 이벤트도 생김)

### 정가은
1. 화이트리스트 규칙(B4) 먼저 데이터로 정의 — 코드 없이도 지금 바로 가능
2. 케이스 표(A4 일부, B4) 착수 — 이것도 언어 무관하게 지금 가능
3. A4의 시스템 프롬프트 1차 작성은 A1/A2 진행 상황 보면서 병행

### 공통 (전원)
- B3 결정을 가장 먼저 — 이게 안 정해지면 A1 이후 작업 방향이 계속 흔들릴 수 있음
