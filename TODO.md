# Workspace 전체 구현 TODO

> **2026-08-12 ai-module v6 통합:** `packages/ai-module` 실제 런타임 연결, Workspace별 세션 히스토리 유지, 승인 게이트/`open_task_session`, 이미지 attachment 전달까지 연결 완료. 남은 핵심은 실제 pet-app+Claude 인증 환경 E2E와 ACP OS 수준 샌드박싱이다.

기준 문서: `plan/03_workspace.md` Workspace 개발 기획서 v2  
최종 갱신: 2026-08-04

## 코드베이스 마무리 리팩터링 (`refactor/codebase`)

분석 기준: `plan-main/03_workspace.md`, 현재 `main` 브랜치, 소스/테스트/문서 정적 분석

### P0 — 이번 브랜치에서 완료

- [x] **Main composition root 분리**: `src/main/index.ts`에 섞였던 CLI 파싱, 폴백 창, 런타임 조립, Agent/PetBridge 라우팅, 종료 처리를 `src/main/app`의 독립 모듈로 분리했다. 진입점은 시작/치명적 실패 처리만 남겼다.
- [x] **Renderer App 역할 축소**: Monaco 공통 설정과 titlebar/command dock/editor surface를 분리해 `App.tsx`가 편집 상태와 화면 조립에 집중하도록 정리했다.
- [x] **저장소 검증 자동화 복구**: 실제 트리에서 누락된 CI 워크플로를 복구하고 architecture → typecheck → unit → build → E2E 순서를 명시했다.
- [x] **문서와 실제 구현 동기화**: README, architecture 문서, protocol 호환 문서의 담당 범위·프로세스 경계·실행 명령·현재 파일 경로를 갱신했다.
- [x] **구조 회귀 방지**: 소스 import cycle, 계층 역참조, 거대 진입 파일 회귀를 검사하는 무의존성 스크립트를 추가하고 CI에 연결했다.

검증 메모: `node scripts/check-architecture.mjs`, 전체 TS/TSX 구문 변환, runtime options 스모크, CI YAML 파싱은 통과했다. 외부 네트워크가 차단된 작업 환경이라 `pnpm install/typecheck/test/build/test:e2e`는 이 브랜치에서 재실행하지 못했으며 CI에서 확인해야 한다.

### P1 — 외부 계약/실환경이 준비되면 완료

- [ ] **AI 실행 경계 확정**: 기획서의 Agent Host 소유 원칙과 현재 Main의 `SessionRouter`/`RunRegistry`/`MockAgentRuntime` 임시 배치를 실제 `ai-module` 태그 기준으로 정리한다.
- [ ] **wire 메시지 런타임 검증**: EditorGateway/PetBridge의 `unknown` payload 및 다수의 이중 캐스트를 protocol의 판별 유니언 또는 런타임 스키마 검증으로 치환한다.
- [ ] **ACP 파일시스템 격리**: cwd 지정만으로는 막지 못하는 워크스페이스 외부 절대경로 쓰기를 OS 샌드박스 또는 검증 프록시로 차단한다.
- [ ] **protocol snapshot/request_id 통합**: `state_snapshot`, `request_id`, `run_id` 계약이 배포되면 임시 확장 타입과 순서 의존 라우팅을 제거한다.
- [ ] **실환경 인수 검증**: 실제 Claude 인증, pet-app WKWebView/bridge.sock, macOS 패키징에서 단독 및 전체 왕복 시나리오를 통과시킨다.


## 표기

- [x] 구현 및 현재 자동 테스트 완료
- [ ] 미구현 또는 최종 통합 검증 필요
- `부분 완료`는 기반 코드가 있지만 완료 기준을 아직 충족하지 못한 항목
- 담당: `이주한`, `김민영`, `공통`

## 지금 먼저 해야 할 P0

- [ ] **공통** protocol PR: `state_snapshot`, `request_id`, 확장 `run_cancel(run_id)` 계약 확정
- [x] **김민영** 단일 HTTP/WebSocket `EditorGateway` 구현
- [x] **김민영** `SessionRouter`와 `RunRegistry` 구현
- [ ] **김민영** 실제 태그 버전 `ai-module`을 Agent Host에 연결 -- `부분 완료`: ai-module 저장소가 아직 `.gitignore` 커밋 하나뿐이라(태그 없음) 설치 불가. `AgentRuntime`/`ApprovalPort` 포트와 `petAppProxy`/`editorLocal` 실행기는 실제 계약대로 배선 완료했고, 현재는 `src/main/app/agent-runtime-coordinator.ts`가 `MockAgentRuntime`을 임시 연결한다. 기획서 4장의 최종 소유 경계는 Agent Host이며, 실제 패키지가 준비되면 coordinator를 Agent Host RPC 어댑터로 치환한다.
- [x] **김민영** 승인·취소 브리지를 ai-module/ACP/PetBridge와 연결
- [ ] **공통** PetAgentClient → Workspace → ai-module → ACP → Editor View 전체 왕복 테스트
- [ ] **이주한** 실제 Claude 인증 환경에서 자연어 파일 수정·취소·ACP 크래시 검증

---

## W0. 계약 테스트 환경

### 이주한

- [x] protocol v0.5.0 패키지 연결 및 버전 고정
- [x] Mock PetBridge 상대 서버와 JSON Lines 왕복 테스트
- [x] Mock ACP Agent 프로세스와 공식 SDK 왕복 테스트
- [x] Mock AgentRuntime 포트 구성
- [x] JSON Lines 구조화 로그 및 비밀값 마스킹
- [x] 타입 검사, Vitest, Playwright 실행 환경

### 김민영

- [x] Mock ai-module이 `user_input`부터 callback까지 실제 인터페이스대로 동작하도록 보강 (`mocks/mock-agent-runtime.ts` -- tool/approval/session 스크립트 지원)
- [x] Mock EditorGateway HTTP/WebSocket 클라이언트 작성 (`mocks/mock-editor-gateway-client.ts` -- `connectMockEditorGateway`/`toEditorGatewayWsUrl`, 다른 저장소도 재사용 가능한 독립 모듈로 추출, `editor-gateway.test.ts`는 이제 이걸 얇게 감싸 쓴다)
- [x] Mock 승인 요청/응답 시나리오 작성 (`pending-approval-store.test.ts`, `run-cancellation.test.ts`, `mock-agent-runtime.test.ts`의 `approve:` 스크립트)

### 공통

- [x] 저장소 간 protocol 버전 호환 매트릭스 작성 (2026-08-04, 4라운드) `docs/protocol-compatibility-matrix.md` -- protocol(v0.5.0, HEAD `4244922`)·workspace(같은 커밋에 고정)·pet-app(Swift 파일 4개 수동 벤더링, diff로 스키마 동일 확인)·ai-module(코드 없음, "확인 불가"로 명시하고 코드가 생기면 다시 볼 목록 정리)까지 로컬에 체크아웃된 세 저장소를 직접 열어 확인. 코드 변경 없음
- [x] 잘못된 메시지, 알 수 없는 type, 누락 필드 계약 테스트 (2026-08-04, 4라운드) `pet-bridge.test.ts`(깨진 JSON/알 수 없는 type/필수 필드 누락/대기 중이지 않은 tool_result 4건, 크래시 없이 로깅만 하고 다음 메시지는 정상 처리되는지까지 확인), `editor-gateway.test.ts`(형식 깨진 JSON/type 필드 누락/file:save 필수 필드 누락 3건 추가, 기존 "알 수 없는 type" 테스트와 함께 커버). 테스트를 짜다가 pet-bridge.test.ts의 mock 서버 소켓에 `data` 리스너가 없으면(paused 상태) FIN을 못 받아 `server.close()`가 영영 안 끝나는 실제 버그를 발견해 `setup()`에 `socket.resume()`을 추가해 고쳤다
- [x] CI에서 architecture → typecheck → unit → build → E2E 순서 자동 실행 (`.github/workflows/ci.yml`) -- private protocol 저장소 인증(`PROTOCOL_PAT`), frozen lockfile 설치, Linux xvfb E2E, Playwright 리포트 업로드를 포함한다. 이번 리팩터링 환경은 외부 네트워크가 차단되어 의존성 설치 기반 명령은 재실행하지 못했고, 대신 architecture 검사·TypeScript 구문 변환·런타임 옵션 스모크·YAML 파싱을 통과했다. 전체 명령은 CI의 첫 실행에서 최종 확인한다.

**완료 기준:** 모든 Mock 사이에서 사용자 입력, 도구 요청, 승인, 취소, 완료 이벤트 왕복

---

## W1. 파일 편집

### 이주한

- [x] 프로젝트 폴더 선택 및 기본 Workspace 연결
- [x] WorkspaceRegistry의 `default` 워크스페이스와 메타데이터 복구
- [x] `realpath` 기반 프로젝트 경로 정규화
- [x] 파일 트리 조회
- [x] Monaco Editor 통합
- [x] 파일 탭 열기·전환·닫기 및 미저장 표시
- [x] revision 기반 읽기·저장
- [x] 임시 파일 작성 후 교체하는 원자적 저장
- [x] 외부 파일 변경 감지
- [x] 경로 이탈 및 심볼릭 링크 이탈 차단
- [x] 바이너리와 잘못된 UTF-8 편집 차단
- [x] 2MB 초과 텍스트 읽기 전용 처리
- [x] 다크 Editor UI와 로컬 Geist 폰트
- [x] Monaco의 부정확한 외부 의존성 진단 제거 및 구문 검사 유지
- [x] PNG·JPEG·GIF·WebP 이미지 파일의 MIME 검증 미리보기
- [x] 폴더·파일 생성, 이름 변경, 삭제는 1차 경량 에디터 범위에서 제외
- [x] 저장되지 않은 탭의 7일 만료 임시 복구 데이터 저장

### 김민영

- [x] 파일 충돌 화면에 실제 diff 연결 (`App.tsx` + `@monaco-editor/react`의 `DiffEditor`, side-by-side)
- [x] `내 내용 유지`, `디스크 내용 사용`, `diff 비교` 전체 동작 완성 -- `내 내용 유지`가 revision을 최신 디스크 값으로 갱신하지 않아 다음 저장이 `file_conflict`로 다시 막히는 버그를 함께 고쳤다(`editor-state.ts`의 `keepMine` 액션에 `revision` 필드 추가). E2E(`tests/e2e/file-conflict-diff.spec.ts`)로 diff 버튼 표시·내 내용 유지 후 저장까지 검증

### 공통

- [x] ACP와 사용자가 같은 파일을 동시에 수정하는 실제 통합 시험 (2026-08-04, 5라운드) `src/agent-host/acp-user-concurrent-edit.test.ts` -- Mock ACP 자식 프로세스(FileService를 거치지 않고 직접 파일에 쓴다, 실제 ACP처럼)와 FileService.saveFile(revision 검사 + 임시 파일 후 rename, 기존 구현 그대로 사용, 새 잠금 메커니즘 없음)이 같은 파일을 두고 부딪히는 세 시나리오 검증: (1) 사용자 저장 성공 후 ACP가 덮어쓰면 디스크는 ACP 내용 그대로이고 FileService의 chokidar watcher가 change 이벤트를 실제로 발생시킨다(EditorGateway가 이걸 file:changed로 브로드캐스트하는 배선은 W2에서 이미 검증됨), (2) ACP가 먼저 쓴 뒤 사용자가 낡은 revision으로 저장을 시도하면 file_conflict로 막히고 ACP 내용이 보존된다, (3) `Promise.all`로 진짜 동시에 부딪혀도 최종 디스크 내용이 항상 완전한 값이고(부분/혼합 내용 없음) 폴링 중 관측되는 값도 완전한 값이거나 ACP 자체의 truncate+write 순간의 빈 문자열(우리 쪽 결함이 아니라 원자적 저장을 거치지 않는 외부 프로세스 특유의 현상)뿐이다. 테스트를 짜다가 실제 버그를 하나 발견해 고쳤다 -- Windows에서 `rename(temporary, target)`이 다른 프로세스가 그 순간 대상 파일을 쓰고 있으면 `file_conflict`가 아니라 raw `EPERM`을 그대로 던졌다(5번 중 2번꼴로 재현). `file-service.ts`의 saveFile에 EPERM/EBUSY를 file_conflict로 정규화하는 코드를 추가해 고쳤다(새 잠금 메커니즘이 아니라 기존 에러 코드 체계에 케이스 하나 추가하는 수준의 수정, 원 소유자 이주한의 파일이라 수정 전 사용자에게 확인받음)
- [x] 대규모 프로젝트 파일 트리 성능 및 제외 패턴 정책 확정 (2026-08-04, 4라운드) `docs/file-tree-performance.md` -- `DEFAULT_IGNORES`에 `.next`/`build`/`target`/`.venv`/`venv`/`__pycache__`/`.pytest_cache`/`.cache`/`coverage`/`.turbo`/`Pods`/`.build`/`DerivedData` 추가(이 에디터가 지원하는 언어의 표준 빌드/의존성/캐시 디렉터리 기준, `out`처럼 소스 폴더명으로도 흔한 이름은 의도적으로 제외). `file-service-large-tree.test.ts`로 제외 목록이 listTree/watch 양쪽에서 실제로 걸러지는지 회귀 테스트 추가. `scripts/benchmark-file-tree.mjs`로 실측(제외 적용 시 2천/2만 파일 규모에서 각각 3.9배/5.4배 빠름) -- 새 정책을 재설계하지 않고, 현재 방식이 감당 가능한 규모(수천~1만 파일대)와 그 이상일 때의 대응 방향(응답 상한, 디렉터리 단위 lazy loading, 병렬 I/O)을 문서에 정리만 해뒀다(구현 안 함)

**완료 기준:** 외부 변경과 동시 수정 상황에서도 원본 손상 없이 편집·저장

---

## W2. EditorGateway와 두 호스트 지원

### 이주한

- [x] Electron 폴백 창과 격리된 preload
- [x] Windows 기본 메뉴·프레임 제거 및 내부 창 제어 버튼
- [x] 폴백 셸에서 프로젝트 선택·편집·명령 입력·중지·상태 표시
- [x] Editor View 정적 빌드의 Monaco worker·로컬 폰트·상대 asset 오프라인 검증
- [ ] macOS 폴백 창과 타이틀바 동작 검증

### 김민영

- [x] Workspace 프로세스당 단일 HTTP 서버
- [x] `/editor/:workspaceId` 라우팅
- [x] 프로세스 시작 시 임의 접근 토큰 생성
- [x] HTTP 요청 token 검증
- [x] WebSocket 연결 token 검증
- [x] 허용 Origin 검증
- [x] workspace ID 유효성 검증
- [x] 요청 본문 크기 제한
- [x] Editor View 정적 파일 제공
- [x] WebSocket 요청/응답의 `requestId` 매칭
- [x] 파일 트리·읽기·저장 API 연결
- [x] 파일 변경 이벤트 브로드캐스트
- [x] ACP 진행 상태 브로드캐스트
- [ ] WKWebView에서 Editor View 로드 -- 클라이언트 트랜스포트(`renderer/gateway-transport.ts`, `gateway-workspace-api.ts`)는 준비됐지만 실제 pet-app WKWebView와의 통합 검증은 pet-app 쪽 작업 필요
- [x] Electron 폴백 창도 동일 EditorGateway URL 사용
- [x] Editor View 재연결 시 열린 탭·활성 탭·작업 상태 복원 (`App.tsx`가 게이트웨이 호스트에서 마운트 시 `restoreState()`를 호출해 탭을 다시 열고, 탭/활성 탭 변경 시 디바운스해 `saveState()`로 반영. `tests/e2e/editor-gateway-reconnect.spec.ts`로 새로고침 후 탭 복원 검증. 이 작업 중 asset(js/css) 요청이 token 없이 401로 막히던 실제 버그도 함께 고쳤다 -- index.html이 상대 경로로 asset을 참조해 브라우저가 쿼리스트링을 안 옮기므로, 진입 문서/WS만 token을 요구하도록 조정)

### 공통

- [x] `editor_view_ready` URL을 PetAgentClient에 전달하는 계약 시험 (2026-08-03, 3라운드) `tests/e2e/editor-view-status-contract.spec.ts` -- 실제 PetBridge 소켓으로 `editor_view_ready`/`editor_view_unavailable`을 받아 workspace_id·url이 맞는지, 그 url이 실제로 200을 반환하는지까지 왕복 검증. project_path 있는/없는 워크스페이스 둘 다, 그리고 두 번째 워크스페이스 생성까지 포함
- [x] 서로 다른 두 워크스페이스 URL과 WebSocket 격리 시험 (2026-08-03, 3라운드) `src/main/editor-gateway-isolation.test.ts` -- file:changed/acp:update/acp:working-paths 브로드캐스트, state:update/restore, open_in_editor 대기 탭, FileService 자체가 워크스페이스별로 격리되는지 확인. 이 테스트를 작성하다 `mocks/mock-editor-gateway-client.ts`의 실제 버그를 하나 발견해 같이 고쳤다 -- `next(timeoutMs)`가 타임아웃으로 reject된 뒤에도 그 waiter를 큐에서 제거하지 않아서, 그다음에 도착하는(관련 없는) 메시지가 죽은 Promise로 조용히 삼켜지고 후속 `next()` 호출이 자기 타임아웃까지 기다리게 되는 문제였다(다른 저장소도 이 mock 클라이언트를 재사용하므로 영향 범위가 있었음)

**완료 기준:** PetAgentClient WKWebView와 Electron 폴백 창에서 동일 Editor View 사용

---

## W3. Agent Host, 세션, 실행 관리

### 이주한

- [x] Electron Utility Process 기반 Agent Host
- [x] MessagePort RPC 요청 ID·timeout·응답 매칭
- [x] Agent Host 상태·ACP 업데이트 이벤트 전달
- [x] Agent Host 종료 시 대기 RPC 실패 처리
- [x] Agent Host 자동 재시작
- [x] Main 종료 시 Agent Host 안전 종료
- [x] Agent Host 강제 크래시 E2E와 재시작 후 새 작업 성공 검증
- [x] 재시작 직후 중복 Agent Host 생성 방지 스트레스 테스트

### 김민영

- [x] `SessionRouter` 구현
- [x] 동일 `session_id` 사용자 입력 순차 라우팅
- [x] 서로 다른 세션 병렬 실행
- [x] ai-module 자체 큐와 Workspace 라우팅 큐의 중복 방지 (SessionRouter가 세션당 직렬 체인을 단일하게 소유)
- [x] `RunRegistry` 구현
- [x] `ActiveRun` 시작·완료·상태 전이 관리
- [x] 동일 세션 중복 실행 정책 구현 (`DuplicateActiveRunError`)
- [x] 실행과 승인 요청 연결 (`attachApproval`/`approvalsFor`)
- [x] Agent Host 종료 시 모든 ActiveRun 실패 처리 (`AgentHostController`에 `exited` 이벤트 추가 + `failAllActiveRuns`)
- [x] AI 이벤트를 protocol 이벤트로 정규화 (`src/main/app/agent-runtime-coordinator.ts`의 Agent Host event 라우팅 -- `code_editor_update`를 requestId/workspaceId로 감싸도록 Agent Host도 함께 고쳤다)

### 공통

- [x] 세션·워크스페이스 메타데이터 저장 형식 리뷰 (2026-08-03, 3라운드) `docs/session-workspace-metadata-review.md` -- WorkspaceRegistry(영속)/SessionRegistry(비영속) 저장 형식·책임 경계 정리, state_snapshot 작업 시작 시 바꿔야 할 것(영속화 여부, 고아 레코드 정리, 보존 정책, 스냅샷 API)과 ai-module 연결 시 바꿔야 할 것(이중 저장 방지)을 분리해 기록. 코드 변경 없음(리뷰 문서, protocol PR 전에는 형식 확정이 의미 없다고 판단)
- [x] Agent Host 재시작 시 GUI에 복구 상태 전달 (2026-08-04, 4라운드) `agent-host-controller.ts`가 spawn 시 "AI 기능 준비 중", 비정상 종료 후 재시작 예약 시 "AI 기능을 다시 시작하는 중"까지는 이미 `App.tsx`의 상태 표시줄로 연결돼 있었는데, 재시작이 실제로 끝나는(`ready`) 시점에 정상 상태로 되돌리는 이벤트가 없어 재시작 후에도 GUI가 "다시 시작하는 중"에 계속 머무는 게 실제 갭이었다 -- `ready` 이벤트 핸들러에 `emit("status", "준비됨")`을 추가해 고쳤다. `agent-host-controller.test.ts`(electron 모듈을 목으로 대체해 spawn/ready/비정상종료/재시작 상태 전이 순서를 검증)로 단위 테스트, `tests/e2e/fallback-shell.spec.ts`에 폴백 창에서 크래시 후 상태 텍스트가 "다시 시작하는 중" → "준비됨"으로 돌아오는지 확인하는 E2E도 추가했으나 이 로컬 환경의 Electron/Playwright 버전 문제로 e2e 자체는 로컬에서 실행 확인을 못 했다(기존 e2e도 동일 문제로 실행 불가 -- 위 CI 항목 참고)

**완료 기준:** Main을 막지 않고 세션 순서·병렬성·실행 상태가 정확히 유지됨

---

## W4. PetBridge와 상태 동기화

### 이주한

- [x] macOS UDS와 Windows Named Pipe 경로 지원
- [x] `client_hello(role="workspace")` 핸드셰이크
- [x] 분할/병합 JSON Lines 파싱
- [x] `tool_dispatch`와 `tool_result` ID 매칭
- [x] 도구별 timeout
- [x] AbortSignal과 `tool_cancel`
- [x] 연결 종료 시 대기 도구 즉시 실패
- [x] 지수 backoff 자동 재연결
- [x] 잘못된 protocol 메시지와 알 수 없는 result 로깅
- [x] 수신 `user_input`·`run_cancel`을 Agent Host/WorkspaceController로 실제 라우팅
- [x] `agent_thinking`·`text_chunk`·`agent_done` 이벤트를 PetAgentClient로 실제 브로드캐스트
- [ ] pet-app 실제 `bridge.sock`과 장시간 재연결 시험

### 김민영

- [x] `workspace_create_request`와 응답 처리 (`WorkspaceRegistry.create` 재사용, `workspace_create`로 확정 응답 + `editor_view_ready`/`unavailable` 통지)
- [x] `session_create_request`와 응답 처리 (`session-registry.ts`, `session_create(origin=user)`로 확정 응답. `open_task_session`의 agent 기원 세션도 같은 레지스트리에 기록해 일관성 유지). `tests/e2e/petbridge-create-requests.spec.ts`로 왕복 검증
- [ ] 요청·응답 `request_id` 매칭 -- protocol v0.5.0에 `request_id` 필드 자체가 없어(공통 PR 대기) "정식" 매칭은 못 함. 지금은 메시지 도착 순서대로 순차 처리하고 확정 이벤트로만 응답
- [x] `user_input`을 SessionRouter로 연결
- [x] 승인·취소 GUI 메시지 연결 (`approval_response`/`run_cancel`)
- [x] Editor View URL 준비 이벤트 전송 (`editor_view_ready`/`editor_view_unavailable`, 프로젝트 바인딩 시점 + pet-app 재연결 시점마다 재통지)

### 공통

- [ ] protocol에 `state_snapshot_request`와 `state_snapshot` 추가
- [ ] Workspace·Session·Editor URL snapshot 생성
- [ ] PetAgentClient 최초 연결·재연결 시 snapshot 동기화
- [ ] protocol 확장 플래그 제거 및 정식 타입 사용

**완료 기준:** PetAgentClient 재실행 후에도 전체 워크스페이스·세션·작업 상태 복원

---

## W5. Claude Agent ACP

### 이주한

- [x] 공식 ACP TypeScript SDK 연결
- [x] Claude Agent ACP 자식 프로세스 실행 구조
- [x] ACP initialize·session/new·prompt·update 처리
- [x] Agent 메시지 요약과 업데이트 전달
- [x] 파일 워처·전후 snapshot 기반 변경 파일 수집
- [x] stderr 마지막 8KB 오류 detail
- [x] 워크스페이스별 쓰기 작업 1개인 `CodeEditorQueue`
- [x] 같은 워크스페이스 대기 및 다른 워크스페이스 병렬 실행
- [x] 대기 중 작업 취소 시 ACP 미전달
- [x] 실행 중 `session/cancel`과 강제 종료 fallback
- [x] 동일 워크스페이스 ACP 세션 정책 구현: 작업별 격리, 재사용하지 않음
- [x] ACP 프로세스 수명주기 정책 확정: 작업 완료·취소·실패 시 즉시 종료
- [ ] 실제 Claude 인증으로 자연어 파일 수정 성공
- [x] Mock ACP 실제 프로세스 실행 중 취소 후 파일 무결성 확인
- [x] ACP 강제 크래시 후 다음 작업에서 재스폰 성공
- [x] 현재 최신 Claude Agent ACP 0.64.0·SDK 1.3.0 Mock 왕복 및 장애 호환 테스트

### 김민영

- [x] ACP `requestPermission`을 ApprovalPort에 연결 (`acp-permission-bridge.ts` -- Agent Host가 크로스 프로세스로 Main에 되묻는 `permission_request`/`permissionResponse` 왕복 추가)
- [x] ACP session/update를 표준 agent 이벤트로 변환 (text_chunk/working-paths/EditorGateway 브로드캐스트)
- [x] ACP 결과를 ai-module `code_editor` 결과로 반환 (`tool-executors.ts`의 `mapCodeEditorResult`)

### 공통

- [x] ACP가 사용할 수 있는 경로가 WorkspaceRegistry 경로와 일치하는지 통합 검증 (2026-08-04, 5라운드) `src/agent-host/acp-workspace-path-boundary.test.ts` -- W6의 "세션 workspace를 기준으로 실제 project path 강제"(이미 완료)는 Main 프로세스 tool-executor 레이어에서 모델이 보낸 project_path를 무시하고 `workspace.realProjectPath`를 쓴다는 걸 단위 테스트로 확인할 뿐이라 겹치지 않는다고 판단했다 -- 여기서는 그 값이 실제로 `AcpAdapter`의 `spawn(..., {cwd})`까지, 즉 자식 프로세스 레벨까지 그대로 전달되는지를 확인한다. 실제 `WorkspaceRegistry`로 워크스페이스를 만들고 그 `realProjectPath`를 `AcpAdapter.run`에 넘겨 spawn에 전달된 cwd가 정확히 일치하는지(spy) + Mock ACP가 그 cwd 기준으로 쓴 결과물이 실제로 그 경로 밑에 나타나는지 이중으로 확인. 두 번째 테스트로 워크스페이스 경계 밖 절대경로 쓰기 시도(Mock ACP에 `ESCAPE:<path>` 시나리오 추가, `tests/fixtures/mock-acp-agent.mjs`)도 검증 -- **중요한 갭 발견**: `AcpAdapter`는 spawn에 cwd만 지정할 뿐 OS 수준 샌드박싱이 전혀 없어서, 절대경로 쓰기 자체는 실제로 성공한다(파일이 워크스페이스 밖에 진짜로 생긴다). `changedFiles` 결과 목록에는 `relativeProjectPath`가 걸러내 안 잡히므로(결과가 새지 않는다는 것까지는 확인됨) 이번 항목의 완료 기준은 충족하지만, "차단"까지는 안 된다는 걸 별도 항목으로 아래 남긴다(사용자 확인받음, TODO.md 신규 항목 참고)
- [x] 모델이 전달한 `project_path`를 무시하는 보안 테스트 -- 이미 커버됨. W6의 "세션 workspace를 기준으로 실제 project path 강제"(`tool-executors.test.ts`, `deps.projectPath`만 쓰고 args의 project_path는 절대 안 씀)가 정확히 이 항목이다. 같은 걸 두 섹션에 중복 기재해뒀던 것으로 보여 정리만 함(2026-08-04, 5라운드)
- [ ] **신규(2026-08-04, 5라운드)** ACP 자식 프로세스에 실제 파일시스템 샌드박싱(예: 플랫폼별 제한된 토큰/chroot 유사 기법, 또는 최소한 쓰기 대상 경로를 워크스페이스 안으로 검증하는 프록시) 적용 -- 지금은 cwd 지정이 전부라 오작동하거나 악의적인 ACP가 절대경로로 워크스페이스 밖에 실제로 쓸 수 있다(위 항목의 `acp-workspace-path-boundary.test.ts`가 이 갭을 그대로 보여줌). 결과 보고(changedFiles)만 새지 않을 뿐 파일 시스템 쓰기 자체는 막지 못한다. 실제 Claude Agent ACP가 이 정도 자유도로 동작하는 게 맞는지, 막아야 한다면 어느 레이어(Agent Host? OS?)에서 막을지부터 논의 필요 -- 이번 라운드 범위 밖(발견만 하고 사용자 확인 받아 새 항목으로 분리)

**완료 기준:** 실제 자연어 명령으로 프로젝트 파일 수정, 결과 요약, 변경 목록, 취소 성공

---

## W6. ai-module 및 Workspace 도구 통합

### 김민영

- [ ] 합의된 실제 태그 버전 `ai-module` 설치 -- 저장소에 태그도 코드도 없어(2026-08-02 기준 `.gitignore` 커밋 1개) 설치할 대상이 없다. 아래 항목들은 실제 포트 계약(`shared/ports.ts`)대로 배선했고, `src/main/app/agent-runtime-coordinator.ts`에서 `MockAgentRuntime`을 임시 구현체로 연결했다.
- [ ] Agent Host 안에서 ai-module 초기화 -- `plan/03_workspace.md` 4.1~4.2의 원칙대로 AI 응답 생성과 세션/실행 관리는 최종적으로 Agent Host가 소유한다. 현재는 설치 가능한 ai-module이 없어 Main의 coordinator에 임시 캡슐화되어 있다.
- [ ] Claude API 키와 모델을 필요한 시점에만 전달 -- ai-module이 없어 아직 전달할 대상이 없다(ACP/Agent Host 쪽 키 전달은 이주한이 이미 구현)
- [x] `petAppProxy` 구현 및 PetBridge 연결 (`tool-executors.ts`의 `createPetAppProxyExecutor`)
- [x] `editorLocal` 구현 및 EditorGateway 연결 (`createEditorLocalExecutor`)
- [x] `code_editor(task, project_path)` 등록 (editorLocal이 처리, ai-module의 실제 tool-use 루프가 없어 `MockAgentRuntime`의 `tool:` 스크립트로 왕복 검증)
- [x] 세션 workspace를 기준으로 실제 project path 강제 (모델이 보낸 project_path 무시 -- 단위 테스트로 확인)
- [x] `CodeEditorResult`를 ai-module 결과로 반환
- [x] `open_in_editor` 구현
- [x] 경로 검증 및 `file_not_found` 처리 (protocol에 전용 에러 코드가 없어 `execution_failed`+detail로 표준화, TODO 주석으로 protocol PR 필요성 명시)
- [x] Editor View 미연결 시 마지막 탭 요청 저장
- [x] 다음 Editor View 연결 시 저장된 파일 열기
- [x] `read_file` 구현
- [x] 프로젝트 내부 읽기 전용 접근
- [x] 대용량·바이너리·인코딩 오류 표준화
- [x] ai-module callback을 PetAgentClient 이벤트로 전달 (`AgentCallbacks` → `petBridge.sendEvent`, `src/main/app/agent-runtime-coordinator.ts`)

### 이주한

- [ ] 실제 통합 후 Agent Host 리소스·프로세스 경계 조정
- [x] ACP tool location의 작업 중 파일을 Editor View 파일 트리에 실시간 표시
- [x] Agent Host CPU 작업 중 Main 이벤트 루프 응답성 E2E 확인

### 공통

- [ ] ai-module 인터페이스가 현재 protocol 버전과 일치하는지 리뷰
- [ ] 필요한 protocol 변경은 Workspace 임시 타입보다 protocol PR 우선

**완료 기준:** 사용자 입력 → ai-module → 도구 → ACP → 결과 이벤트 전체 성공

---

## W7. 승인, 취소, 설정, 복구, 배포

### 김민영

- [x] `PendingApproval` 저장소 구현 (`pending-approval-store.ts`)
- [x] `approval_id` 생성과 `await_approval` 전송
- [x] `approval_response` 한 번만 resolve
- [x] 중복·알 수 없는 승인 ID 무시
- [x] 실행 취소 시 관련 승인 자동 거부 (`run-cancellation.ts`의 `cancelActiveRun`)
- [x] Agent Host 종료 시 승인 자동 거부 (`failAllActiveRuns`)
- [x] pet-app 연결 종료 시 승인 자동 거부 (`petBridge.on("state", ...)`에서 `rejectAll()`)
- [ ] 폴백 셸 승인 팝업 -- 렌더러 UI(App.tsx)에 아직 붙이지 않음. 채팅 패널이 pet-app으로 이관되면서 폴백 셸의 승인 UI 형태가 재정의 필요(이번 라운드 범위 밖으로 판단)
- [x] 현재 protocol `run_cancel(session_id)` 호환 처리
- [ ] 확장 `run_cancel(workspace_id, session_id, run_id)` 처리 -- `PROTOCOL_EXTENSIONS_ENABLED=false`인 동안은 wire로 보내지 않는다는 기존 원칙을 따름, 공통 protocol PR 이후 진행
- [x] 취소 시 ActiveRun → pet 도구 → ACP → 승인 순서 정리
- [x] `agent_done(ok=false, summary="중단됨")` 전송 (정상 완료 경로와 경합해도 `RunRegistry.markDoneSent`로 정확히 한 번만 전송)
- [x] 설정 화면: API 키, 모델, 최근 프로젝트, 창 크기, 파일 제한, 로그 수준 (`SettingsPanel.tsx` + `settings-controller.ts`/`settings-store.ts`, 폴백 셸 전용 -- 게이트웨이 호스트에는 노출 안 함. API 키는 이주한의 `SecretStore`(safeStorage) 그대로 재사용, 값은 렌더러/로그에 절대 노출 안 됨(hasApiKey 플래그만 왕복). 로그 수준은 `JsonlLogger`에 `minLevel` 필터를 추가해 실제로 동작. 파일 크기 제한은 다음 프로젝트 연결부터 반영(이미 연 FileService는 재적용 안 함). API 키 변경은 다음 Agent Host 재시작부터 반영(현재 구조상 실행 중인 Agent Host의 env는 갱신 못 함). `tests/e2e/settings-panel.spec.ts`로 검증
- [x] Editor diff 화면 (위 W1 항목과 동일 구현)

### 이주한

- [x] Electron `safeStorage` 기반 API 키 암호화 저장
- [x] 키를 Renderer와 로그에 노출하지 않음
- [x] Agent Host/ACP에 최소 환경 변수 전달
- [x] JSON Lines 로그 및 민감 필드 마스킹
- [x] Electron 종료 시 Bridge·Agent Host·FileService 정리
- [x] electron-builder Windows 디렉터리 패키징
- [x] 실행·구조 README
- [x] 저장된 폴백 창 크기·위치·최대화 상태 적용 및 화면 이탈 복구
- [x] 로그 일별·5MB 회전, 14일 보존, 최대 30개 파일 정책
- [x] 자체 노드 아이콘과 Windows NSIS 설치 프로그램 구성
- [ ] macOS 앱 아이콘·서명·notarization·패키징
- [x] Windows 패키지에서 Agent Host·Claude ACP·native `claude.exe` 탐색 검증

### 공통

- [x] 첨부 이미지 확장자와 실제 MIME 일치 검증 (2026-08-03, 3라운드) `src/main/attachment-validator.ts`(`validateAttachment`) -- file-service.ts의 매직 바이트 판별을 `shared/image-mime.ts`로 뽑아 재사용. `src/main/attachment-validator.test.ts`로 검증
- [x] 첨부 최대 크기와 파일 존재 검증 (2026-08-03, 3라운드) 위와 동일 파일, `file_too_large`/`file_not_found` 에러 코드로 구분
- [x] 허용 임시 디렉터리·사용자 선택 파일 검증 (2026-08-03, 3라운드) `AttachmentPolicy.allowedDirectories`(기본 OS 임시 디렉터리, realpath 정규화) + `allowedPaths`(사용자가 명시적으로 고른 개별 경로용 확장점, 지금은 빈 값 -- 첨부 파일 선택 UI 자체가 아직 없어 실제로 채워지는 경로는 없다)
- [x] 첨부 심볼릭 링크 이탈 방지 (2026-08-03, 3라운드) file-service.ts의 경로 이탈 검사(`isInside`)를 `shared/path-containment.ts`로 뽑아 재사용, realpath 기준으로 허용 디렉터리 밖을 가리키는 심볼릭 링크를 `symlink_escape`로 별도 구분. 잘못된 확장자/위조 MIME/크기 초과/미존재/허용 범위 밖 경로/심볼릭 링크 이탈 6가지 모두 단위 테스트로 확인(`attachment-validator.test.ts`, 심볼릭 링크 테스트는 이 환경(Windows, 개발자 모드 없음)에서 symlink 생성 권한이 없어 런타임에 건너뛰지만 나머지 5개+정상 케이스는 항상 통과). `src/main/app/pet-bridge-router.ts`의 `user_input` 처리에 `filterValidAttachments`로 연결해 실제로 걸러진 첨부만 ai-module로 넘어가게 배선했다
- [ ] 임시 캡처 파일 삭제 책임을 pet-app과 확정 (2026-08-04 갱신: F14는 pet-app에서 2026-08-01에 이미 구현 완료됨 -- `Puck/Input/ScreenRegionCapture.swift`가 `FileManager.default.temporaryDirectory`에 캡처 파일을 생성해 attachment로 전달, `pet-app/PROGRESS.md` "quick-capture panel moves to bottom-center, and F14 drag-capture attachments finally land" 항목 참고. 다만 삭제 로직은 코드 어디에도 없음 -- pet-app도 지우지 않고, Workspace 쪽도 첨부를 읽기만 하고 지우지 않는다(검증 실패해도 파일은 그대로 둠). "F14 구현 전이라 대상이 없다"는 기존 사유는 더 이상 유효하지 않으므로, 이제는 실제로 삭제 책임 주체를 정하는 논의 자체를 진행해야 함
- [x] Editor View 종료 전 미저장 내용 경고 (2026-08-03, 3라운드) `부분 완료`: Electron 폴백 창은 `src/main/app/fallback-window.ts`에서 `webContents.on("will-prevent-unload", ...)`을 연결해 실제로 닫기를 막고 확인 대화상자를 띄우도록 고쳤다 -- 기존에는 `App.tsx`의 `beforeunload`가 `preventDefault()`를 해도 Electron이 `will-prevent-unload`를 아무도 안 들으면 그냥 닫아버리는 문제가 있었다(Electron 고유 동작, 실제로 안 막히고 있었음). WKWebView(게이트웨이 호스트) 쪽은 이 저장소에서 할 수 있는 부분(App.tsx의 표준 `beforeunload` 핸들러)은 이미 있지만, pet-app이 WKWebView를 닫을 때 실제로 확인창을 띄우려면 pet-app의 Swift `WKUIDelegate`가 beforeunload 확인 패널을 구현해야 한다 -- pet-app 쪽 작업이라 이번 라운드 범위 밖(다른 WKWebView 관련 항목들과 동일하게 cross-repo 의존)
- [x] Editor View 임시 복구 데이터와 만료 정책 (2026-08-03, 3라운드) 점검 결과 정리는 지금까지 정리가 "같은 프로젝트를 다시 열 때"만 일어나는 lazy 방식이라, 한 번 열고 다시 열지 않은 프로젝트의 draft는 7일이 지나도 아무도 안 지우는 사각지대가 있었다 -- `src/renderer/draft-store.ts`의 `sweepExpiredDrafts()`를 앱 시작 시 한 번(App.tsx의 mount effect) 호출해 모든 `workspace:drafts:*` 키를 훑어 만료/손상 항목을 정리하도록 채웠다(`draft-store.test.ts`로 검증). 점검 중 별개로 발견한 것: EditorGateway가 포트 0(OS 임의 할당)으로 뜨기 때문에 재시작마다 origin이 바뀌어, "재시작 후에도 복구"가 필요한 시나리오(이 기능의 원래 목적)에서는 localStorage 자체에 접근할 수 없다(같은 세션 내 새로고침/재연결에는 영향 없음, `editor-gateway-reconnect.spec.ts`로 검증된 범위). 포트를 고정하려면 여러 Workspace 프로세스 동시 실행 시 포트 경합을 같이 풀어야 해서 이번 라운드에서 고치지 않고 `editor-gateway.ts`에 코멘트로 남겨뒀다 -- 별도 항목으로 다룰 것을 제안
- [x] 개인정보·API 키·프로젝트 경로 로그 정책 리뷰 (2026-08-04, 4라운드) `docs/log-privacy-review.md` -- `logger.write(...)` 호출부 전수 확인. `REDACTED_KEYS`는 키 이름 기준이라 값 자체가 필요한 `projectPath`/`path`/`socketPath` 같은 필드의 절대경로 유출은 못 잡는다는 걸 확인하고, 실제 유출 3건(`workspace_project_bound`의 `realProjectPath`, `attachment_rejected`의 첨부 절대경로, `pet_bridge_connected`의 macOS `socketPath`)을 새로 만든 `basenameForLog()` 헬퍼(마지막 세그먼트만 기록)로 고쳤다. `logger.test.ts`에 단위 테스트 추가. 나머지(원본 그대로 남겨야 진단에 쓸모 있는 `invalid_protocol_message`의 raw value, `error.message`에 fs 경로가 섞일 수 있는 케이스들)는 범위 밖으로 판단해 문서에 근거를 적어뒀다

**완료 기준:** 승인·취소·재연결·크래시 후에도 작업 상태와 파일이 일관되게 복구됨

---

## 필수 장애 시험

### 이주한

- [x] 외부 파일 변경 감지 단위 시험
- [x] revision이 다른 같은 파일 저장 충돌 시험
- [x] 잘못된 경로와 심볼릭 링크 이탈 시험
- [x] 잘못된 JSON Lines와 protocol 메시지 시험
- [x] PetBridge 연결 종료 시 대기 요청 실패 시험
- [x] CodeEditorQueue 대기 취소 시험
- [x] Agent Host 강제 크래시 및 자동 재시작 E2E
- [x] ACP 강제 크래시 및 다음 작업 재스폰 E2E
- [ ] 실제 ACP 수정 중 취소와 부분 파일 무결성 시험
- [ ] pet-app 종료 중 ACP 작업 지속 시험

### 김민영

- [x] 승인 대기 중 pet-app 연결 종료 시험 (`petbridge-approval-integration.test.ts` -- 실제 `PetBridge`를 mock 소켓 서버에 붙이고 연결 종료 시 대기 승인이 `rejectAll()`로 자동 거부되는지, 연결이 살아있는 동안은 거부되지 않는지 둘 다 확인)
- [x] 같은 세션 중복 사용자 입력 순서 시험 (`session-router.test.ts`)
- [ ] `run_id`가 다른 취소 요청 오작동 방지 시험 -- 현재 protocol의 `run_cancel`은 `run_id`가 없어(session_id만) 해당되지 않음, 확장 계약이 정식화된 뒤 진행
- [x] EditorGateway WebSocket 재연결 시험 (연결 종료 후 재연결해 `state:restore`로 상태 복원 확인)
- [x] Editor View 재연결 후 탭·작업 상태 복원 시험 (서버 측, 위와 동일 테스트)
- [x] 잘못된 token·Origin·workspace ID·본문 크기 시험

### 공통

- [ ] PetAgentClient 종료·재실행 후 snapshot 복구 시험
- [ ] 실제 pet-app과 잘못된 protocol 메시지 상호 운용 시험
- [x] 두 워크스페이스에서 ACP 병렬 작업 시험 (2026-08-04, 4라운드) `code-editor-queue-acp-integration.test.ts` -- `code-editor-queue.test.ts`는 mock execute 함수로 큐 자체의 정책만 확인했었는데(W5), 실제 `CodeEditorQueue` + `AcpAdapter` + Mock ACP 자식 프로세스(`tests/fixtures/mock-acp-agent.mjs`) 조합으로 서로 다른 두 워크스페이스에 진짜 ACP 작업을 동시에 붙여 검증했다. 한 워크스페이스를 `WAIT`로 붙잡아 둔 채 다른 워크스페이스 작업이 기다리지 않고 끝나는지, 결과 파일이 각자 프로젝트 폴더에만 남는지(워크스페이스 격리) 둘 다 확인. 같은 워크스페이스 안에서는 여전히 순차 실행되는 것도 함께 검증
- [x] 장시간 실행·반복 재연결·메모리 누수 시험 (2026-08-04, 5라운드) `src/main/editor-gateway-connection-churn.test.ts` -- EditorGateway WebSocket을 300회 연결·해제 반복하며 매 반복마다 서버 쪽 연결 목록(`state.connections`)이 정확히 0으로 돌아오는지 확인(관측을 위해 `EditorGateway.connectionCount()` 최소 접근자 추가, `CodeEditorQueue.position()`과 같은 기존 관측용 공개 메서드 패턴). heap은 50회마다 샘플링해 반복 횟수에 비례해 계속 자라지 않는지 널널한 임계값으로 스모크 체크(정밀 프로파일링 도구는 새로 안 씀). `pending-approval-store`/`run-registry`/`session-registry`는 EditorGateway의 WS 연결·해제와 코드상 연동돼 있지 않아(`editor-gateway.ts`의 `handleConnection`/`forget`이 건드리는 건 워크스페이스별 connections Set뿐) 이번 시험 범위에서 제외함(사용자 확인받음) -- 세 registry는 PetBridge/AgentHost/승인 흐름에 연결돼 있고 그 경로들은 이미 `petbridge-approval-integration.test.ts`(W7) 등 다른 시험으로 커버돼 있음

---

## 최종 인수 시나리오

### 단독 실행

- [ ] Workspace 실행
- [ ] 프로젝트 선택
- [ ] 파일 열기·편집·저장
- [ ] 폴백 명령 입력
- [ ] ai-module 실행
- [ ] Claude Agent ACP 파일 수정
- [ ] 변경 파일 실시간 갱신
- [ ] diff 확인
- [ ] 승인 및 취소
- [ ] 앱 재실행 후 메타데이터 복구

### 전체 통합

- [ ] PetAgentClient 사용자 입력
- [ ] pet-app `bridge.sock` 전달
- [ ] Workspace SessionRouter/RunRegistry 등록
- [ ] ai-module tool-use 실행
- [ ] `code_editor` → CodeEditorQueue → ACP
- [ ] 파일 변경과 Editor View 갱신
- [ ] 결과를 PetAgentClient와 pet-app에 전달
- [ ] PetAgentClient 재연결 후 state snapshot 복구

---

## 담당별 남은 작업 요약

### 이주한

- 실제 Claude ACP·실제 pet-app·macOS 환경 검증
- ACP 세션 재사용 및 프로세스 수명주기
- Agent Host/ACP 크래시 E2E
- Editor View 미저장 복구
- 패키지 아이콘·서명·macOS 배포
- 통합 이후 전체 기술 조정

### 김민영

- (2026-08-02, P0) EditorGateway, SessionRouter/RunRegistry, 도구 3종(petAppProxy/editorLocal), 승인·취소 브리지는 포트 계약대로 구현·테스트 완료. 실제 ai-module 태그가 나오면 `src/main/app/agent-runtime-coordinator.ts`의 runtime 생성 경계를 Agent Host RPC 어댑터로 교체하도록 정리함
- (2026-08-03, 2라운드) Editor View 재연결 탭 복원(App.tsx 연동 + E2E), 파일 충돌 diff 화면과 `내 내용 유지`의 revision 갱신 버그 수정, `workspace_create_request`/`session_create_request` 처리, 설정 화면(API 키/모델/최근 프로젝트/파일 제한/로그 수준), 승인-PetBridge 연결 종료 통합 시험, Mock EditorGateway 클라이언트 독립 모듈화까지 완료. 이 라운드에서 EditorGateway의 asset 401 버그와 `keepMine` revision 버그 등 실사용 시나리오(E2E)로만 드러나는 결함 두 건을 추가로 발견·수정함
- (2026-08-03, 3라운드) 첨부 파일 보안 정책 4건(확장자/MIME/크기/존재/경로/심볼릭 링크, `attachment-validator.ts` + 단위 테스트, `src/main/app/pet-bridge-router.ts` 배선), `editor_view_ready`/`unavailable` 계약 E2E, 두 워크스페이스 WebSocket 격리 단위 테스트, Electron 폴백 창 미저장 경고(`will-prevent-unload` 연결 -- 기존엔 안 막히고 있던 버그), draft 만료 데이터 시작 시 sweep, 세션·워크스페이스 메타데이터 리뷰 문서까지 완료. 이 라운드에서 Mock EditorGateway 클라이언트의 타임아웃 waiter 누수 버그(`next()`가 타임아웃 후에도 waiter를 안 지워 다음 메시지를 삼킴)를 격리 테스트 작성 중 발견·수정함
- (2026-08-04, 5라운드, **마지막 라운드**) 이 라운드에 배정된 항목 3개 모두 완료: (1) ACP와 사용자의 동시 파일 수정 실제 통합 시험(`acp-user-concurrent-edit.test.ts`) -- 테스트를 짜다가 Windows에서 `file-service.ts`의 원자적 저장이 다른 프로세스와 rename이 겹치면 `file_conflict`가 아니라 raw `EPERM`을 그대로 던지는 실제 버그를 발견, 사용자 확인 후 EPERM/EBUSY를 file_conflict로 정규화해 고쳤다. (2) ACP 프로세스 cwd가 WorkspaceRegistry의 realProjectPath와 정확히 일치하는지 통합 검증(`acp-workspace-path-boundary.test.ts`, W6의 tool-executor 레이어 검증과는 다른 레이어임을 먼저 확인) -- 검증 중 AcpAdapter가 spawn에 cwd만 지정할 뿐 OS 수준 파일시스템 샌드박싱이 전혀 없다는 걸 발견(절대경로로 워크스페이스 밖에 실제로 쓸 수 있음, changedFiles 결과에만 안 잡힘), 사용자 확인 후 새 TODO 항목(W5 공통)으로 분리해 남겼다. (3) EditorGateway WebSocket 300회 연결·해제 반복 시험(`editor-gateway-connection-churn.test.ts`) -- 서버 쪽 연결 목록이 매 반복 0으로 돌아오는지, heap이 반복에 비례해 계속 자라지 않는지 확인. `pending-approval-store`/`run-registry`/`session-registry`는 WS 연결·해제와 무관해 범위에서 제외(사용자 확인받음). 세 항목 모두 시작 전 진행 순서·범위 판단이 필요한 지점을 먼저 사용자에게 확인받고 진행함
- **진짜로 남은 건 전부 외부 의존**: 실제 ai-module 태그 연결(ai-module 저장소가 아직 `.gitignore` 커밋 하나뿐이라 설치할 대상 자체가 없음 -- ai-module 저장소/팀의 몫), 폴백 셸 승인 팝업 UI(채팅 UI가 pet-app으로 이관되며 형태 재정의가 먼저 필요, 별도 논의 대상), state snapshot 생성·전달과 `request_id` 정식 매칭(공통 protocol PR이 `state_snapshot`/`request_id` 계약을 확정해야 시작 가능), WKWebView 쪽 미저장 경고 확인창(pet-app의 Swift `WKUIDelegate` 구현 필요, cross-repo), 임시 캡처 파일 삭제 책임(F14 캡처는 구현됐지만 pet-app/Workspace 어느 쪽도 삭제하지 않음), EditorGateway 포트 고정(여러 Workspace 프로세스 동시 실행 시 포트 경합까지 함께 풀어야 해서 별도 항목 제안 상태), ACP 파일시스템 샌드박싱(이번 라운드에 새로 발견, 실제 Claude Agent ACP가 이 정도 자유도로 동작하는 게 맞는지부터 논의 필요 -- 코드만으로 결정할 수 없는 설계 판단). Workspace 저장소 안에서 코드만으로 끝낼 수 있는 항목은 이번 라운드로 소진됨

### 공통

- protocol 확장 PR과 타입 리뷰
- PetAgentClient/pet-app 전체 통합
- 첨부 파일 보안 정책 (3라운드에서 검증 로직 4건 완료, 구현된 F14 임시 캡처 파일의 삭제 책임만 미확정)
- 필수 장애 시험과 최종 인수 테스트
- (2026-08-04, 4라운드) 외부 의존성 없이 바로 끝낼 수 있던 항목 7개 완료: pet-bridge/editor-gateway 잘못된 메시지 계약 테스트, 로그의 절대경로 유출 3건 수정(`basenameForLog`), 두 워크스페이스 ACP 병렬 통합 테스트, 파일 트리 제외 패턴 확장 및 성능 실측, Agent Host 재시작 후 GUI 상태 복구(`ready` 시 "준비됨" 재emit), CI 워크플로(`ci.yml`) 신규 작성, protocol 버전 호환 매트릭스 문서. 테스트를 짜다가 실사용에서만 드러나는 버그 2건도 발견·수정함: pet-bridge 테스트용 mock 소켓이 `data` 리스너 없이 paused 상태로 남아 `server.close()`가 안 끝나던 문제, `agent-host-controller.ts`가 재시작 완료 후에도 GUI 상태를 "다시 시작하는 중"에 방치하던 문제. 여전히 막힌 것: E2E(`pnpm test:e2e`)는 이 Windows 개발 환경의 Electron/Playwright 버전 조합 문제로 로컬 실행 확인을 못 했다(새로 만든 CI에서 처음 돌 때 검증 필요) -- 기존 e2e 테스트도 동일 환경 문제로 로컬에서 안 됨을 확인했으므로 이번에 손댄 코드 때문에 생긴 문제는 아니다
