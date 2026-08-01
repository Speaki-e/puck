# Workspace 전체 구현 TODO

기준 문서: `plan/03_workspace.md` Workspace 개발 기획서 v2  
최종 갱신: 2026-08-02

## 표기

- [x] 구현 및 현재 자동 테스트 완료
- [ ] 미구현 또는 최종 통합 검증 필요
- `부분 완료`는 기반 코드가 있지만 완료 기준을 아직 충족하지 못한 항목
- 담당: `이주한`, `김민영`, `공통`

## 지금 먼저 해야 할 P0

- [ ] **공통** protocol PR: `state_snapshot`, `request_id`, 확장 `run_cancel(run_id)` 계약 확정
- [ ] **김민영** 단일 HTTP/WebSocket `EditorGateway` 구현
- [ ] **김민영** `SessionRouter`와 `RunRegistry` 구현
- [ ] **김민영** 실제 태그 버전 `ai-module`을 Agent Host에 연결
- [ ] **김민영** 승인·취소 브리지를 ai-module/ACP/PetBridge와 연결
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

- [ ] Mock ai-module이 `user_input`부터 callback까지 실제 인터페이스대로 동작하도록 보강
- [ ] Mock EditorGateway HTTP/WebSocket 클라이언트 작성
- [ ] Mock 승인 요청/응답 시나리오 작성

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
- [ ] 이미지 파일 미리보기
- [ ] 폴더·파일 생성, 이름 변경, 삭제가 필요할지 제품 범위 확정
- [ ] 저장되지 않은 탭의 임시 복구 데이터 저장

### 김민영

- [ ] 파일 충돌 화면에 실제 diff 연결
- [ ] `내 내용 유지`, `디스크 내용 사용`, `diff 비교` 전체 동작 완성

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
- [ ] Editor View 정적 빌드를 패키징 결과에서 독립적으로 제공하는지 검증
- [ ] macOS 폴백 창과 타이틀바 동작 검증

### 김민영

- [ ] Workspace 프로세스당 단일 HTTP 서버
- [ ] `/editor/:workspaceId` 라우팅
- [ ] 프로세스 시작 시 임의 접근 토큰 생성
- [ ] HTTP 요청 token 검증
- [ ] WebSocket 연결 token 검증
- [ ] 허용 Origin 검증
- [ ] workspace ID 유효성 검증
- [ ] 요청 본문 크기 제한
- [ ] Editor View 정적 파일 제공
- [ ] WebSocket 요청/응답의 `requestId` 매칭
- [ ] 파일 트리·읽기·저장 API 연결
- [ ] 파일 변경 이벤트 브로드캐스트
- [ ] ACP 진행 상태 브로드캐스트
- [ ] WKWebView에서 Editor View 로드
- [ ] Electron 폴백 창도 동일 EditorGateway URL 사용
- [ ] Editor View 재연결 시 열린 탭·활성 탭·작업 상태 복원

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
- [ ] Agent Host 강제 크래시 E2E와 재시작 후 새 작업 성공 검증
- [ ] 재시작 직후 중복 Agent Host 생성 방지 스트레스 테스트

### 김민영

- [ ] `SessionRouter` 구현
- [ ] 동일 `session_id` 사용자 입력 순차 라우팅
- [ ] 서로 다른 세션 병렬 실행
- [ ] ai-module 자체 큐와 Workspace 라우팅 큐의 중복 방지
- [ ] `RunRegistry` 구현
- [ ] `ActiveRun` 시작·완료·상태 전이 관리
- [ ] 동일 세션 중복 실행 정책 구현
- [ ] 실행과 승인 요청 연결
- [ ] Agent Host 종료 시 모든 ActiveRun 실패 처리
- [ ] AI 이벤트를 protocol 이벤트로 정규화

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
- [ ] 수신 GUI 메시지를 Agent Host/WorkspaceController로 실제 라우팅
- [ ] Workspace 이벤트를 PetAgentClient로 실제 브로드캐스트
- [ ] pet-app 실제 `bridge.sock`과 장시간 재연결 시험

### 김민영

- [ ] `workspace_create_request`와 응답 처리
- [ ] `session_create_request`와 응답 처리
- [ ] 요청·응답 `request_id` 매칭
- [ ] `user_input`을 SessionRouter로 연결
- [ ] 승인·취소 GUI 메시지 연결
- [ ] Editor View URL 준비 이벤트 전송

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
- [ ] 동일 워크스페이스 ACP 세션 생성·재사용 정책 구현
- [ ] ACP 프로세스 pool/수명주기와 유휴 종료 정책 확정
- [ ] 실제 Claude 인증으로 자연어 파일 수정 성공
- [ ] 실제 실행 중 취소 후 파일 무결성 확인
- [ ] ACP 강제 크래시 후 다음 작업에서 재스폰 성공
- [ ] Claude Agent ACP 업그레이드 호환 테스트

### 김민영

- [ ] ACP `requestPermission`을 ApprovalPort에 연결
- [ ] ACP session/update를 표준 agent 이벤트로 변환
- [ ] ACP 결과를 ai-module `code_editor` 결과로 반환

### 공통

- [ ] ACP가 사용할 수 있는 경로가 WorkspaceRegistry 경로와 일치하는지 통합 검증
- [ ] 모델이 전달한 `project_path`를 무시하는 보안 테스트

**완료 기준:** 실제 자연어 명령으로 프로젝트 파일 수정, 결과 요약, 변경 목록, 취소 성공

---

## W6. ai-module 및 Workspace 도구 통합

### 김민영

- [ ] 합의된 실제 태그 버전 `ai-module` 설치
- [ ] Agent Host 안에서 ai-module 초기화
- [ ] Claude API 키와 모델을 필요한 시점에만 전달
- [ ] `petAppProxy` 구현 및 PetBridge 연결
- [ ] `editorLocal` 구현 및 EditorGateway 연결
- [ ] `code_editor(task, project_path)` 등록
- [ ] 세션 workspace를 기준으로 실제 project path 강제
- [ ] `CodeEditorResult`를 ai-module 결과로 반환
- [ ] `open_in_editor` 구현
- [ ] 경로 검증 및 `file_not_found` 처리
- [ ] Editor View 미연결 시 마지막 탭 요청 저장
- [ ] 다음 Editor View 연결 시 저장된 파일 열기
- [ ] `read_file` 구현
- [ ] 프로젝트 내부 읽기 전용 접근
- [ ] 대용량·바이너리·인코딩 오류 표준화
- [ ] ai-module callback을 PetAgentClient 이벤트로 전달

### 이주한

- [ ] 실제 통합 후 Agent Host 리소스·프로세스 경계 조정
- [ ] code_editor 실행 중 파일 변경을 Editor View에 실시간 표시
- [ ] 전체 흐름에서 Main 이벤트 루프 응답성 확인

### 공통

- [ ] ai-module 인터페이스가 현재 protocol 버전과 일치하는지 리뷰
- [ ] 필요한 protocol 변경은 Workspace 임시 타입보다 protocol PR 우선

**완료 기준:** 사용자 입력 → ai-module → 도구 → ACP → 결과 이벤트 전체 성공

---

## W7. 승인, 취소, 설정, 복구, 배포

### 김민영

- [ ] `PendingApproval` 저장소 구현
- [ ] `approval_id` 생성과 `await_approval` 전송
- [ ] `approval_response` 한 번만 resolve
- [ ] 중복·알 수 없는 승인 ID 무시
- [ ] 실행 취소 시 관련 승인 자동 거부
- [ ] Agent Host 종료 시 승인 자동 거부
- [ ] pet-app 연결 종료 시 승인 자동 거부
- [ ] 폴백 셸 승인 팝업
- [ ] 현재 protocol `run_cancel(session_id)` 호환 처리
- [ ] 확장 `run_cancel(workspace_id, session_id, run_id)` 처리
- [ ] 취소 시 ActiveRun → pet 도구 → ACP → 승인 순서 정리
- [ ] `agent_done(ok=false, summary="중단됨")` 전송
- [ ] 설정 화면: API 키, 모델, 최근 프로젝트, 창 크기, 파일 제한, 로그 수준
- [ ] Editor diff 화면

### 이주한

- [x] Electron `safeStorage` 기반 API 키 암호화 저장
- [x] 키를 Renderer와 로그에 노출하지 않음
- [x] Agent Host/ACP에 최소 환경 변수 전달
- [x] JSON Lines 로그 및 민감 필드 마스킹
- [x] Electron 종료 시 Bridge·Agent Host·FileService 정리
- [x] electron-builder Windows 디렉터리 패키징
- [x] 실행·구조 README
- [ ] 저장된 폴백 창 크기 적용
- [ ] 로그 회전·보존 기간·최대 크기
- [ ] Windows 앱 아이콘과 설치 프로그램
- [ ] macOS 앱 아이콘·서명·notarization·패키징
- [ ] 배포 환경에서 Claude Agent ACP 실행 파일 탐색 검증

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
- [ ] Agent Host 강제 크래시 및 자동 재시작 E2E
- [ ] ACP 강제 크래시 및 다음 작업 재스폰 E2E
- [ ] 실제 ACP 수정 중 취소와 부분 파일 무결성 시험
- [ ] pet-app 종료 중 ACP 작업 지속 시험

### 김민영

- [ ] 승인 대기 중 pet-app 연결 종료 시험
- [ ] 같은 세션 중복 사용자 입력 순서 시험
- [ ] `run_id`가 다른 취소 요청 오작동 방지 시험
- [ ] EditorGateway WebSocket 재연결 시험
- [ ] Editor View 재연결 후 탭·작업 상태 복원 시험
- [ ] 잘못된 token·Origin·workspace ID·본문 크기 시험

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

- EditorGateway와 WKWebView 통신
- SessionRouter와 RunRegistry
- 실제 ai-module 통합
- `code_editor`, `open_in_editor`, `read_file`
- 승인·취소 브리지
- diff와 설정 화면
- state snapshot 생성·전달

### 공통

- protocol 확장 PR과 타입 리뷰
- PetAgentClient/pet-app 전체 통합
- 첨부 파일 보안 정책
- 필수 장애 시험과 최종 인수 테스트
