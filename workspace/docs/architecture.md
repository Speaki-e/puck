# Workspace 기술 구성

## 프로세스 경계

```text
PuckClient / Fallback Electron
              │ HTTP + WebSocket / IPC
              ▼
Workspace Main
├─ app/workspace-application       composition root와 종료 처리
├─ app/pet-bridge-router           pet-app 메시지 라우팅
├─ app/agent-runtime-coordinator   AI 실행/세션 조정 경계
├─ WorkspaceRegistry / FileService
├─ EditorGateway / PetBridge
├─ SecretStore / SettingsStore
└─ AgentHostController
              │ MessagePort RPC
              ▼
Agent Host Utility Process
├─ CodeEditorQueue
├─ ACP permission bridge endpoint
└─ AcpAdapter
              │ ACP JSON-RPC
              ▼
Claude Agent ACP child process
```

Main은 Electron 생명주기, 파일시스템, 로컬 HTTP/WebSocket, PetBridge, 암호화 저장소를 소유합니다. Agent Host는 ACP 실행을 별도 Utility Process에 격리합니다. Agent Host가 비정상 종료되면 대기 RPC와 ActiveRun을 실패 처리하고 재시작하지만 FileService와 Editor View는 유지됩니다.

`src/main/index.ts`는 애플리케이션 시작과 치명적 오류 처리만 담당합니다. 실제 조립은 `src/main/app` 아래에 모아 도메인 모듈과 Electron 진입점을 분리했습니다.

## 현재 AI 실행 경계

기획서의 최종 구조에서는 ai-module, SessionRouter, RunRegistry가 Agent Host에 위치합니다. 현재는 v6 ai-module을 `packages/ai-module`에 포함해 실제 실행에 사용하되, 실행 경계는 Main의 `app/agent-runtime-coordinator.ts`에 유지합니다.

- 세션 직렬화와 ActiveRun 관리
- ai-module 승인 콜백과 ACP permission 연결
- PetBridge agent 이벤트 정규화
- Workspace별 `AiModuleRuntime`/Claude client 재사용으로 세션 히스토리 유지
- AsyncLocalStorage 기반 세션별 `editorLocal` 실행기 격리
- 테스트(`NODE_ENV=test`/`WORKSPACE_MOCK_AI=1`)에서만 `MockAgentRuntime` 사용

다음 구조 단계에서는 ai-module과 SessionRouter/RunRegistry를 Agent Host로 옮깁니다. 이때 bootstrap과 PetBridge 라우터는 유지하고 Agent Host↔Main 도구 실행 RPC를 추가합니다.

## 파일 흐름

파일을 열면 SHA-256 revision과 UTF-8 내용을 반환합니다. Renderer는 저장 시 받은 revision을 `expectedRevision`으로 전달합니다. 외부 도구나 ACP가 먼저 파일을 바꾸면 저장을 거부하고, 사용자는 디스크 내용 사용·내 내용 유지·side-by-side diff 중 하나를 선택합니다.

FileService는 요청 경로의 기존 부모까지 `realpath`로 확인합니다. `..`, 절대 경로, 디렉터리 심볼릭 링크를 이용한 프로젝트 밖 접근을 차단하며, 저장은 같은 디렉터리의 임시 파일을 교체하는 방식으로 수행합니다.

## Editor View

Renderer는 파일 상태와 비동기 작업을 `App.tsx`에서 조정하고, 표현 책임은 `components`로 분리합니다.

- `EditorSurface`: Monaco, 이미지 미리보기, 충돌 배너와 diff
- `WorkspaceTitlebar`: 프로젝트/설정/창 제어
- `CommandDock`: Agent 명령과 상태
- `FileTree`, `EditorTabs`, `SettingsPanel`: 독립 화면 영역
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
- Main에서 Mock 구현을 사용하는 임시 경계가 coordinator 밖으로 확산되지 않음
- `main/index.ts`와 `renderer/App.tsx`가 다시 거대 진입 파일이 되지 않음
