# workspace(Electron)를 Swift로 흡수하고 삭제한다

- 날짜: 2026-08-15
- 상태: 설계 승인됨 (byeolki: "다 지워", "너가 알아서 해봐")
- 성공 기준: **에디터가 Swift에서 정상 동작하고 현재 기능을 전부 수행한다.**
  Electron 없이 워크스페이스 생성 → 파일 편집 → 에이전트 주도 편집(`code_editor`)이
  모두 되어야 한다.

## 1. 배경

2026-08-14 `94b14ef`가 PuckClient의 에디터 패인을 네이티브 SwiftUI로 옮겼다
(`Puck/ClientWindow/Editor/`). 그때 옮기지 않은 것이 남아 Electron이 아직 살아 있다.

`workspace/`에서 **아직 살아 있는 기능**은 셋뿐이다.

1. **워크스페이스/세션 레지스트리** — `workspace-registry.ts`(104줄),
   `session-registry.ts`(36줄). PuckClient의 "새 워크스페이스"는
   `UserInputSender.swift:70`에서 `workspace_create_request`를 브리지로 보내고,
   Electron이 만들어 `workspace_create`로 되돌려준다.
2. **`code_editor`** — `agent-host/`(1,029줄). `Puck/Agent/CodeEditorDelegate.swift`가
   `user_input`으로 위임하고, Electron이 ACP 에이전트(claude/codex)를 자식
   프로세스로 띄워 편집한 뒤 `agent_done`으로 답한다.
3. **브리지 클라이언트** — `pet-bridge.ts`(212줄). 위 둘을 Puck.app 소켓에 연결한다.

나머지는 이미 죽었다: renderer(807줄), `editor-gateway.ts`(402줄, 네이티브 에디터가
대체), `file-service.ts`(252줄, `WorkspaceFileService.swift`에 1:1 사본 존재),
`openai-code-editor.ts`(243줄, 아래 §6에서 폐기 결정).

### 중요한 제약: 순서

`workspace/`를 먼저 지우면 `code_editor`뿐 아니라 **워크스페이스 생성 자체가
죽는다.** projectPath를 가진 워크스페이스를 만들 수단이 사라지고,
`EditorAvailability.resolve(projectPath: nil)`이 `.noProject`를 반환해
네이티브 에디터가 영구히 빈 상태에 갇힌다. 그래서 레지스트리 포팅이 1단계다.

## 2. 목표 아키텍처

```
현재: Puck.app ⇄ 소켓 ⇄ workspace(Electron main) → UtilityProcess(agent-host)
                                                  → node(ACP 에이전트)

목표: Puck.app → node(ACP 에이전트)
```

중간 두 프로세스가 사라진다. **브리지 자체는 남는다** — Puck.app ⇄ PuckClient가
계속 쓴다(`ClientRelay.swift`). 사라지는 것은 workspace를 향한 메시지 타입뿐이다.

### 판단하는 주체는 바뀌지 않는다

`agent-runtime-coordinator.ts`가 명시한다 — "workspace는 '무엇을 할지' 판단하지
않는 일반 에디터다. pet-app의 CodeEditorDelegate가 이미 코딩 작업이라고 판단해 보낸
user_input을 code_editor 한 번으로 실행하는 것뿐이다." 따라서 **에이전트 루프는
포팅 대상이 아니다.** 옮기는 것은 실행기 하나와 그 수명주기뿐이다.

## 3. 새로 만드는 Swift 컴포넌트

모두 `pet-app/Puck/` 아래. Puck 타겟과 PuckClient 타겟이 `Puck/` 폴더를 통째로
컴파일하므로 별도 타겟 설정은 필요 없다.

### 3.1 `Puck/Workspaces/WorkspaceRegistry.swift`

`workspace-registry.ts` 포팅. 워크스페이스 레코드(id/name/projectPath/
realProjectPath/createdAt/updatedAt)를 Application Support에 JSON으로 영속화한다.

- 저장 위치: `~/Library/Application Support/Puck/workspaces.json`
- `realProjectPath`는 심볼릭 링크를 푼 경로(`URL.resolvingSymlinksInPath`) —
  원본과 동일하게 경로 격리 판정의 기준이 된다.
- 원자적 쓰기: 임시 파일에 쓴 뒤 `FileManager.replaceItemAt` (원본의
  write→rename과 같은 보장).
- 기동 시 기본 워크스페이스 하나를 보장(`ensureDefault`).

### 3.2 `Puck/Workspaces/SessionRegistry.swift`

`session-registry.ts` 포팅. 워크스페이스별 세션 목록. 영속화하지 않는다(원본도
메모리 전용).

### 3.3 `Puck/Agent/ACP/AcpAgentProcess.swift`

`acp-adapter.ts`의 프로세스/전송 절반. node를 spawn하고 stdin/stdout에 NDJSON
JSON-RPC를 흘린다.

- **node 탐색**: `PATH` → `/opt/homebrew/bin/node` → `/usr/local/bin/node` →
  `~/.nvm/versions/node/*/bin/node` 순. 못 찾으면 `.nodeMissing` 오류로 끝내고
  `code_editor`만 비활성화한다(앱의 나머지는 정상 동작).
- **에이전트 JS**: 앱 번들의 `Resources/ACP/claude.js` / `codex.js` (§5).
- **환경변수**: 원본과 동일하게 최소만 전달 — `PATH`, `NODE_ENV=production`,
  그리고 선택된 에이전트가 읽는 키만. claude → `ANTHROPIC_API_KEY`,
  codex → `CODEX_API_KEY`/`OPENAI_API_KEY`. 부모 환경 전체를 넘기지 않는다.
  키는 Keychain(`AgentConfiguration`)에서 읽는다.
- **cwd**: 대상 프로젝트 경로.

### 3.4 `Puck/Agent/ACP/AcpSession.swift`

`@agentclientprotocol/sdk`의 client 헬퍼가 하던 일. 손수 구현하며, 필요한
JSON-RPC 표면은 6개다.

| 방향 | 메서드 | 용도 |
|---|---|---|
| → | `initialize` | 프로토콜 버전 협상 |
| → | `session/new` | 프로젝트 경로로 세션 생성 |
| → | `session/prompt` | 작업 지시 전달 |
| ← | `session/update` (알림) | `agent_message_chunk`, `tool_call` 등 스트림 |
| ← | `session/request_permission` (요청) | 에이전트가 승인을 물음 |
| → | `session/cancel` (알림) | 중단 |

`ClaudeClient.swift`(손수 짠 Anthropic Messages 클라이언트, 270줄)와 같은 방식으로
`Codable` 기반 인코딩/디코딩. 취소 시 `session/cancel`을 보내고 2초 뒤에도 살아
있으면 프로세스를 죽인다(원본의 `forceKillTimer`와 동일).

### 3.5 `Puck/Agent/ACP/CodeEditorRunner.swift`

`agent-host/index.ts` + `code-editor-queue.ts` + `run-registry.ts` +
`pending-approval-store.ts` + `run-cancellation.ts`를 하나로 접는다. 다섯 파일이
나뉘어 있던 이유는 프로세스 경계(Main ↔ UtilityProcess) 때문인데, 그 경계가
사라지므로 나눌 이유도 사라진다.

- **워크스페이스별 직렬 큐**: 같은 워크스페이스의 `code_editor`는 한 번에 하나,
  다른 워크스페이스끼리는 병렬. Swift actor로 구현한다(원본의 `CodeEditorQueue`).
- **대기 상태 통지**: 큐에 밀리면 `status(queued, position:)` 이벤트.
- **승인 라우팅**: ACP의 `session/request_permission`을 기존 승인 UI로 올린다 —
  브리지의 `approvalResponse` 메시지를 그대로 재사용하므로 chat-web 쪽 변경 없음.
- **취소**: 실행 중이면 `session/cancel`, 대기 중이면 큐에서 제거.

### 3.6 `Puck/Agent/ACP/ProjectChangeTracker.swift`

`acp-adapter.ts`의 변경 파일 집계(`chokidar` + `projectSnapshot`) 대체.

- 감시는 기존 `WorkspaceFileWatcher.swift`(FSEvents)를 재사용한다. 새로 만들지
  않는다.
- FSEvents가 놓치는 경우를 대비해 원본과 동일하게 실행 전/후 스냅샷
  (경로 → `size:mtime`)을 비교해 합집합을 취한다.
- `.git`, `node_modules` 제외.

## 4. 바뀌는 기존 Swift 코드

- **`Puck/Agent/CodeEditorDelegate.swift`** — 소켓 왕복 대신 `CodeEditorRunner`를
  직접 호출한다. 파일 상단 주석이 설명하던 "user_input으로 우회하는 이유"
  (pet-app → workspace 디스패치 방향이 프로토콜에 없음)가 사라지므로, 그 우회도
  같이 사라진다. 세션당 하나씩만 허용하던 제약(`ponytail:` 주석)도 requestId를
  갖게 되면서 풀린다.
- **`Puck/Tools/ToolRegistry.swift`** — `code_editor`의 `executor`가
  `.workspace` → `.petApp`. `open_in_editor`/`read_file`도 `.workspace`로 남아
  있으나 실제로는 이미 네이티브 위임이라 같이 정리한다. `case workspace`와
  `case aiModule`은 디스패치 대상이 없어지므로 제거.
- **`Puck/Bridge/BridgeMessages.swift`** — workspace를 향하던 메시지 타입 제거:
  `workspaceCreateRequest`/`sessionCreateRequest`(로컬 처리로 대체),
  `editorViewReady`/`editorViewUnavailable`(네이티브 에디터가 이미 대체).
  `workspaceCreate`/`sessionCreate`는 PuckClient에게 결과를 알리는 용도로 **남는다**.
- **`Puck/Bridge/BridgeServer.swift`** — `workspaceFacingConnections()` 및
  "workspace 연결 없음" 상태 개념 제거. `UserInputDelivery.workspaceDisconnected`도
  의미를 잃으므로 정리한다.
- **`Puck/Settings/SettingsStore.swift`** — `codingAgent`(claude|codex) 설정 추가.
  기존 `AgentProvider`(openai|anthropic, 펫의 두뇌)와는 **별개의 축**이다.
  혼동하지 않도록 이름을 `codingAgent`로 유지한다.

## 5. 빌드: ACP 에이전트 번들링

`pet-app/scripts/vendor-acp.sh` (신규). `sync-chat-web.sh`와 같은 패턴 — Xcode가
알 수 없는 외부 의존성을 명시적 사전 단계로 처리한다.

```
esbuild <claude-agent-acp>/dist/index.js --bundle --platform=node \
  --outfile=pet-app/Puck/Resources/ACP/claude.js
esbuild <codex-acp>/dist/index.js --bundle --platform=node \
  --outfile=pet-app/Puck/Resources/ACP/codex.js
```

- 소스 패키지는 전용 `pet-app/scripts/acp/package.json`에 핀으로 고정한다
  (claude-agent-acp `0.64.0`, codex-acp `1.2.0` — workspace가 쓰던 버전 그대로).
- 산출물 2개는 git에 커밋한다. 그래야 체크아웃 직후 npm 없이 빌드된다.
- 이것이 레포에 남는 유일한 Node 흔적이며, 빌드 시에만 쓰인다.

## 6. 삭제 대상

- `workspace/` 전체
- `protocol/` 전체 — TS 소비자가 workspace/ai-module뿐이라 0이 된다.
  `protocol/swift/`의 4개 파일은 pet-app에 이미 사본이 있어 잃는 내용이 없고,
  `swift-mirror.test.ts`는 대조군(TS 구현)이 사라지므로 무의미해진다.
- `ai-module/` 전체 — README가 "never built; superseded by pet-app's F15 agent"라고
  명시. 참조하는 코드 없음.
- `openai-code-editor.ts`의 기능 — 포팅하지 않는다. 존재 이유가 "키가 OpenAI
  하나뿐일 때도 편집이 되게"였는데, codex ACP가 `OPENAI_API_KEY`로 동작하므로
  같은 상황을 더 잘 덮는다.

## 7. 데이터 흐름 (목표)

**워크스페이스 생성**

```
PuckClient "새 워크스페이스"
  → 브리지 workspace_create_request  … 삭제됨
  → ClientWindowStore가 WorkspaceRegistry.create()를 직접 호출
  → workspace_create를 PuckClient로 (기존 경로 그대로)
  → EditorAvailability.resolve(projectPath:) → .ready → 에디터 열림
```

**에이전트 주도 편집**

```
사용자: "이 함수 고쳐줘"
  → AgentRunner(펫 두뇌)가 code_editor 툴 호출로 판단
  → CodeEditorDelegate.execute(task:workspaceId:sessionId:)
  → CodeEditorRunner: 워크스페이스 큐에 등록
  → AcpAgentProcess: node + Resources/ACP/claude.js spawn (cwd=projectPath)
  → AcpSession: initialize → session/new → session/prompt
  → session/update 스트림 → 브리지 이벤트로 relay
       (text_chunk / tool_call → 기존 EventRouter가 펫 타이핑 애니메이션까지 처리)
  → session/request_permission → 기존 승인 UI
  → 종료 → ProjectChangeTracker가 변경 파일 목록 확정 → 툴 결과
```

## 8. 오류 처리

원본의 동작을 유지한다.

| 상황 | 동작 |
|---|---|
| node 없음 | `code_editor`만 비활성화, 사유를 툴 결과에 담아 반환. 앱 나머지는 정상 |
| ACP 프로세스 조기 종료 | stderr 마지막 8KB를 `detail`에 담아 실패 반환 |
| 취소 | `session/cancel` → 2초 후에도 살아 있으면 kill. 결과는 `error: "cancelled"` |
| 타임아웃 | `ToolTimeouts.seconds(for: "code_editor")` = 600초 유지 |
| 승인 거부 | ACP에 `outcome: cancelled` 응답 |
| 프로젝트 경로 소실 | `EditorAvailability.unavailable(.pathMissing)` (기존 로직) |
| 변경 파일 집계 실패 | 실패해도 툴 결과는 반환 — 원본과 동일하게 삼킨다 |

## 9. 테스트

기존 `PuckTests`에 추가한다(현재 1016개 통과).

- `WorkspaceRegistryTests` — 생성/영속화/재기동 후 복원/원자적 쓰기/기본
  워크스페이스 보장/심볼릭 링크 해석
- `AcpSessionTests` — 스텁 프로세스(고정 NDJSON을 뱉는 스크립트)를 상대로
  initialize→new→prompt 왕복, `session/update` 파싱, 승인 요청 왕복, 취소
- `CodeEditorRunnerTests` — 워크스페이스별 직렬화, 다른 워크스페이스 병렬,
  대기 위치 통지, 실행 중 취소 / 대기 중 취소
- `ProjectChangeTrackerTests` — 생성/수정/삭제 감지, `.git`·`node_modules` 제외
- `AcpAgentProcessTests` — node 탐색 순서, 환경변수 최소 전달(에이전트별 키만)

`acp-adapter.test.ts`의 기존 케이스들이 그대로 참고 대상이다 — 특히 환경변수
전달 케이스는 회귀 위험이 큰 지점이라 Swift에서도 동등하게 덮는다.

## 10. 단계

각 단계 끝에서 앱이 동작해야 한다. 되돌릴 수 없는 삭제는 마지막 단계에 몰아둔다.

1. **레지스트리 포팅** — `WorkspaceRegistry`/`SessionRegistry` + 브리지 배선.
   완료 시점에 **Electron 없이 워크스페이스 생성과 네이티브 에디터가 동작한다.**
   (성공 기준의 절반이 여기서 충족된다.)
2. **ACP 번들링** — `vendor-acp.sh`, `Resources/ACP/*.js` 커밋.
3. **ACP 포팅** — `AcpAgentProcess`/`AcpSession`/`ProjectChangeTracker`.
   스텁 상대 테스트까지.
4. **실행기 배선** — `CodeEditorRunner` + `CodeEditorDelegate` 전환 +
   `ToolRegistry` 실행기 변경. 이 시점에 Electron 의존이 0이 된다.
5. **삭제** — `workspace/`, `protocol/`, `ai-module/` + 브리지 메시지 정리.
6. **검증** — 전체 테스트, 두 타겟 빌드, 실제 앱에서 워크스페이스 생성 →
   파일 편집 → `code_editor` 왕복.

## 11. 열린 항목

- `docs/decisions.md`에 이 전환의 결정 기록을 추가한다(레포 관례).
- `README.md`의 모노레포 구성 설명에서 삭제된 세 디렉터리를 걷어낸다.
- CI 워크플로는 현재 없다(`.github/workflows` 부재). 이번 범위에서 만들지 않는다.
