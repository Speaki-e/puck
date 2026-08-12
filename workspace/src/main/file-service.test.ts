import { mkdtemp, mkdir, readFile, writeFile } from "node:fs/promises";
import os from "node:os";
import path from "node:path";
import { describe, expect, it } from "vitest";
import { FileService } from "./file-service.js";
import { FileServiceError } from "../shared/file-contract.js";

async function fixture(): Promise<{ root: string; service: FileService }> {
  const root = await mkdtemp(path.join(os.tmpdir(), "workspace-file-"));
  await mkdir(path.join(root, "src"));
  await writeFile(path.join(root, "src", "main.ts"), "export const value = 1;\n", "utf8");
  return { root, service: await FileService.create(root) };
}

describe("FileService", () => {
  it("트리와 revision을 반환하고 원자적으로 저장한다", async () => {
    const { root, service } = await fixture();
    const tree = await service.listTree();
    expect(tree[0]?.name).toBe("src");
    const opened = await service.readFile("src/main.ts");
    const saved = await service.saveFile({
      path: "src/main.ts",
      content: "export const value = 2;\n",
      expectedRevision: opened.revision,
    });
    expect(saved.revision).not.toBe(opened.revision);
    expect(await readFile(path.join(root, "src", "main.ts"), "utf8")).toContain("2");
  });

  it("revision이 다르면 저장을 거부한다", async () => {
    const { root, service } = await fixture();
    const opened = await service.readFile("src/main.ts");
    await writeFile(path.join(root, "src", "main.ts"), "external\n", "utf8");
    await expect(service.saveFile({ path: "src/main.ts", content: "mine\n", expectedRevision: opened.revision }))
      .rejects.toMatchObject({ code: "file_conflict" });
  });

  it("프로젝트 밖 경로와 바이너리를 거부한다", async () => {
    const { root, service } = await fixture();
    await expect(service.readFile(path.resolve(root, "..", "outside.txt"))).rejects.toBeInstanceOf(FileServiceError);
    await writeFile(path.join(root, "binary.bin"), Buffer.from([0, 1, 2]));
    await expect(service.readFile("binary.bin")).rejects.toMatchObject({ code: "binary_file" });
  });

  it("크기 제한을 넘은 텍스트는 읽기 전용으로 연다", async () => {
    const { root, service } = await fixture();
    await writeFile(path.join(root, "large.txt"), "x".repeat(128), "utf8");
    const limited = await FileService.create(root, 64);
    const opened = await limited.readFile("large.txt");
    expect(opened.readOnly).toBe(true);
    await expect(limited.saveFile({ path: opened.path, content: opened.content, expectedRevision: opened.revision }))
      .rejects.toMatchObject({ code: "file_too_large" });
  });

  it("확장자와 실제 MIME가 일치하는 이미지만 미리보기로 반환한다", async () => {
    const { root, service } = await fixture();
    const png = Buffer.from("iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNk+A8AAQUBAScY42YAAAAASUVORK5CYII=", "base64");
    await writeFile(path.join(root, "pixel.png"), png);
    const preview = await service.readImagePreview("pixel.png");
    expect(preview).toMatchObject({ mimeType: "image/png", readOnly: true, language: "image" });
    expect(preview.previewUrl).toMatch(/^data:image\/png;base64,/);

    await writeFile(path.join(root, "fake.jpg"), png);
    await expect(service.readImagePreview("fake.jpg")).rejects.toMatchObject({ code: "binary_file" });
  });
});
