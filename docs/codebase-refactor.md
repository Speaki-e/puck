# Codebase 마무리 분석 및 리팩터링

기준: `plan-main/03_workspace.md`, `workspace-main/TODO.md`, `main` 브랜치 `1123372`

## 분석 결과

리팩터링 전 소스는 51개 비테스트 모듈과 95개 내부 import로 구성됐고 import cycle은 없었습니다. 핵심 문제는 순환 참조가 아니라 책임 집중과 문서 불일치였습니다.

| 영역 | 발견 사항 | 영향 | 처리 |
|---|---|---|---|
| Main entry | `src/main/index.ts` 450줄에 CLI, 창, 저장소, Agent 이벤트, PetBridge, 종료가 결합 | 변경 영향 범위와 회귀 위험 증가 | `src/main/app` 6개 경계 모듈로 분리, entry 7줄로 축소 |
| Renderer | `App.tsx` 524줄에 Monaco 설정과 전체 표현 UI 포함 | 상태 로직과 표현 변경이 충돌 | 주요 화면 컴포넌트와 Monaco 설정 분리, 347줄로 축소 |
| CI | TODO에는 완료지만 `.github/workflows/ci.yml`이 최신 트리에 없음 | main 병합 전 자동 검증 부재 | private protocol 인증을 포함해 워크플로 복구 |
| 구조 규칙 | 타입 검사 외에 계층/순환 검증 없음 | 시간이 지나며 경계 재붕괴 가능 | 무의존성 architecture check 추가 |
| 문서 | README가 EditorGateway, SessionRouter 등을 미구현으로 설명 | 신규 개발자의 잘못된 판단 | 현재 구현과 임시 ai-module 경계 기준으로 갱신 |

## 적용한 구조

```text
src/main/index.ts
  └─ app/workspace-application.ts
       ├─ runtime-options.ts
       ├─ fallback-window.ts
       ├─ agent-runtime-coordinator.ts
       ├─ pet-bridge-router.ts
       └─ test-hooks.ts
```

- `workspace-application`은 객체 생성 순서와 종료 순서만 소유합니다.
- `agent-runtime-coordinator`는 실제 ai-module 도입 전의 임시 Main AI 경계를 한곳에 제한합니다.
- `pet-bridge-router`는 wire 메시지를 application 명령으로 변환합니다.
- `fallback-window`는 BrowserWindow와 창 상태 복구만 담당합니다.
- CLI 파싱은 Electron 전역에 의존하지 않는 순수 함수로 만들고 단위 테스트를 추가했습니다.

Renderer는 `WorkspaceTitlebar`, `EditorSurface`, `CommandDock`, `Icon`, `monaco-config`를 분리했습니다. 기존 상태 reducer, 저장, 충돌, 초안 복구 동작은 변경하지 않았습니다.

## 성능 관점

이번 브랜치는 동작을 바꾸는 최적화보다 병목을 분리해 이후 측정 가능한 형태로 만드는 데 집중했습니다.

- 파일 트리는 기존 제외 정책과 벤치마크를 유지합니다. 매우 큰 저장소는 디렉터리 lazy loading과 응답 상한이 다음 단계입니다.
- EditorGateway는 단일 서버/워크스페이스별 연결 집합 구조를 유지합니다. 메시지 런타임 검증을 추가할 때 hot path의 JSON parsing 비용을 함께 측정해야 합니다.
- AI 실행 객체 생성과 이벤트 라우팅이 coordinator에 모여, 실제 ai-module 도입 후 Main ↔ Agent Host RPC 비용과 세션 큐를 독립적으로 측정할 수 있습니다.
- Renderer의 표현 컴포넌트 분리는 React 상태 effect를 건드리지 않아 성능 회귀 위험을 낮췄습니다. 다음 최적화는 큰 파일 트리의 가상화가 우선입니다.

## 출시 전 차단 항목

1. 실제 태그 버전 ai-module 연결과 Agent Host 소유 경계 확정
2. protocol의 request_id/state_snapshot/run_id 계약 배포
3. ACP 자식 프로세스의 워크스페이스 외부 파일 쓰기 차단
4. 실제 Claude 인증과 pet-app WKWebView/bridge.sock 전체 왕복
5. macOS 패키징, 서명 정책, 장시간 재연결 검증

세부 체크리스트와 담당 항목은 루트 `TODO.md`에 유지합니다.
