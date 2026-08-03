import { lstat, readFile, realpath, stat } from "node:fs/promises";
import path from "node:path";
import type { Attachment } from "@speaki-e/protocol";
import { detectImageMime, IMAGE_EXTENSION_MIME } from "../shared/image-mime.js";
import { isPathInsideAny } from "../shared/path-containment.js";
import type { JsonlLogger } from "./logger.js";

export type AttachmentErrorCode =
  | "invalid_attachment"
  | "unsupported_extension"
  | "mime_mismatch"
  | "file_too_large"
  | "file_not_found"
  | "path_not_allowed"
  | "symlink_escape";

export class AttachmentValidationError extends Error {
  constructor(
    readonly code: AttachmentErrorCode,
    message: string,
  ) {
    super(message);
    this.name = "AttachmentValidationError";
  }
}

export interface AttachmentPolicy {
  /** 첨부의 realpath가 이 디렉터리들(모두 realpath 기준) 중 하나 안에 있어야 한다 -- 기본은 OS 임시 디렉터리. */
  allowedDirectories: readonly string[];
  /** 사용자가 파일 선택 대화상자로 명시적으로 고른 개별 경로(디렉터리 제한과 별도로 허용, 원본/realpath 둘 다 확인). */
  allowedPaths?: ReadonlySet<string>;
  maxBytes?: number;
}

export const DEFAULT_MAX_ATTACHMENT_BYTES = 10 * 1024 * 1024;

export interface ValidatedAttachment {
  path: string;
  mimeType: string;
  size: number;
}

/**
 * pet-app이 user_input.attachments(드래그 캡처 등, plan/01_protocol.md 3.3)로 실어 보내는 로컬 파일
 * 경로는 신뢰할 수 없는 입력이다 -- 확장자 위조, 존재하지 않는 경로, 허용 범위 밖 경로, 심볼릭 링크로
 * 위장한 경로 이탈을 전부 가려낸다. file-service.ts의 경로 이탈/심볼릭 링크 차단 로직(isInside)과
 * 이미지 매직 바이트 판별 로직을 shared/path-containment.ts, shared/image-mime.ts로 뽑아 재사용한다.
 */
export async function validateAttachment(attachment: Attachment, policy: AttachmentPolicy): Promise<ValidatedAttachment> {
  if (!attachment || attachment.type !== "image" || typeof attachment.path !== "string" || !attachment.path) {
    throw new AttachmentValidationError("invalid_attachment", "지원하지 않는 첨부 형식입니다");
  }
  if (attachment.path.includes("\0")) {
    throw new AttachmentValidationError("invalid_attachment", "잘못된 파일 경로입니다");
  }

  const expectedMime = IMAGE_EXTENSION_MIME.get(path.extname(attachment.path).toLowerCase());
  if (!expectedMime) {
    throw new AttachmentValidationError("unsupported_extension", `지원하지 않는 확장자입니다: ${path.extname(attachment.path) || "(없음)"}`);
  }

  const absolute = path.resolve(attachment.path);
  let real: string;
  try {
    real = await realpath(absolute);
  } catch (error) {
    if ((error as NodeJS.ErrnoException).code === "ENOENT") {
      throw new AttachmentValidationError("file_not_found", "첨부 파일을 찾을 수 없습니다");
    }
    throw error;
  }

  const allowedByPath = policy.allowedPaths?.has(absolute) || policy.allowedPaths?.has(real);
  if (!allowedByPath && !isPathInsideAny(real, policy.allowedDirectories)) {
    // realpath 기준으로 판단하므로, 허용된 임시 디렉터리 안에 있는 심볼릭 링크가 바깥 파일을
    // 가리키는 이탈도 여기서 함께 걸린다 -- lstat으로 원본이 심볼릭 링크였는지만 구분해 에러 코드를 나눈다.
    const info = await lstat(absolute).catch(() => undefined);
    const code = info?.isSymbolicLink() ? "symlink_escape" : "path_not_allowed";
    throw new AttachmentValidationError(code, "허용되지 않은 경로의 첨부입니다");
  }

  const metadata = await stat(real);
  if (!metadata.isFile()) {
    throw new AttachmentValidationError("invalid_attachment", "파일이 아닙니다");
  }
  const maxBytes = policy.maxBytes ?? DEFAULT_MAX_ATTACHMENT_BYTES;
  if (metadata.size > maxBytes) {
    throw new AttachmentValidationError("file_too_large", `첨부 파일이 최대 크기(${maxBytes} bytes)를 초과합니다`);
  }

  const buffer = await readFile(real);
  const detectedMime = detectImageMime(buffer);
  if (!detectedMime || detectedMime !== expectedMime) {
    throw new AttachmentValidationError("mime_mismatch", "확장자와 실제 파일 내용이 일치하지 않습니다");
  }

  return { path: real, mimeType: detectedMime, size: metadata.size };
}

/**
 * 첨부 목록을 검증해 통과한 것만 남긴다. 첨부 하나가 거부됐다고 나머지 정상 첨부나 본문 텍스트까지
 * 막을 이유는 없어(사용자 입력 자체는 유효할 수 있음) 개별 필터링 후 로깅만 한다.
 */
export async function filterValidAttachments(
  attachments: Attachment[] | undefined,
  policy: AttachmentPolicy,
  logger: Pick<JsonlLogger, "write">,
): Promise<Attachment[]> {
  if (!attachments?.length) return [];
  const kept: Attachment[] = [];
  for (const attachment of attachments) {
    try {
      const validated = await validateAttachment(attachment, policy);
      kept.push({ ...attachment, path: validated.path });
    } catch (error) {
      if (!(error instanceof AttachmentValidationError)) throw error;
      await logger.write("warn", "attachment_rejected", { code: error.code, path: attachment?.path });
    }
  }
  return kept;
}
