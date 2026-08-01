# Workspace 기술 구성

## 프로세스

```text
Fallback Electron / PetAgentClient
              │
        Workspace Main
        ├─ WorkspaceRegistry
        ├─ FileService
        ├─ PetBridge
        ├─ SecretStore
        └─ AgentHostController
              │ MessagePort
        Agent Host Utility Process
        ├─ CodeEditorQueue
        └─ AcpAdapter
              │ ACP JSON-RPC
        Claude Agent ACP
```

Main은 Electron 생명주기, 파일 시스템, 로컬 UI와 소켓을 소유합니다. Agent Host는 ACP와 이후 `ai-module`이 Main 이벤트 루프를 막지 않도록 Utility Process에서 실행됩니다. Agent Host가 종료되면 대기 RPC를 실패시키고 1초 뒤 재시작하지만 FileService와 폴백 에디터는 유지됩니다.

## 파일 흐름

파일을 열면 SHA-256 revision과 UTF-8 내용을 함께 반환합니다. 저장은 Renderer가 받은 revision을 `expectedRevision`으로 되돌려 보내는 낙관적 잠금 방식입니다. 외부 도구나 ACP가 먼저 파일을 바꾸면 저장을 거부하고 Editor가 내 내용 유지 또는 디스크 다시 열기를 선택하게 합니다.

FileService는 요청 경로의 기존 부모까지 `realpath`로 확인합니다. 따라서 `..`, 절대 경로, 디렉터리 심볼릭 링크로 프로젝트 밖에 접근할 수 없습니다.

## ACP 실행과 큐

`CodeEditorQueue`는 워크스페이스 ID마다 별도 큐를 유지합니다. 동일 프로젝트의 쓰기 작업은 하나씩 실행하고 다른 프로젝트는 병렬 실행합니다. 대기 중 취소된 항목은 ACP로 전달하지 않으며 실행 중 취소는 `session/cancel` 후 응답이 없으면 프로세스를 종료합니다.

`AcpAdapter`는 공식 `@agentclientprotocol/sdk`의 NDJSON stream을 사용합니다. 세션 업데이트를 Agent Host 이벤트로 정규화하고, 파일 워처와 실행 전후 스냅샷을 결합해 변경 파일을 수집하며, 실패 시 ACP stderr의 마지막 8KB만 결과 detail에 포함합니다.

승인 결정은 `PermissionResolver` 주입 지점입니다. 승인 브리지가 연결되기 전 기본 정책은 거부입니다.

## PetBridge

PetBridge는 연결 후 `client_hello(role="workspace")`를 전송합니다. JSON 한 줄이 여러 소켓 chunk로 분리되거나 여러 줄이 한 chunk로 들어와도 파싱합니다. 도구 요청은 UUID로 결과와 매칭하며 timeout·AbortSignal·연결 종료 시 정리됩니다. 재연결 간격은 1, 2, 4, 8, 16, 30초로 증가합니다.

## 후속 담당자 연결 지점

- EditorGateway는 FileService와 WorkspaceRegistry를 사용해 HTTP/WebSocket 계층을 구성합니다.
- 실제 ai-module은 `AgentRuntime` 포트를 구현하고 Agent Host의 `runCodeEditor` 진입점에 연결합니다.
- SessionRouter와 RunRegistry는 `workspaceId`, `sessionId`, `requestId`를 보존해 Agent Host RPC를 호출합니다.
- 승인 브리지는 AcpAdapter의 `resolvePermission`에 연결합니다.
- protocol 확장 메시지는 공통 protocol 릴리스 전에는 wire로 전송하지 않습니다.
