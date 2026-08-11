# Speaki-e Workspace

PetAgent의 로컬 AI 실행 백엔드이자 Monaco 기반 코드 에디터입니다. Electron 폴백 창과 PetAgentClient의 WKWebView가 같은 Editor View를 사용하며, Main 프로세스는 파일·브리지·앱 생명주기를, Agent Host Utility Process는 Claude Agent ACP 실행을 담당합니다.

## 현재 구현

- WorkspaceRegistry와 프로젝트 메타데이터 복구
- 경로 이탈·심볼릭 링크 이탈을 차단하는 FileService
- revision 충돌 검사와 임시 파일 교체 기반 저장
- Monaco 파일 트리, 탭, 이미지 미리보기, 외부 변경 diff, 미저장 복구
- 단일 HTTP/WebSocket EditorGateway와 워크스페이스별 격리
- UDS/Windows Named Pipe PetBridge, 재연결, 승인·취소 라우팅
- Electron Utility Process Agent Host와 비정상 종료 후 재시작
- 공식 ACP SDK 기반 Claude Agent ACP Adapter와 워크스페이스별 직렬 큐
- safeStorage 기반 API 키 보관, 설정, 구조화 로그와 민감값 마스킹
- Vitest 계약/장애 테스트와 Playwright Electron E2E
- ai-module v6 실제 Claude 스트리밍/tool-use/세션 히스토리/승인 게이트 통합
- 이미지 attachment를 Claude 멀티모달 입력으로 전달

`packages/ai-module`에 v6 적용본을 함께 포함하고 실제 실행 경로에 연결했습니다. 테스트 환경(`NODE_ENV=test`) 또는 `WORKSPACE_MOCK_AI=1`에서만 기존 `MockAgentRuntime`을 사용합니다. Workspace별 ai-module 클라이언트를 재사용해 세션 히스토리를 유지하고, 세션별 `editorLocal` 실행기는 AsyncLocalStorage로 격리합니다.

## 요구 환경

- Node.js 22 이상
- pnpm 11.18.0 (`corepack enable` 권장)
- Claude API 키 또는 Claude Agent ACP가 사용할 수 있는 인증 환경
- private `Speaki-e/protocol` 저장소 읽기 권한

## 설치와 실행

```powershell
corepack pnpm install
$env:ANTHROPIC_API_KEY = "키"
corepack pnpm start -- --project C:\path\to\project
```

실제 키 없이 ai-module의 Anthropic SDK 연결만 점검하려면 별도 터미널에서 `corepack pnpm mock:anthropic`을 실행하고, 앱 시작 터미널에 `ANTHROPIC_API_KEY=test`와 `ANTHROPIC_BASE_URL=http://127.0.0.1:8787`을 설정한다. 이 endpoint는 loopback HTTP 주소만 허용하며 mock은 텍스트 스트리밍 응답만 반환한다.

UI 없이 백엔드와 브리지만 실행합니다.

```powershell
corepack pnpm start:headless -- --project C:\path\to\project
```

Mock 또는 통합 환경에서 별도 브리지 주소를 사용하려면 `--bridge-socket <path>`를 추가합니다. 기본 주소는 Windows `\\.\pipe\PetAgent-bridge`, macOS `~/Library/Application Support/PetAgent/bridge.sock`입니다.

## 검증

```powershell
corepack pnpm check:architecture
corepack pnpm typecheck
corepack pnpm test
corepack pnpm build
corepack pnpm test:e2e
```

`check:architecture`는 import cycle, 계층 역참조, 임시 Mock 경계 확산, 과도하게 커진 진입 파일을 검사합니다. GitHub Actions는 architecture → typecheck → unit → build → E2E 순서로 실행하며, private protocol 의존성을 받기 위한 읽기 전용 `PROTOCOL_PAT` secret이 필요합니다.

패키징 명령은 다음과 같습니다.

```powershell
corepack pnpm package
corepack pnpm package:win
```

## 코드 구조

```text
src/
├─ main/
│  ├─ index.ts                    # 최소 Electron 진입점
│  ├─ app/                        # 조립, 라우팅, 창/종료 생명주기
│  ├─ *-controller.ts             # Electron/Workspace 조정자
│  └─ *-service.ts, *-store.ts    # 파일·설정·상태 인프라
├─ agent-host/                    # Utility Process, ACP Adapter, CodeEditorQueue
├─ renderer/
│  ├─ App.tsx                     # 편집 상태와 화면 조립
│  ├─ components/                 # 표현 컴포넌트
│  └─ gateway-*.ts                # WKWebView/EditorGateway 전송 계층
├─ shared/                        # 프로세스 공통 계약과 순수 유틸리티
└─ mocks/                         # 계약 테스트용 Mock 구현
packages/
└─ ai-module/                     # v6 Claude agent core (Workspace 통합본)
```

상세 프로세스와 데이터 흐름은 [docs/architecture.md](docs/architecture.md), 이번 마무리 분석은 [docs/codebase-refactor.md](docs/codebase-refactor.md), 남은 외부 의존 작업은 [TODO.md](TODO.md)를 참고하세요.

## 핵심 보안 규칙

- 프로젝트 경로는 `realpath`로 정규화하고 모든 파일 요청에서 루트 포함 여부를 재검증합니다.
- 저장은 `expectedRevision`이 현재 디스크 revision과 일치할 때만 허용합니다.
- BrowserWindow는 `contextIsolation`, `sandbox`를 사용하고 Node 통합을 비활성화합니다.
- Renderer와 로그에는 API 키 원문을 전달하지 않습니다.
- 첨부 파일은 허용된 임시 디렉터리, MIME, 크기, 실제 경로를 검증합니다.
- 현재 ACP 자식 프로세스는 cwd 경계만 사용하므로 OS 수준 파일시스템 샌드박싱은 출시 전 P1 보안 과제입니다.
