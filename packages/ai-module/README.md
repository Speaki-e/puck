# ai-module 저장소 기획서 (3조: 문정후 + 정가은)

- 산출물: 단일 에이전트 코어. UI 없는 TypeScript npm 모듈 + CLI 테스트 도구 + 프롬프트/케이스 표
- 의존 계약: protocol 저장소 (도구 레지스트리 타입 import, 모듈 인터페이스 준수)
- 소비자: workspace가 git 의존성 태그로 import
- 위상: 프로젝트의 두뇌. 모든 사용자 명령이 이 모듈의 tool-use 루프를 거친다


## 현재 v6 통합 상태 (2026-08-12)

- A0~A6: Claude 스트리밍, 멀티 tool-use, protocol 레지스트리 디스패치, CLI, 세션별 히스토리/컨텍스트, 승인 화이트리스트 구현
- `open_task_session`: ai-module 내부 세션 생성 + `onSessionCreated` 콜백 구현
- 이미지 attachment: 검증된 로컬 이미지를 Claude 멀티모달 입력으로 전달
- A7: Workspace의 `petAppProxy`/`editorLocal` 실행기와 실제 런타임 연결 완료
- 남은 검증: 실제 pet-app + Claude 인증 환경의 전체 E2E, protocol 로그 전건 기록, executor timeout, A8 케이스 확장

## 1. 담당

문정후: tool-use 루프, 스트리밍 클라이언트, 실행기 디스패치, 승인 게이트, 컨텍스트 주입, CLI
정가은: 시스템 프롬프트·전 도구 description 작성/튜닝, 케이스 표·회귀 테스트, 승인 화이트리스트 정의 (+landing 프론트 겸임)

통합 시점에 이주한(2조)이 리뷰어로 참여해 상급자 부재를 보완한다.

## 2. 구현 순서

A0 | Claude API 스트리밍 클라이언트 (공식 TypeScript SDK) | 문정후 | 텍스트 응답 스트리밍
A1 | tool-use 멀티턴 루프 + 목(mock) 실행기 | 문정후 | 가짜 도구 호출 왕복
A2 | protocol 레지스트리 import + 실행기 주입 구조 | 문정후 | executor별 디스패치
A3 | CLI 테스트 도구 | 문정후 | 콘솔에서 명령→도구 시퀀스 확인
A4 | 시스템 프롬프트·도구 description 1차 + 케이스 표 1차 | 정가은 | CLI 회귀 통과
A5 | 컨텍스트 주입, 대화 히스토리 | 문정후 | 컨텍스트 반영 응답 확인 (frontmostApp 언급 케이스), 2번째 명령이 1번째를 기억
A6 | 승인 게이트 + 화이트리스트 | 문정후/정가은 | 위험 도구 콜백 대기
A7 | workspace 통합 (실제 실행기 주입) | 문정후 (이주한 리뷰) | M-1 마일스톤
A8 | 케이스 표 확장, 프롬프트 고도화 | 정가은 | M-2 마일스톤

CLI 우선 원칙: A0~A6까지 UI 없이 터미널에서 개발·검증한다. 난이도 곡선을 완만하게 유지하고, workspace 없이도 개발이 막히지 않게 하는 장치.

## 3. 설계

### 3.1 모듈 인터페이스

protocol 저장소 5절이 규범. 요지:
- run(command, sessionId, context, callbacks, attachments?, signal?) 단일 진입점 (signal: AbortSignal — 사용자 중단 경로, sessionId: 2026-07-29 신규 — 세션별 히스토리 분리 키, attachments: 2026-07-29 신규 — 드래그 캡처 등 이미지 첨부)
- 콜백: onTextChunk, onToolCallStart(id 포함), onToolResult(id 포함), onApprovalRequired(resolve 콜백 포함), onSessionCreated(2026-07-29 신규 — 3.7절), onDone
- ToolExecutor 2종(petAppProxy, editorLocal)을 생성 시 주입 — 모듈은 소켓·파일시스템을 직접 만지지 않는다
- API 키·모델명도 주입 (모듈 내 저장 금지)

### 3.2 tool-use 루프 (문정후)

1. context를 system 프롬프트에 병합해 Claude API 호출 (스트리밍)
2. 텍스트 청크 → onTextChunk
3. tool_use 블록 수신 → onToolCallStart(id, tool, args) → open_task_session이면 3.7절로 분기(소켓 디스패치 없음), 그 외에는 승인 게이트 통과 확인 → 레지스트리에서 executor 조회 → 해당 ToolExecutor.execute
4. 결과 → onToolResult(id, ...) → tool_result 메시지로 루프 계속
5. 종료 → onDone(ok, summary)

병렬 tool_use: Claude는 한 턴에 tool_use 블록을 여러 개 낼 수 있고, API는 다음 메시지에 모든 tool_use id에 대한 tool_result를 요구한다. 실행은 순차(수신 순서대로)를 기본으로 하되, 하나가 실패/거부돼도 나머지 id 전부에 tool_result를 만들어 응답할 것 — 하나라도 빠지면 API 에러다. 콜백에 id가 있는 이유가 이것(protocol 5절)

도구 레지스트리는 protocol 패키지(/src/types/tools.ts가 소스, 소비 시엔 dist 컴파일 산출물을 import)에서 가져온다 (하드코딩 금지 — 레지스트리는 런타임 값이므로 .d.ts가 아닌 .ts다). 레지스트리에 없는 도구를 모델이 호출하면 tool_result(error=unknown_tool) 반환 (protocol 3.1 표준 코드)

도구 호출/결과 전건을 protocol 7절 로그 포맷(src: agent)으로 기록 — 분산 디버깅의 앵커

에러 처리: executor 에러 코드와 detail(protocol 3.1의 사람이 읽는 실패 상세)을 tool_result로 함께 모델에 전달 — 코드만 넘기면 모델이 "execution_failed" 외엔 아무것도 모른 채 안내해야 한다

중단: run()의 AbortSignal이 abort되면 스트리밍 중단, 진행 중 executor 호출은 execute에 전파된 signal로 취소(petAppProxy는 tool_cancel 송신), onDone(ok=false)로 종료

### 3.3 승인 게이트 (문정후 + 정가은)

레지스트리의 승인 필수 도구(run_shell, run_applescript, click_element)는 실행 전 onApprovalRequired(summary, resolve) 발생 후 resolve 대기

화이트리스트(정가은 정의, 저장소 내 data/whitelist.json): 매칭 시 자동 통과. 접두 매칭 금지 — ls로 시작한다고 통과시키면 ls; rm -rf ~가 통과한다. 규칙: ① 명령 전체를 셸 메타문자(;, &&, |, >, `, $() 포함 시 무조건 승인 요구, ② 메타문자가 없을 때만 첫 토큰을 화이트리스트(예: ls, cat, pwd, echo, git status)와 완전 일치 비교. open은 화이트리스트에서 제외 — 읽기성이 아니라 임의 실행이다

거부 시 tool_result(ok=false, "denied_by_user")로 모델에 전달 (소켓을 지나지 않는 모델 전용 값 — protocol 3.1 참고)

### 3.4 컨텍스트 주입 (문정후)

Context(frontmostApp, openWindows, editorOpenFiles, recentActions, projectPath)를 요약 문자열로 system 프롬프트에 포함. projectPath는 세션이 속한 워크스페이스의 project_path(2026-07-29 신규) — code_editor 호출 시 모델이 매번 지정하지 않아도 자동으로 실린다

대화 히스토리: sessionId로 keyed된 멀티 세션 메모리(2026-07-29 정정 — 이전엔 단일 세션 가정. 워크스페이스 하나당 default 세션 1개 + 임의 개수의 작업 세션이 각자 독립된 히스토리를 가진다, 01_protocol.md 3.4). 로컬 저장은 후순위

run() 실행 중 같은 sessionId로 새 user_input이 도착하면: 그 세션 안에서만 직렬 큐잉 — 진행 중 run 완료 후 순서대로 처리 (동시 실행·현재 run 취소 아님). 다른 sessionId의 run은 서로 막지 않는다(병렬 처리). 호출자(workspace/CLI)가 큐 상태를 UI에 표시

### 3.5 프롬프트/도구 설명 (정가은)

시스템 프롬프트 핵심 규칙:
1. 코딩 작업은 반드시 code_editor 도구로 위임, 직접 파일 조작 금지 (read_file은 열람 전용)
2. click_element는 시스템 권한 다이얼로그에 동작하지 않음 — 그 경우 point_at으로 사용자에게 직접 안내
3. 사용자 응답은 짧게, 수행 결과 중심으로
4. (2026-07-29 신규) 일상 세션에서 코딩/작업성 요청이 명확해지면 그 자리에서 작업 도구를 바로 쓰지 말고 먼저 open_task_session으로 새 세션을 연 뒤 그 세션에서 진행 (3.7절)

전 도구의 description 원문을 이 저장소 prompts/ 폴더에서 관리. 단, 도구 목록·파라미터·executor의 추가/변경은 protocol PR 선행이 원칙

튜닝 방법: 케이스 표 기준 회귀 테스트를 돌려 프롬프트 변경의 효과를 정량 확인

### 3.6 케이스 표 + 회귀 테스트 (정가은)

형식: "명령 문장 → 기대 도구 호출 시퀀스(도구명·핵심 인자)" 표 (data/cases/*.json)

예시:
- "사파리 켜줘" → launch_app(app_name~Safari)
- "이 프로젝트 테스트 돌려줘" → code_editor(task~테스트 실행)
- "설정에서 카메라 권한 어디서 켜는지 알려줘" → launch_app(시스템 설정) → find_ui_element → point_at
- "빌드 폴더 지워줘" → run_shell(rm ...) — 승인 요청 발생해야 함
- (일상 세션에서) "아 근데 로그인 버튼 눌러도 반응이 없는 버그 좀 고쳐줘" → open_task_session(title~로그인 버튼 버그 수정) → (새 세션에서) code_editor(task~버그 수정)
- (일상 세션에서) "오늘 날씨 어때" → 도구 호출 없음 — open_task_session으로 분기하면 안 됨(오탐 회귀 대상)

테스트 스크립트: 목 실행기로 CLI 실행 → 실제 호출 시퀀스와 기대 시퀀스 비교 → 통과율 리포트

프롬프트/모델 변경 PR에는 회귀 결과 첨부 필수

### 3.7 작업 세션 자동 분기 — open_task_session (문정후 + 정가은, 2026-07-29 신규)

pet-app이 "일상 대화 세션이 디폴트, 작업은 별도 세션"으로 UI를 나누게 됨(02_pet-app.md F13)에 따라, 에이전트가 일상 세션 중 명확한 작업 요청을 감지하면 스스로 새 세션을 열고 그쪽에서 이어가야 한다.

open_task_session(title, brief)은 레지스트리엔 있지만(01_protocol.md 4절) executor 디스패치를 타지 않는 유일한 도구 — tool-use 루프(3.2)가 직접 처리한다: 새 sessionId를 발급 → 3.4의 세션별 히스토리 레지스트리에 빈 항목 생성(brief를 첫 시스템 메시지로 시드) → onSessionCreated(sessionId, title) 콜백 발생 → tool_result(ok=true)로 루프 계속하되, 이 turn 이후의 대화는 새 sessionId 쪽 히스토리에 기록된다

호출자(workspace)는 onSessionCreated를 받아 session_create(origin=agent) 소켓 이벤트로 pet-app에 통지(03_workspace.md 4.5/4.6) — pet-app 사이드바에 새 세션이 자동으로 나타나고 대화 뷰가 그쪽으로 전환된다

시스템 프롬프트 규칙(3.5에 추가): "일상 세션에서 코딩/작업성 요청이 명확해지면 그 자리에서 code_editor 등 작업 도구를 바로 쓰지 말고 먼저 open_task_session으로 새 세션을 연 뒤 그 세션에서 진행하라" — 일상 세션 히스토리가 작업 로그로 오염되는 걸 막는다

애매한 경우(잡담인지 작업인지 불분명) 판단 기준은 케이스 표(3.6)로 회귀 테스트 — 정가은이 프롬프트 튜닝 시 오탐(잡담을 세션 분기)/누락(작업인데 안 분기) 둘 다 회귀 대상으로 관리

## 4. 스택

형태: TypeScript npm 모듈 (UI 없음) — CLI 동봉
AI: 공식 Anthropic TypeScript SDK (@anthropic-ai/sdk) 스트리밍 — 자체 fetch+SSE 파서 금지. tool 인자 델타(input_json_delta) 누적·재시도·stop_reason 처리를 SDK가 다 해준다. 자작은 이 팀의 "usdz 첫 애니메이션" 함정이다. CLI는 ANTHROPIC_API_KEY env로 키 주입
도구 스키마: protocol /types import — 하드코딩 금지
테스트: 케이스 표 기반 회귀 스크립트 — 목 실행기
배포: git 태그 (workspace가 태그 참조) — 개발 중 npm link

## 5. 협업 규칙 (저장소 로컬)

- 문정후↔정가은 상호 PR 리뷰 (프롬프트 PR도 코드와 동일하게 PR로)
- 태그 규칙: 인터페이스 변경 시 minor 이상, workspace 통합 마일스톤마다 태그 필수
- README에 CLI 사용법 (목 실행기 실행, 케이스 회귀 돌리기) 필수

## 6. CLI 사용법 (A5 구현 기준)

공통: `ANTHROPIC_API_KEY` 필수(없으면 종료 코드 1), `ANTHROPIC_MODEL` 선택(기본 `claude-sonnet-4-6`). `npm run cli`은 `tsx --env-file=.env`로 실행되므로 저장소 루트의 `.env`를 읽는다. 실행기는 목(mock) 고정. 시스템 프롬프트 원문은 `prompts/system.md`이며, 없으면 시작 시 에러로 종료한다.

### 모드 1 — 단발 실행

```
npm run cli "사파리 켜줘"
```

응답 텍스트 스트리밍 + `[tool_call]` / `[dispatch]` / `[tool_result]` / `[done]` 로그를 stdout에 출력. 세션은 `default` 고정. 종료 코드는 run 성공 시 0, 실패 시 1.

### 모드 2 — 대화형 REPL

```
npm run cli
```

프롬프트는 `ai-module[<세션 id>]> `. 특수 명령:

- `/tools` — protocol `TOOL_REGISTRY`를 표로 출력 (API 호출 없음)
- `/session` — 현재 세션 표시 / `/session <id>` — 세션 전환(없는 id면 새 대화 시작)
- `/ctx` — 현재 컨텍스트 표시 / `/ctx k=v ...` — 설정 / `/ctx clear` — 초기화
  - 설정 가능: `frontmostApp`, `projectPath`, `editorOpenFiles`(쉼표 구분), `recentActions`(쉼표 구분).
    `openWindows`는 `WindowInfo` 객체 배열이라 key=value로 표현할 수 없어 제외.
- `/help`, `/exit`

같은 세션에서는 **이전 대화를 기억한다.** 세션이 다르면 히스토리는 완전히 분리된다. 모델이 `open_task_session`을 호출하면 `[새 세션 생성: <id> (<title>)]`을 출력하고 현재 세션을 그쪽으로 자동 전환한다(pet-app 사이드바 전환 시뮬레이션).

실행 중 Ctrl+C는 그 run만 중단하고(`[done ok=false aborted]`) 프롬프트로 돌아온다. 프롬프트 상태에서 Ctrl+C는 종료. 종료 코드는 항상 0.

### 모드 3 — 시퀀스 출력 (A4 회귀 테스트 기반)

```
npm run cli --seq "사파리 켜줘"
npm run cli --seq --session=t1 "사파리 켜줘"
npm run cli --seq --approve=all "빌드 폴더 지워줘"
```

`--approve`는 대화형 입력이 불가능한 `--seq`에서 승인 요청을 어떻게 처리할지 정한다. `all`이면 전부 허용, 그 외 값과 미지정은 전부 거부(`none`)다 — 회귀 테스트가 위험한 명령을 실수로 통과시키지 않도록 기본값이 거부다.

**stdout에는 JSON 한 줄만** 나간다(파이프 전용). 사람이 읽는 로그는 stderr로 분리된다.

```json
{"command":"사파리 켜줘","session":"t1","sequence":[{"tool":"launch_app","args":{"app_name":"Safari"}}],"ok":true,"stopReason":"end_turn"}
```

| 필드 | 타입 | 의미 |
| --- | --- | --- |
| `command` | string | 입력한 명령 원문 |
| `session` | string | 실행한 세션 id (`--session=<id>`, 기본 `default`) |
| `sequence` | `{tool: string, args: unknown}[]` | 호출된 도구를 호출 순서대로. 없으면 `[]`. 인자 검증 실패로 실행되지 않은 호출도 포함 |
| `ok` | boolean | 루프가 `end_turn`으로 끝났는지. 개별 도구 실패는 반영되지 않음 |
| `stopReason` | string | 성공 시 `stop_reason`, 실패 시 요약(`aborted`, `max_turns_exceeded`, `api error (...)` 등) |
| `approvals` | `{tool, summary, approved}[]` | 발생한 승인 요청 전건. 없으면 `[]`(필드는 항상 존재) |
| `createdSession` | `{id, title}` (선택) | `open_task_session`이 발생했을 때만 존재 |

종료 코드는 **항상 0**(실패도 JSON으로 보고). API 키 누락·명령 미지정처럼 실행 자체가 불가능한 경우만 1이며 그때는 stdout에 아무것도 쓰지 않는다.

npm 플래그 주의: npm이 `--seq` / `--session=` 을 자기 config로 삼켜 스크립트에 전달하지 않는다(대신 `npm_config_seq` / `npm_config_session`). CLI가 두 경로를 모두 인식하므로 위 형태와 `npm run cli -- --seq "명령"`, `npx tsx --env-file=.env src/cli.ts --seq "명령"`이 모두 같게 동작한다.

### 승인 게이트 (A6)

위험한 도구는 실행기를 호출하기 **전에** 사용자 승인을 받는다. 거부하면 실행기를 아예 호출하지 않고 모델에게 `tool_result(ok=false, error="denied_by_user")`를 돌려준다 — `denied_by_user`는 소켓을 지나지 않는 모델 전용 값이므로, 여기서 막지 못하면 위험한 명령이 이미 pet-app으로 나간 뒤가 된다.

판정 기준은 protocol 레지스트리의 `approval.kind`다:

| kind | 대상 도구 | 동작 |
| --- | --- | --- |
| `not_required` | launch_app, read_file, point_at, open_task_session 등 | 그냥 실행 |
| `required` | click_element, run_applescript | 항상 승인 요구 |
| `required_with_whitelist` | run_shell | 아래 규칙 |
| `acp_internal` | code_editor | 통과 (Claude Code의 자체 승인 흐름이 처리) |

**run_shell 화이트리스트 (`data/whitelist.json`)**

1. **셸 메타문자가 하나라도 있으면 화이트리스트와 무관하게 무조건 승인을 요구한다.** 대상: ``; & | < > $ ` ( ) [ ] { } * ? ! # \`` 와 개행/캐리지리턴. `ls; rm -rf ~`처럼 허용 명령으로 시작해 다른 명령을 이어 붙이는 경로를 전부 막기 위한 것이다(접두 매칭 금지).
2. 메타문자가 없을 때만 토큰 **완전 일치**를 본다.
   - `first_token_commands` — 첫 토큰이 일치하면 통과(뒤 인자는 자유). `ls`, `cat`, `pwd`, `echo`, `which`, `head`, `tail`, `wc`, `date`, `whoami`
   - `two_token_commands` — 앞 **두** 토큰이 일치해야 통과. `git status`, `git log`, `git diff`, `git branch`, `git show`. `git` 단독은 통과하지 않으므로 `git push` / `git reset --hard`는 승인을 받는다.
   - `open`은 읽기성이 아니라 임의 실행이므로 **절대 넣지 않는다**(기획서 3.3).
3. 파일이 없거나 깨졌으면 빈 화이트리스트로 물러선다 — 모든 셸 명령이 승인 대상이 되고, 이유는 stderr에 남는다.

**승인 UI**

- 단발/REPL: `⚠️ 승인 필요: <요약>` 뒤에 `허용하시겠습니까? [y/N]: `. `y`/`yes`만 허용이고 **엔터·그 외 입력·입력 종료(EOF)·Ctrl+C는 전부 거부**다.
- `--seq`: `--approve=all|none`(기본 none)으로 정하고, 결정을 `approvals` 배열에 기록한다.
- 승인 콜백(`onApprovalRequired`)을 붙이지 않은 호출부에서는 승인이 필요한 도구가 전부 거부된다 — 물어볼 수 없는데 실행하면 게이트가 없는 것과 같다.

### 세션과 히스토리 (A5)

- 히스토리는 클라이언트 인스턴스의 메모리에만 있다. 프로세스가 끝나면 사라진다(로컬 저장은 후순위).
- **정상 종료(`end_turn`)한 턴만** 히스토리에 커밋된다. 중단·에러·`max_turns_exceeded`로 끝난 턴은 통째로 버린다 — `tool_result` 없는 `tool_use`가 남으면 다음 API 호출이 거부되기 때문이다.
- 같은 sessionId로 run이 겹치면 그 세션 안에서만 직렬 큐잉되고 stderr에 `[queued session=<id> waiting=<n>]`이 찍힌다. 다른 세션끼리는 병렬로 돈다.

## 7. 리스크

- 상급자 부재 → CLI 우선의 완만한 난이도 곡선 + 통합 시 이주한 리뷰
- 에이전트→Claude Code 이중 위임 혼선 → 시스템 프롬프트 규칙 1 + read_file 열람 전용 한정
- click_element 오남용 → 승인 게이트 + 도구 설명 제약 이중 방어 (pet-app 실행기의 대상 검증과 삼중)
- 도구 디스패치 분산 디버깅 → protocol 로그 포맷 전건 기록, id로 3소스 join
- 프롬프트 회귀 (수정하다 기존 케이스 깨짐) → 케이스 표 회귀 테스트를 PR 게이트로
- open_task_session 오탐/누락 (2026-07-29 신규 리스크) — 잡담을 작업으로 오분기하거나, 반대로 작업인데 일상 세션에 눌러앉음 → 3.6 케이스 표에 오탐/누락 양쪽 케이스를 명시적으로 포함해 회귀 대상으로 관리
