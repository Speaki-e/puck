# Workspace TODO

**현재 상태:** workspace는 순수 코드 에디터 패키지다. `ai-module` 통합은 2026-08-12에 영구
폐기됐고(`../docs/decisions.md` "workspace becomes a plain editor" 참고), workspace는 "무엇을
할지" 판단하지 않는다 -- pet-app의 F15 두뇌(`AgentRunner.swift`)가 이미 코딩 작업으로 분류해 보낸
지시문을 `DirectCodeEditorRuntime`(`src/agent-host/direct-code-editor-runtime.ts`)이 `code_editor`
도구 호출 하나로 실행할 뿐이다. 이건 남아있는 임시 구현이 아니라 최종 설계다.

`code_editor`/`open_in_editor`/`read_file`은 여전히 이 방식대로 필요하다 -- 헷갈리지 말 것. 다만
2026-08-14부로 PuckClient 자체 에디터 패널이 네이티브 SwiftUI(`pet-app/Puck/ClientWindow/Editor/`)로
옮겨가면서, 사람이 수동으로 파일을 browsing/editing하던 workspace의 EditorGateway + Monaco 경로
(`WKWebView` 로드)는 예전보다 덜 쓰인다. Electron 폴백 창은 그대로 이 경로를 쓴다.

아래는 실제로 남아 있는 항목만 정리한 목록이다. 완료됐거나 영구적으로 대상이 사라진 항목
(ai-module 설치, `MockAgentRuntime` 교체, "Agent Host 소유 경계는 실제 ai-module이 준비되면"류
논의)은 전부 뺐다 -- 그 히스토리는 git log와 `../docs/decisions.md`로 충분하다.

## 미해결 항목

### 보안

- [ ] **ACP 파일시스템 샌드박싱 부재.** `AcpAdapter`는 자식 프로세스 spawn 시 `cwd`만 지정한다
  (`src/agent-host/acp-adapter.ts:116`) -- OS 수준 격리가 전혀 없어서, 절대경로를 쓰면 워크스페이스
  밖에도 실제로 파일을 쓸 수 있다. `changedFiles` 결과 보고에는 안 잡히므로(결과 자체는 새지 않음)
  드러나지 않을 뿐 쓰기 자체는 막히지 않는다. 어느 레이어(Agent Host? OS?)에서 막을지 설계 판단이
  먼저 필요한, 아직 논의되지 않은 실제 보안 갭.

### UI

- [ ] **폴백 셸 승인 팝업 없음.** `PendingApprovalStore`(`src/agent-host/pending-approval-store.ts`)는
  구현돼 있지만 렌더러 쪽에 승인 UI가 붙어 있지 않다(`src/renderer`에 승인 관련 컴포넌트 자체가
  없음). 채팅 UI가 pet-app으로 이관된 뒤로 폴백 셸에서 승인 UI가 어떤 형태여야 하는지부터 다시
  정의해야 한다.

### 프로토콜

- [ ] **`state_snapshot`/`request_id` 확장 미구현.** `src/shared/protocol-extensions.ts`의
  `PROTOCOL_EXTENSIONS_ENABLED`가 여전히 `false`다. protocol PR로 계약이 확정되기 전까지는
  PuckClient 재연결 시 workspace/session/editor URL 상태를 snapshot으로 복구하는 것도,
  `request_id` 기반 정식 요청-응답 매칭도 불가능하다 -- 지금은 메시지 도착 순서 기반 순차 처리로
  대체 중.
- [ ] **이중 타입 캐스트 잔존.** EditorGateway/PetBridge 경계에 `as unknown as` 캐스트가 여전히
  여러 곳(`src/main` 기준 19곳) 남아 있다. protocol의 판별 유니언이나 런타임 스키마 검증으로
  대체할 여지가 있음.

### 배포/패키징

- [ ] **macOS 서명/notarization 미검증.** `package.json`의 `build.mac.identity`가 `null`로 고정돼
  있어 서명을 하지 않는다 -- 아이콘, 코드사이닝, notarization, 실제 macOS 패키징 왕복 전부 미검증
  상태다(Windows nsis 패키징만 검증됨).
- [ ] **EditorGateway 포트 미고정.** `server.listen(0, ...)`로 매 실행마다 임의 포트를 할당한다
  (`src/main/editor-gateway.ts:113`) -- 재시작마다 origin이 바뀌어 Editor View의 localStorage 기반
  draft 복구가 "재시작 후 복구"라는 원래 목적에는 못 미친다(같은 세션 내 새로고침/재연결은 영향
  없음). 여러 workspace 프로세스를 동시에 띄울 때의 포트 경합까지 함께 풀어야 해서 미뤄져 있다.

### 정책 미확정

- [ ] **첨부 임시 파일 삭제 책임 미정.** F14 화면 캡처
  (`pet-app/Puck/Input/ScreenRegionCapture.swift`)가 OS 임시 디렉터리에 첨부 파일을 만들어
  전달하지만, pet-app도 workspace도 지우지 않는다(`src/main/attachment-validator.ts`에 삭제 로직
  없음, 검증 실패한 첨부도 그대로 남는다). 어느 쪽이 정리 책임을 가질지 아직 정해지지 않았다.

## 참고 문서

- 배경/의사결정 히스토리: `../docs/decisions.md`
- 현재 아키텍처: `docs/architecture.md`
- protocol 버전 호환 기록(합병 전 시점의 스냅샷): `docs/protocol-compatibility-matrix.md`
