# Workspace 기술 구성

## 프로세스 경계

```text
PuckClient / Fallback Electron
              │ HTTP + WebSocket / IPC
              ▼
Workspace Main
├─ app/workspace-application       composition root와 종료 처리
├─ app/pet-bridge-router           pet-app 메시지 라우팅
├─ app/agent-runtime-coordinator   Agent Host <-> petBridge 이벤트 릴레이 + 도구 실행 RPC 처리
├─ WorkspaceRegistry / FileService
├─ EditorGateway / PetBridge
├─ SecretStore / SettingsStore
└─ AgentHostController
              │ MessagePort RPC (양방향: runAgent/cancelAgentSession/respondToApproval ↓,
              │                          agent_*/tool_execute_request ↑)
              ▼
Agent Host Utility Process
├─ agent-runner (SessionRouter, RunRegistry, PendingApprovalStore, DirectCodeEditorRuntime)
├─ CodeEditorQueue
└─ AcpAdapter
              │ ACP JSON-RPC
              ▼
Claude Agent ACP child process
```

Main은 Electron 생명주기, 파일시스템, 로컬 HTTP/WebSocket, PetBridge, 암호화 저장소를 소유합니다. Agent Host는 ACP 실행을 별도 Utility Process에 격리합니다. Agent Host가 비정상 종료되면 재시작하고, Main은 진행 중이던 `runAgent` 호출이 없으면 조용히, 있으면(내부 in-flight 추적) 해당 세션에 `agent_done(ok=false)`를 보내 정리합니다. FileService와 Editor View는 Main에 남아 있으므로 영향받지 않습니다.

`src/main/index.ts`는 애플리케이션 시작과 치명적 오류 처리만 담당합니다. 실제 조립은 `src/main/app` 아래에 모아 도메인 모듈과 Electron 진입점을 분리했습니다.

## AI 실행 경계

Workspace는 더 이상 "이게 무슨 작업인지" 판단하지 않습니다 -- pet-app이 판단을 전담합니다(전체 배경은 `docs/decisions.md` "workspace becomes a plain editor" 참고). pet-app의 에이전트(F15)가 이미 코딩 작업이라고 분류해 지시문을 작성한 뒤 `user_input`으로 보내면, Workspace는 그 텍스트 전체를 `code_editor` 도구 호출 하나로 곧장 실행합니다 -- 이 판단·위임을 `DirectCodeEditorRuntime`(`src/agent-host/direct-code-editor-runtime.ts`)이 맡고, `AiModuleRuntime`/`MockAgentRuntime`과 그 전제였던 pet-app 도구 프록시(petAppProxy)는 제거되었습니다.

- 세션 직렬화(SessionRouter)와 ActiveRun 관리(RunRegistry)는 여전히 Agent Host 프로세스 안에 있습니다 -- 실행기가 하나로 줄었어도 동시 실행 취소/정리 책임은 그대로 필요합니다.
- ACP의 `request_permission`은 `PendingApprovalStore`를 거쳐 `agent_approval_request`/`respondToApproval` 왕복으로 나갑니다. `DirectCodeEditorRuntime`은 `onApprovalRequired`를 항상 거부로 응답하므로(코딩 작업 자체는 pet-app이 이미 승인한 것으로 간주) 이 경로로는 더 이상 승인 요청이 발생하지 않습니다.
- editorLocal(code_editor/open_in_editor/read_file)은 Main에만 있는 petBridge/FileService/EditorGateway가 필요하므로, Agent Host는 `tool_execute_request` 이벤트로 실행을 위임하고 Main은 `toolExecuteResponse`로 결과를 돌려줍니다. `code_editor` 자체는 Agent Host 안에서 바로 처리되던 `runCodeEditor` RPC를 그대로 한 번 더 타므로(Main을 거쳐 되돌아옴) 약간의 왕복 비용이 있지만, 이 도구는 원래도 수 초~수 분 걸리는 작업이라 무시할 만합니다.
- Claude API 키는 ACP(Claude Code CLI)의 인증에만 쓰이며, 없으면 ACP가 자기 로그인 인증으로 대체합니다. 모델 선택이나 실행 중 API 키 교체를 위한 `runtime_config_request` 왕복은(ai-module 전용이었으므로) 제거되었습니다.
- AsyncLocalStorage 기반 세션별 `editorLocal` 실행기 격리는 그대로입니다.

## 파일 흐름

파일을 열면 SHA-256 revision과 UTF-8 내용을 반환합니다. Renderer는 저장 시 받은 revision을 `expectedRevision`으로 전달합니다. 외부 도구나 ACP가 먼저 파일을 바꾸면 저장을 거부하고, 사용자는 디스크 내용 사용·내 내용 유지·side-by-side diff 중 하나를 선택합니다.

FileService는 요청 경로의 기존 부모까지 `realpath`로 확인합니다. `..`, 절대 경로, 디렉터리 심볼릭 링크를 이용한 프로젝트 밖 접근을 차단하며, 저장은 같은 디렉터리의 임시 파일을 교체하는 방식으로 수행합니다.

## Editor View

Renderer는 파일 상태와 비동기 작업을 `App.tsx`에서 조정하고, 표현 책임은 `components`로 분리합니다.

- `EditorSurface`: Monaco, 이미지 미리보기, 충돌 배너와 diff
- `WorkspaceTitlebar`: 프로젝트/설정/창 제어
- `FileTree`, `EditorTabs`, `SettingsPanel`: 독립 화면 영역

workspace는 "무엇을 할지" 판단하지 않으므로(위 "AI 실행 경계" 참고) 에이전트 명령을 직접 받는 UI가
없습니다 -- 하단은 저장/재연결/에러 같은 짧은 상태 텍스트만 보여주는 얇은 status bar 하나뿐입니다.
- `monaco-config.ts`: 공통 테마와 폰트 설정

Electron 폴백 창은 preload IPC를 사용하고, WKWebView는 `gateway-transport.ts`를 사용하지만 둘 다 같은 `WorkspaceApi` 인터페이스와 Editor View 번들을 소비합니다.

## ACP 실행과 큐

`CodeEditorQueue`는 워크스페이스 ID마다 별도 큐를 유지합니다. 동일 프로젝트의 쓰기 작업은 하나씩 실행하고 다른 프로젝트는 병렬 실행합니다. 대기 중 취소된 항목은 ACP로 전달하지 않으며 실행 중 취소는 `session/cancel` 후 응답이 없으면 프로세스를 종료합니다.

`AcpAdapter`는 공식 SDK의 NDJSON stream을 사용합니다. 세션 업데이트를 Agent Host 이벤트로 정규화하고, 파일 워처와 실행 전후 snapshot을 결합해 변경 파일을 수집하며, 실패 시 ACP stderr의 마지막 8KB만 detail에 포함합니다.

현재 ACP 격리는 작업별 프로세스와 cwd 지정입니다. 절대경로를 통한 워크스페이스 외부 쓰기를 OS 수준에서 차단하지 못하므로 별도 샌드박싱이 필요합니다.

## PetBridge와 EditorGateway

PetBridge는 연결 후 `client_hello(role="workspace")`를 전송하고 JSON Lines 분할/병합, timeout, 취소, 연결 종료 정리, 지수 backoff 재연결을 처리합니다. `app/pet-bridge-router.ts`는 메시지 해석과 application 명령 호출만 담당합니다.

EditorGateway는 프로세스당 하나만 실행되며 workspace ID, token, Origin을 검증합니다. 파일 변경, ACP 업데이트, 작업 경로, Editor View 상태를 워크스페이스별 WebSocket 연결에 브로드캐스트합니다.

## 구조 검증

`scripts/check-architecture.mjs`는 다음을 CI에서 검사합니다.

- 내부 import cycle 부재
- shared/renderer/agent-host 계층 역참조 금지
- `main/index.ts`와 `renderer/App.tsx`가 다시 거대 진입 파일이 되지 않음
