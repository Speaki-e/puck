# Workspace 전체 구현 TODO

기준 문서: `plan/03_workspace.md` Workspace 개발 기획서 v2  
최종 갱신: 2026-08-03

## 표기

- [x] 구현 및 현재 자동 테스트 완료
- [ ] 미구현 또는 최종 통합 검증 필요
- `부분 완료`는 기반 코드가 있지만 완료 기준을 아직 충족하지 못한 항목
- 담당: `이주한`, `김민영`, `공통`

## 지금 먼저 해야 할 P0

- [ ] **공통** protocol PR: `state_snapshot`, `request_id`, 확장 `run_cancel(run_id)` 계약 확정
- [x] **김민영** 단일 HTTP/WebSocket `EditorGateway` 구현
- [x] **김민영** `SessionRouter`와 `RunRegistry` 구현
- [ ] **김민영** 실제 태그 버전 `ai-module`을 Agent Host에 연결 -- `부분 완료`: ai-module 저장소가 아직 `.gitignore` 커밋 하나뿐이라(태그 없음) 설치 불가. `AgentRuntime`/`ApprovalPort` 포트와 `petAppProxy`/`editorLocal` 실행기는 실제 계약대로 배선 완료, `MockAgentRuntime`으로 임시 대체(`main/index.ts`의 TODO 주석 참고). ai-module은 실행 위치를 Main 프로세스로 정함(TODO.md 기존 문구와 plan 문서가 갈렸던 부분 -- Main으로 확정)
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

- [ ] 저장소 간 protocol 버전 호환 매트릭스 작성
- [ ] 잘못된 메시지, 알 수 없는 type, 누락 필드 계약 테스트
- [ ] CI에서 typecheck → unit → E2E 순서 자동 실행

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

- [ ] ACP와 사용자가 같은 파일을 동시에 수정하는 실제 통합 시험
- [ ] 대규모 프로젝트 파일 트리 성능 및 제외 패턴 정책 확정

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

- [ ] `editor_view_ready` URL을 PetAgentClient에 전달하는 계약 시험
- [ ] 서로 다른 두 워크스페이스 URL과 WebSocket 격리 시험

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
- [x] AI 이벤트를 protocol 이벤트로 정규화 (`main/index.ts`의 `agentHost.on("event", ...)` -- `code_editor_update`를 requestId/workspaceId로 감싸도록 Agent Host도 함께 고쳤다)

### 공통

- [ ] 세션·워크스페이스 메타데이터 저장 형식 리뷰
- [ ] Agent Host 재시작 시 GUI에 복구 상태 전달

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

- [ ] ACP가 사용할 수 있는 경로가 WorkspaceRegistry 경로와 일치하는지 통합 검증
- [ ] 모델이 전달한 `project_path`를 무시하는 보안 테스트

**완료 기준:** 실제 자연어 명령으로 프로젝트 파일 수정, 결과 요약, 변경 목록, 취소 성공

---

## W6. ai-module 및 Workspace 도구 통합

### 김민영

- [ ] 합의된 실제 태그 버전 `ai-module` 설치 -- 저장소에 태그도 코드도 없어(2026-08-02 기준 `.gitignore` 커밋 1개) 설치할 대상이 없다. 아래 항목들은 실제 포트 계약(`shared/ports.ts`)대로 배선해뒀고, `MockAgentRuntime`을 임시 구현체로 연결했다(`main/index.ts`의 TODO 주석 참고)
- [ ] Agent Host 안에서 ai-module 초기화 -- Main 프로세스에서 구동하는 쪽으로 확정(plan/03_workspace.md 4.1 원문 채택). ai-module 자체가 없어 초기화 대상도 없음
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
- [x] ai-module callback을 PetAgentClient 이벤트로 전달 (`AgentCallbacks` -> `petBridge.sendEvent`, `main/index.ts`)

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

- [ ] 첨부 이미지 확장자와 실제 MIME 일치 검증
- [ ] 첨부 최대 크기와 파일 존재 검증
- [ ] 허용 임시 디렉터리·사용자 선택 파일 검증
- [ ] 첨부 심볼릭 링크 이탈 방지
- [ ] 임시 캡처 파일 삭제 책임을 pet-app과 확정
- [ ] Editor View 종료 전 미저장 내용 경고
- [ ] Editor View 임시 복구 데이터와 만료 정책
- [ ] 개인정보·API 키·프로젝트 경로 로그 정책 리뷰

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
- [ ] 두 워크스페이스에서 ACP 병렬 작업 시험
- [ ] 장시간 실행·반복 재연결·메모리 누수 시험

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

- (2026-08-02, P0) EditorGateway, SessionRouter/RunRegistry, 도구 3종(petAppProxy/editorLocal), 승인·취소 브리지는 포트 계약대로 구현·테스트 완료. 실제 ai-module 태그가 나오면 `main/index.ts`의 `MockAgentRuntime` 한 줄만 교체하면 되도록 배선해둠
- (2026-08-03, 2라운드) Editor View 재연결 탭 복원(App.tsx 연동 + E2E), 파일 충돌 diff 화면과 `내 내용 유지`의 revision 갱신 버그 수정, `workspace_create_request`/`session_create_request` 처리, 설정 화면(API 키/모델/최근 프로젝트/파일 제한/로그 수준), 승인-PetBridge 연결 종료 통합 시험, Mock EditorGateway 클라이언트 독립 모듈화까지 완료. 이 라운드에서 EditorGateway의 asset 401 버그와 `keepMine` revision 버그 등 실사용 시나리오(E2E)로만 드러나는 결함 두 건을 추가로 발견·수정함
- 남은 것: 실제 ai-module 태그 연결(저장소가 아직 비어 있어 대기), 폴백 셸 승인 팝업 UI(채팅 UI가 pet-app으로 이관되며 형태 재정의 필요, 별도 논의 대상), state snapshot 생성·전달과 `request_id` 정식 매칭(공통 protocol PR 대기)

### 공통

- protocol 확장 PR과 타입 리뷰
- PetAgentClient/pet-app 전체 통합
- 첨부 파일 보안 정책
- 필수 장애 시험과 최종 인수 테스트
