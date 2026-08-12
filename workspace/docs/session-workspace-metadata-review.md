# 세션·워크스페이스 메타데이터 저장 형식 리뷰

TODO.md W3/공통 "세션·워크스페이스 메타데이터 저장 형식 리뷰" 항목의 산출물이다. 코드 변경 없이
현재 두 레지스트리의 저장 형식·책임 경계를 정리하고, 세션이 영속화 대상이 될 때(state_snapshot
작업 시작 시, W4 공통) 무엇을 바꿔야 하는지 미리 적어둔다.

## 현재 상태

| | `WorkspaceRegistry` (`src/main/workspace-registry.ts`) | `SessionRegistry` (`src/main/session-registry.ts`) |
|---|---|---|
| 저장 위치 | `userData/workspaces.json` (디스크, 영속) | 프로세스 메모리의 `Map` (비영속) |
| 쓰기 방식 | 임시 파일 작성 후 `rename`(원자적), `version: 1` 스키마 필드 있음 | 없음 — 항상 최신 상태만 메모리에 존재 |
| 레코드 | `id, name, projectPath, realProjectPath, createdAt, updatedAt` | `id, workspaceId, title, origin(user\|agent), createdAt` |
| 생성 계기 | 앱 시작 시 프로젝트 바인딩, `workspace_create_request`(W4) | `session_create_request`(origin=user), `open_task_session`(origin=agent, W6) |
| 재시작 후 | 그대로 복원(`default` 워크스페이스는 항상 보장) | 전부 소실 — 재시작하면 세션 목록이 빈 상태로 시작 |
| 삭제 | `remove(id)` 있음(`default`는 보호) | 삭제 API 자체가 없음 — 워크스페이스가 삭제돼도 그 워크스페이스의 세션 레코드는 메모리에 그대로 남는다(고아 레코드, 아래 참고) |

`SessionRegistry`의 docstring이 이미 명시하듯, 이 클래스는 임시 어댑터다: 진짜 대화 히스토리
레지스트리는 ai-module이 소유해야 하고(plan/04_ai-module.md 3.4 "sessionId로 keyed된 멀티 세션
메모리" — 대화 내용/히스토리, "로컬 저장은 후순위"), Workspace의 `SessionRegistry`는 그것과는
다른, 더 좁은 책임만 진다: pet-app에 `session_create` 이벤트를 확정 응답하고 사이드바에 표시할
`title`/`origin`/`workspaceId` 메타데이터만 기억한다. **대화 내용 자체는 여기 없다** — ai-module이
없는 지금은 아예 어디에도 저장되지 않는다(MockAgentRuntime은 상태가 없다).

## 책임 경계가 이렇게 나뉜 이유

- `WorkspaceRegistry`는 "이 컴퓨터에 어떤 프로젝트/워크스페이스가 있고 그 프로젝트 폴더가
  어디인지"를 기억해야 한다 — 사용자가 다음날 앱을 다시 켰을 때 프로젝트를 다시 찾아 여는 걸
  전제로 하므로 영속화가 필수다.
- `SessionRegistry`는 "지금 이 프로세스가 살아있는 동안 pet-app에 어떤 세션들을 통지했는지"만
  기억하면 충분했다 — 지금까지는 세션 자체가 재시작 후 복원 대상이 아니었기 때문이다(TODO.md
  W4 공통의 `state_snapshot`이 아직 없다 — protocol PR 대기).

이 경계는 앞으로 두 가지 서로 다른 이유로 깨질 수 있다: (1) Workspace가 재시작 후 세션 목록을
복원해야 하는 요구(state_snapshot), (2) ai-module이 실제로 붙어 대화 히스토리를 갖게 되는 것.
둘은 별개의 사건이고, 아래는 그 각각이 왔을 때 무엇을 바꿔야 하는지다.

## state_snapshot(재시작 복원)이 시작될 때 바꿔야 할 것

1. **영속화 여부 결정**: `SessionRegistry`도 `WorkspaceRegistry`처럼 디스크에 쓸지, 아니면
   PuckClient가 재연결할 때마다 "이번 프로세스가 아는 세션"만 스냅샷으로 보내고 pet-app이
   자기 쪽 히스토리를 소스 오브 트루스로 삼을지 먼저 정해야 한다. 후자라면 `SessionRegistry`는
   지금 형태 그대로도 충분할 수 있다 — snapshot 생성 시점의 스냅샷일 뿐 영속화가 필요 없어진다.
2. **영속화하기로 하면** `WorkspaceRegistry`와 같은 패턴(임시 파일 + `rename`, `version` 필드)을
   그대로 재사용한다 — 이미 검증된 원자적 쓰기 로직이 있으니 새로 설계할 필요는 없다.
3. **고아 레코드 정리**: 지금은 `WorkspaceRegistry.remove(id)`가 그 워크스페이스의 세션들을
   전혀 정리하지 않는다(cascade 없음) — 메모리에서는 눈에 안 띄지만, 영속화하는 순간 디스크에
   고아 레코드가 영원히 남는 문제가 된다. 영속화 작업과 함께 `WorkspaceRegistry.remove`가
   `SessionRegistry`에도 알리도록(또는 반대로 세션 쪽에서 워크스페이스 존재 여부를 주기적으로
   검증하도록) 연결해야 한다.
4. **개수 상한/보존 정책**: 지금은 세션이 늘어나기만 하고 지워지는 경로가 없다(`SessionRegistry`에
   삭제 API 자체가 없음). 영속화하면 무한정 쌓이는 문제가 실제 디스크 사용량 문제가 되므로,
   보존 기간이나 워크스페이스당 최대 개수 같은 정책이 필요하다.
5. **스냅샷 API 형태 맞추기**: `WorkspaceRegistry.list()`처럼 스냅샷 생성용 읽기 API
   (`listForWorkspace`는 이미 있음)를 W4의 `state_snapshot` 페이로드 형식에 맞게 다시 봐야 한다.

## ai-module이 실제로 붙을 때 바꿔야 할 것

- ai-module이 자기 자신의 세션별 히스토리 레지스트리(대화 내용)를 갖게 되면, `title`/`origin`
  같은 메타데이터도 결국 ai-module 쪽 레지스트리의 부분집합이 될 가능성이 있다 — 그렇다면
  Workspace의 `SessionRegistry`는 "진짜 저장소"가 아니라 ai-module 쪽 데이터를 조회해 pet-app
  wire 형식으로 얇게 변환하는 어댑터로 바뀌어야 한다(`session-registry.ts` docstring에 이미
  예견돼 있음). **이중 저장(double bookkeeping)을 피하려면, ai-module 태그가 나온 시점에
  "메타데이터를 Workspace가 계속 들고 있을지 vs ai-module에서 매번 조회할지"부터 다시 결정해야
  한다** — state_snapshot 작업을 그 전에 먼저 해버리면 이 결정을 두 번 하게 될 수 있으니,
  두 작업의 순서(ai-module 연결이 먼저 오는지, state_snapshot이 먼저 오는지)에 따라 위 3~5번의
  설계가 폐기될 수 있다는 점을 감안해야 한다.

## 지금 당장 바꾸지 않는 이유

이번 라운드에서는 코드를 바꾸지 않았다 — 영속화 형식과 정책은 protocol PR(`state_snapshot`)의
정확한 페이로드 계약이 먼저 나와야 확정할 수 있고, 그 전에 임의로 설계하면 W4 공통 작업이
끝났을 때 다시 갈아엎을 가능성이 크다(이미 TODO.md에 여러 차례 기록된 "protocol PR 대기" 패턴과
동일). 이 문서는 그 결정이 내려질 때 참고할 체크리스트로 남겨둔다.
