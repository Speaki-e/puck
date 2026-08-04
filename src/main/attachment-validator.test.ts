import { mkdtemp, realpath, symlink, writeFile } from "node:fs/promises";
import os from "node:os";
import path from "node:path";
import { describe, expect, it } from "vitest";
import type { Attachment } from "@speaki-e/protocol";
import { filterValidAttachments, validateAttachment, type AttachmentPolicy } from "./attachment-validator.js";

const PNG_1PX = Buffer.from(
  "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNk+A8AAQUBAScY42YAAAAASUVORK5CYII=",
  "base64",
);

async function tempDir(prefix: string): Promise<string> {
  return realpath(await mkdtemp(path.join(os.tmpdir(), prefix)));
}

function imageAttachment(filePath: string): Attachment {
  return { type: "image", path: filePath };
}

describe("validateAttachment", () => {
  it("허용된 디렉터리 안의 진짜 PNG는 통과한다", async () => {
    const dir = await tempDir("attach-ok-");
    const file = path.join(dir, "capture.png");
    await writeFile(file, PNG_1PX);
    const policy: AttachmentPolicy = { allowedDirectories: [dir] };
    await expect(validateAttachment(imageAttachment(file), policy)).resolves.toMatchObject({
      mimeType: "image/png",
      size: PNG_1PX.byteLength,
    });
  });

  it("지원하지 않는 확장자를 거부한다", async () => {
    const dir = await tempDir("attach-ext-");
    const file = path.join(dir, "capture.txt");
    await writeFile(file, PNG_1PX);
    const policy: AttachmentPolicy = { allowedDirectories: [dir] };
    await expect(validateAttachment(imageAttachment(file), policy)).rejects.toMatchObject({ code: "unsupported_extension" });
  });

  it("확장자와 실제 파일 내용이 다른 위조 MIME을 거부한다", async () => {
    const dir = await tempDir("attach-mime-");
    const file = path.join(dir, "capture.png");
    await writeFile(file, "이건 이미지가 아니라 평범한 텍스트입니다", "utf8");
    const policy: AttachmentPolicy = { allowedDirectories: [dir] };
    await expect(validateAttachment(imageAttachment(file), policy)).rejects.toMatchObject({ code: "mime_mismatch" });
  });

  it("최대 크기를 초과한 첨부를 거부한다", async () => {
    const dir = await tempDir("attach-size-");
    const file = path.join(dir, "capture.png");
    await writeFile(file, PNG_1PX);
    const policy: AttachmentPolicy = { allowedDirectories: [dir], maxBytes: PNG_1PX.byteLength - 1 };
    await expect(validateAttachment(imageAttachment(file), policy)).rejects.toMatchObject({ code: "file_too_large" });
  });

  it("존재하지 않는 첨부 파일을 거부한다", async () => {
    const dir = await tempDir("attach-missing-");
    const file = path.join(dir, "missing.png");
    const policy: AttachmentPolicy = { allowedDirectories: [dir] };
    await expect(validateAttachment(imageAttachment(file), policy)).rejects.toMatchObject({ code: "file_not_found" });
  });

  it("허용된 디렉터리 밖의 첨부 경로를 거부한다", async () => {
    const allowedDir = await tempDir("attach-allowed-");
    const outsideDir = await tempDir("attach-outside-");
    const file = path.join(outsideDir, "capture.png");
    await writeFile(file, PNG_1PX);
    const policy: AttachmentPolicy = { allowedDirectories: [allowedDir] };
    await expect(validateAttachment(imageAttachment(file), policy)).rejects.toMatchObject({ code: "path_not_allowed" });
  });

  it("사용자가 명시적으로 선택한 개별 경로는 디렉터리 제한과 무관하게 허용한다", async () => {
    const allowedDir = await tempDir("attach-allowed2-");
    const outsideDir = await tempDir("attach-outside2-");
    const file = path.join(outsideDir, "capture.png");
    await writeFile(file, PNG_1PX);
    const policy: AttachmentPolicy = { allowedDirectories: [allowedDir], allowedPaths: new Set([file]) };
    await expect(validateAttachment(imageAttachment(file), policy)).resolves.toMatchObject({ mimeType: "image/png" });
  });

  it("허용 디렉터리 안의 심볼릭 링크가 바깥 파일을 가리키면 거부한다", async () => {
    const allowedDir = await tempDir("attach-symlink-allowed-");
    const outsideDir = await tempDir("attach-symlink-outside-");
    const target = path.join(outsideDir, "secret.png");
    await writeFile(target, PNG_1PX);
    const link = path.join(allowedDir, "capture.png");
    try {
      await symlink(target, link, "file");
    } catch (error) {
      // Windows에서 개발자 모드/관리자 권한이 없으면 심볼릭 링크 생성 자체가 EPERM으로 막힌다 --
      // 이 환경 제약 때문에 이 테스트만 건너뛴다(정책 로직 자체는 위 "허용 디렉터리 밖" 테스트로 검증됨).
      console.warn(`심볼릭 링크 생성 권한이 없어 이 테스트를 건너뜁니다: ${(error as Error).message}`);
      return;
    }
    const policy: AttachmentPolicy = { allowedDirectories: [allowedDir] };
    await expect(validateAttachment(imageAttachment(link), policy)).rejects.toMatchObject({ code: "symlink_escape" });
  });

  it("지원하지 않는 첨부 type과 빈 경로를 거부한다", async () => {
    const dir = await tempDir("attach-invalid-");
    const policy: AttachmentPolicy = { allowedDirectories: [dir] };
    await expect(validateAttachment({ type: "video" as never, path: "x.png" }, policy)).rejects.toMatchObject({
      code: "invalid_attachment",
    });
    await expect(validateAttachment({ type: "image", path: "" }, policy)).rejects.toMatchObject({ code: "invalid_attachment" });
  });
});

describe("filterValidAttachments", () => {
  it("유효한 첨부만 남기고 거부된 첨부는 경고로 로깅한다", async () => {
    const dir = await tempDir("attach-filter-");
    const good = path.join(dir, "good.png");
    await writeFile(good, PNG_1PX);
    const bad = path.join(dir, "bad.txt");
    await writeFile(bad, "not an image", "utf8");

    const logged: Array<{ level: string; kind: string; data: Record<string, unknown> }> = [];
    const logger = {
      write: async (level: "debug" | "info" | "warn" | "error", kind: string, data: Record<string, unknown> = {}) => {
        logged.push({ level, kind, data });
      },
    };
    const policy: AttachmentPolicy = { allowedDirectories: [dir] };
    const kept = await filterValidAttachments([imageAttachment(good), imageAttachment(bad)], policy, logger);

    expect(kept).toHaveLength(1);
    expect(kept[0]?.path).toBe(good);
    expect(logged).toHaveLength(1);
    expect(logged[0]).toMatchObject({ level: "warn", kind: "attachment_rejected", data: { code: "unsupported_extension" } });
  });

  it("첨부가 없으면 빈 배열을 반환한다", async () => {
    const dir = await tempDir("attach-empty-");
    const policy: AttachmentPolicy = { allowedDirectories: [dir] };
    const logger = { write: async () => undefined };
    await expect(filterValidAttachments(undefined, policy, logger)).resolves.toEqual([]);
  });
});
