# Speaki-e Workspace

PetAgent의 프로젝트 파일 편집과 Claude Agent ACP 실행을 담당하는 Electron 백엔드/폴백 에디터입니다. 이 저장소의 현재 구현은 Workspace 개발 기획서 v2 중 **이주한 담당 영역**을 대상으로 합니다.

## 구현 범위

- Electron Main 및 보안 preload
- Agent Host Utility Process와 비정상 종료 후 재시작
- Monaco Editor, 파일 트리, 다중 탭, 외부 변경 알림
- 프로젝트 경계·심볼릭 링크를 검증하는 FileService
- revision 충돌 검사와 임시 파일 기반 원자적 저장
- 공식 ACP TypeScript SDK 기반 Claude Agent ACP Adapter
- 워크스페이스별 직렬 `CodeEditorQueue`
- UDS/Windows Named Pipe 기반 `PetBridge`
- 프로젝트 선택, 한 줄 명령, 실행 취소를 제공하는 폴백 셸
- Electron `safeStorage` 기반 Claude API 키 저장
- JSON Lines 로그와 Mock 계약 테스트

`EditorGateway`, 통합 Editor View 통신, `SessionRouter`, `RunRegistry`, 승인 브리지, diff, 설정 화면과 실제 `ai-module` 결합은 김민영 담당 영역이므로 포트와 메시지 경계만 제공하며 구현하지 않습니다.

## 요구 환경

- Node.js 22 이상
- pnpm 11.18.0 (`corepack enable` 권장)
- Claude API 키 또는 Claude Agent ACP가 사용할 수 있는 인증 환경

## 개발 실행

```powershell
corepack pnpm install
$env:ANTHROPIC_API_KEY = "키"
corepack pnpm start -- --project C:\path\to\project
```

처음 전달된 `ANTHROPIC_API_KEY`는 운영체제 암호화 기능을 사용할 수 있을 때 `safeStorage`로 암호화해 사용자 데이터 디렉터리에 저장됩니다. Renderer, Editor View 및 로그에는 원문 키를 전달하지 않습니다. 환경 변수를 사용하지 않으면 Claude Agent ACP 자체의 인증 방식도 사용할 수 있습니다.

UI 없이 Main과 브리지만 실행하려면 다음 명령을 사용합니다.

```powershell
corepack pnpm start:headless -- --project C:\path\to\project
```

별도 소켓을 사용하는 Mock 또는 통합 환경에서는 `--bridge-socket <path>`를 추가합니다. Windows 기본값은 `\\.\pipe\PetAgent-bridge`, macOS 기본값은 `~/Library/Application Support/PetAgent/bridge.sock`입니다.

## 검증과 패키징

```powershell
corepack pnpm typecheck
corepack pnpm test
corepack pnpm build
corepack pnpm test:e2e
corepack pnpm package
```

단위 테스트는 경로 이탈, 바이너리·대용량 파일, revision 충돌, JSON Lines 분할 수신, PetBridge 연결 종료, ACP Mock 왕복, 같은 워크스페이스의 직렬 큐와 대기 취소를 포함합니다. Playwright 테스트는 폴백 창과 격리된 preload를 실제 Electron에서 확인합니다.

## 보안 및 파일 규칙

- 모든 프로젝트 경로는 `realpath`로 정규화합니다.
- 읽기와 저장 시 루트 내부 경로인지 다시 검증하며 심볼릭 링크 이탈을 거부합니다.
- 2MB 초과 텍스트는 읽기 전용이고 바이너리는 편집하지 않습니다.
- 저장 시 `expectedRevision`이 현재 디스크 revision과 다르면 `file_conflict`를 반환합니다.
- 저장 내용은 같은 디렉터리의 임시 파일에 쓴 뒤 교체합니다.
- BrowserWindow는 `contextIsolation: true`, `nodeIntegration: false`, `sandbox: true`로 실행합니다.
- ACP 자식 프로세스에는 필요한 최소 환경 변수만 전달합니다.

## 통합 경계

공통 타입은 `src/shared`에 있습니다. `ports.ts`의 `AgentRuntime`, `ApprovalPort`, `SessionRouterPort`, `RunRegistryPort`가 후속 통합 지점입니다. 기획서가 권장하지만 protocol v0.5.0에 아직 없는 `state_snapshot_request`와 확장 `run_cancel`은 `protocol-extensions.ts`에 타입만 두었고 wire 전송은 비활성화했습니다. protocol 저장소의 계약이 배포된 뒤 플래그와 실제 브리지를 함께 갱신해야 합니다.

자세한 구성은 [docs/architecture.md](docs/architecture.md)를 참고하세요.
