> **폐기 — 2026-08-12.** 이 모듈은 착수되지 못한 채 puck 모노레포로 통합됐다. 에이전트 코어 역할은
> pet-app의 F15 두뇌(`pet-app/Puck/Agent/AgentRunner.swift`)가 정식으로 대신하며, workspace는
> `DirectCodeEditorRuntime`으로 code_editor 하나만 실행한다. 자세한 배경은 `../docs/decisions.md`,
> 설계 기록은 `../../plan/04_ai-module.md`(마찬가지로 폐기 표시됨) 참고. 아래는 원래 계획 문서다.

# Speaki-e ai-module

Puck의 에이전트 코어입니다. Anthropic Messages API 스트리밍과 tool-use 루프를 처리하고, 실행 자체는 호출자가 주입한 executor에 맡깁니다. UI·소켓·파일시스템을 직접 다루지 않습니다.

## 역할

```text
사용자 입력 → Claude 스트리밍 → tool_use → 승인/실행기 → tool_result → 완료 응답
```

- 세션별 대화 히스토리와 직렬 큐
- protocol 레지스트리 기반 도구 정의·입력 검증
- `pet-app`과 `workspace` executor 주입
- 승인 게이트와 `run_shell` 화이트리스트
- `open_task_session` 생성과 콜백 전달
- 이미지 첨부를 Anthropic 멀티모달 입력으로 변환

## 요구 사항

- Node.js 22+
- Anthropic API 키
- `@speaki-e/protocol` 계약 패키지

개발 중에는 Workspace에 포함된 `packages/ai-module`이 실제 실행 경로입니다. 이 저장소는 모듈과 CLI를 개발·검증하는 원본입니다.

## CLI

루트에 `.env`를 만들고 API 키를 설정합니다.

```text
ANTHROPIC_API_KEY=your-anthropic-api-key
ANTHROPIC_MODEL=claude-sonnet-4-6
```

단발 실행:

```powershell
npm install
npm run cli "사파리 켜줘"
```

대화형 REPL:

```powershell
npm run cli
```

도구 호출 순서를 JSON으로 확인하려면:

```powershell
npm run cli --seq "사파리 켜줘"
npm run cli --seq --approve=all "빌드 폴더 지워줘"
```

`--seq`는 stdout에 JSON 한 줄만 출력합니다. 사람이 읽는 로그는 stderr로 분리됩니다. 위험 도구는 기본적으로 거부하며, `--approve=all`을 명시한 경우에만 CLI에서 승인합니다.

## 공개 계약

```ts
run(command, sessionId, context, callbacks, attachments?, signal?)
```

호출자는 `onTextChunk`, `onToolCallStart`, `onToolResult`, `onApprovalRequired`, `onSessionCreated`, `onDone` 콜백과 `pet-app`·`workspace` executor를 제공해야 합니다. 타입과 도구 레지스트리의 정본은 `protocol`입니다.

## 검증과 배포

```powershell
npm run typecheck
npm run build
```

인터페이스가 바뀌면 minor 이상 태그를 발행하고, Workspace 통합 시에도 같은 태그를 기록합니다. 상세 설계·케이스 표·협업 규칙은 [전체 기획서](../plan/04_ai-module.md)를 참고하세요.

