# Speaki-e Workspace

Puck의 로컬 워크스페이스 앱입니다. Monaco 에디터, 프로젝트 파일 관리, PetBridge, Claude Agent ACP와 `ai-module` 실행을 한 Electron 앱 안에서 연결합니다.

## 구성

```text
PuckClient ── PetBridge ── Workspace ── ai-module ── Claude API
                                  │
                                  └── Claude Agent ACP ── 프로젝트 파일
```

- **Main process**: 파일·세션·설정·브리지·앱 생명주기
- **Agent Host**: Claude Agent ACP와 코딩 작업 큐
- **EditorGateway**: Electron 창과 WKWebView가 공유하는 Editor View
- **ai-module**: 스트리밍, tool-use, 승인, 세션 히스토리를 담당하는 에이전트 코어

## 요구 사항

- Node.js 22+
- pnpm 11.18.0 (`corepack enable` 권장)
- Anthropic API 키
- private `Speaki-e/protocol` 저장소 읽기 권한

## 시작

```powershell
corepack pnpm install
$env:ANTHROPIC_API_KEY = "your-anthropic-api-key"
corepack pnpm start -- --project C:\path\to\project
```

UI 없이 브리지와 백엔드만 실행하려면 다음을 사용합니다.

```powershell
corepack pnpm start:headless -- --project C:\path\to\project
```

기본 PetBridge 주소는 Windows `\\.\pipe\Puck-bridge`, macOS `~/Library/Application Support/Puck/bridge.sock`입니다. 다른 주소가 필요하면 `--bridge-socket <path>`를 추가하세요.

## 검증

```powershell
corepack pnpm check
corepack pnpm test:e2e
```

`check`는 아키텍처 검사, 타입 검사, 단위 테스트, 프로덕션 빌드를 순서대로 실행합니다. E2E는 Electron·EditorGateway·PetBridge 계약을 검증합니다.

```powershell
corepack pnpm package
corepack pnpm package:win
```

## 보안 경계

- 모든 파일 경로는 `realpath` 기준으로 워크스페이스 루트 안인지 확인합니다.
- 저장은 revision 충돌 검사를 통과해야 합니다.
- API 키는 `safeStorage`에 보관하며 Renderer·로그에 원문을 전달하지 않습니다.
- 첨부 파일은 허용 경로, MIME, 크기, 실제 경로를 검증합니다.
- ACP 자식 프로세스의 OS 수준 파일시스템 샌드박싱은 아직 P1 과제입니다.

## 문서

- [아키텍처](docs/architecture.md)
- [프로토콜 호환성](docs/protocol-compatibility-matrix.md)
- [남은 외부 의존 작업](TODO.md)
- [전체 프로젝트 계획](../plan/프로젝트_개요.md)

