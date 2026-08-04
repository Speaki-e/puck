# 개인정보·API 키·프로젝트 경로 로그 정책 리뷰

TODO.md W7/공통 "개인정보·API 키·프로젝트 경로 로그 정책 리뷰" 항목의 산출물이다. `src/main/logger.ts`의
`REDACTED_KEYS`(`apiKey`, `api_key`, `authorization`, `content`, `token`)를 기준으로, 실제로 로그에
찍히는 모든 `logger.write(...)` 호출부(`src/main/*.ts`, `src/agent-host/*.ts`)를 전수 확인했다.
`REDACTED_KEYS`는 **키 이름** 기준으로 마스킹하므로, `projectPath`/`path`/`socketPath`처럼 값 자체가
디버깅에 필요해 마스킹할 수 없는 필드에 절대경로가 그대로 들어가는 경우는 못 잡는다는 게 이번에
확인한 핵심 문제였다.

## 무엇을 확인했나

`grep -rn "logger.write"` 로 찾은 모든 호출부(약 25곳)를 하나씩 열어 두 번째 인자(`kind`)와 세 번째
인자(`data`)에 절대경로·홈 디렉터리·사용자명이 들어갈 수 있는지 확인했다.

## 무엇을 고쳤나 (실제 유출 3건)

| 위치 | 로그 kind | 문제 | 조치 |
|---|---|---|---|
| `workspace-controller.ts`의 `bindDefault` | `workspace_project_bound` | `record.realProjectPath`를 절대경로 그대로 기록 -- Windows에서 `C:\Users\<user>\...`, macOS에서 `/Users/<user>/...` 형태로 OS 사용자명이 로그에 남는다 | `basenameForLog()`로 마지막 세그먼트만 기록 |
| `attachment-validator.ts`의 `filterValidAttachments` catch 블록 | `attachment_rejected` | 거부된 첨부의 절대경로(`attachment.path`)를 그대로 기록 -- OS 임시 디렉터리 하위 경로라 여기도 사용자 홈 디렉터리가 포함된다 | 동일하게 `basenameForLog()` 적용 |
| `pet-bridge.ts`의 `openSocket` 연결 성공 핸들러 | `pet_bridge_connected` | `defaultBridgeSocketPath()`가 macOS에서 `os.homedir()` 하위 경로(`~/Library/Application Support/PetAgent/bridge.sock`)를 반환 -- 연결될 때마다 로그에 홈 디렉터리가 남는다(Windows named pipe 경로는 홈 디렉터리를 포함하지 않아 원래도 안전했지만 일관성을 위해 동일 처리) | 동일하게 `basenameForLog()` 적용 |

세 곳 모두 `logger.ts`에 새로 추가한 `basenameForLog(absolutePath)` 헬퍼(내부적으로
`path.basename`)를 재사용한다. `REDACTED_KEYS`에 항목을 추가하는 대신 헬퍼를 택한 이유: 이 필드들은
"어떤 프로젝트/파일/소켓인지" 자체가 디버깅에 필요한 정보라 완전 마스킹(`[REDACTED]`)하면 로그의
쓸모가 없어진다. 마지막 세그먼트(파일/폴더 이름)만 남기면 같은 프로젝트를 가리키는 로그 라인을 계속
구분할 수 있으면서 상위 경로(홈 디렉터리, 사용자명)는 로그에서 사라진다.

검증: `logger.test.ts`에 `basenameForLog` 단위 테스트 추가(홈 디렉터리 문자열이 결과에 포함되지
않는지 확인). `attachment-validator.test.ts`의 기존 `attachment_rejected` 검증은 `code` 필드만
확인하므로 이번 변경으로 깨지지 않았다.

## 확인했지만 고치지 않은 것 (범위 밖으로 판단)

- `file_saved`(`workspace-controller.ts`)의 `path` 필드: `FileService`가 이미 프로젝트 루트 기준
  상대경로(`relativeForWire`)로 변환한 값이라 원래도 절대경로가 아니다 -- 문제 없음.
- `pet-bridge.ts`의 `invalid_protocol_message` 로그가 검증 실패한 원본 메시지 전체(`value`)를 그대로
  남기는 것: `redact()`가 `REDACTED_KEYS`에 있는 키(`content`, `token` 등)는 중첩 객체까지 재귀적으로
  가리므로 흔한 경우는 막히지만, 예를 들어 잘못된 형식의 `user_input.attachments[].path`처럼 임의
  위치에 경로 문자열이 들어있으면 새어나갈 수 있다. 이 메시지는 프로토콜 위반을 진단하는 목적으로
  원본 그대로 남겨야 쓸모가 있고, pet-app이 신뢰할 수 있는 로컬 프로세스라는 전제(같은 사용자 세션)
  아래에서는 위험도가 낮다고 판단해 이번 라운드에서는 손대지 않았다. 일반화된 재귀 경로 마스킹이
  필요해지면(예: 첨부 인터페이스가 pet-app 외부로 열리는 시점) 별도 항목으로 다시 볼 것.
- `agent_run_failed`/`bridge_message_route_failed` 등 `error.message`를 그대로 기록하는 곳들:
  Node의 파일시스템 에러(`ENOENT` 등)는 메시지 안에 절대경로를 포함하는 경우가 있다. 이건 이
  코드베이스 전반의 에러 처리 패턴이라 로그 정책 리뷰 범위에서 개별적으로 다 고치기보다, 에러 메시지
  자체를 프로젝트 상대경로로 만드는 상위 설계(예: `FileServiceError`처럼 도메인 에러로 감싸 원본 fs
  에러를 로그에 노출하지 않는 것)가 필요하다고 보고 문서화만 해둔다. 지금 남아있는 개별 사례들은
  대부분 이미 `FileServiceError`/`EditorGatewayRequestError`처럼 구조화된 에러를 쓰고 있어 실제
  노출 빈도는 낮다.
- API 키: `settings-controller.ts`가 값 자체를 로그에 아예 넘기지 않는 것을 이미 확인(주석에도 명시돼
  있음) -- `REDACTED_KEYS`와 별개의 이중 방어가 이미 되어 있어 추가 조치 없음.

## 결론

`REDACTED_KEYS`는 키 이름 기준 마스킹만 하므로, "값 자체가 경로인데 그 값이 필요한" 필드는 별도
헬퍼(`basenameForLog`)로 다뤄야 한다는 게 이번 리뷰의 결론이다. 발견된 3건은 모두 수정했고, 나머지는
범위/설계상 이유로 이번 라운드에서 남겨둔 채 위에 근거를 적어뒀다.
