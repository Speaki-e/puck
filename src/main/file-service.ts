import { createHash, randomUUID } from "node:crypto";
import { lstat, readFile, readdir, realpath, rename, rm, stat, writeFile } from "node:fs/promises";
import path from "node:path";
import { EventEmitter } from "node:events";
import { watch, type FSWatcher } from "chokidar";
import {
  FileServiceError,
  type FileContent,
  type FileTreeEntry,
  type SaveFileRequest,
  type SaveFileResult,
} from "../shared/file-contract.js";
import { detectImageMime, IMAGE_EXTENSION_MIME } from "../shared/image-mime.js";
import { isPathInside } from "../shared/path-containment.js";

export const DEFAULT_EDITABLE_SIZE_LIMIT = 2 * 1024 * 1024;
export const DEFAULT_IMAGE_PREVIEW_SIZE_LIMIT = 10 * 1024 * 1024;
const DEFAULT_IGNORES = new Set([".git", "node_modules", "dist", "dist-main", "release"]);

function revision(buffer: Buffer): string {
  return createHash("sha256").update(buffer).digest("hex");
}

function isBinary(buffer: Buffer): boolean {
  const sample = buffer.subarray(0, Math.min(buffer.length, 8192));
  return sample.includes(0);
}

function languageFor(filePath: string): string | undefined {
  const extension = path.extname(filePath).toLowerCase();
  return {
    ".ts": "typescript",
    ".tsx": "typescript",
    ".js": "javascript",
    ".jsx": "javascript",
    ".json": "json",
    ".md": "markdown",
    ".css": "css",
    ".html": "html",
    ".py": "python",
    ".rs": "rust",
    ".swift": "swift",
    ".sh": "shell",
    ".yml": "yaml",
    ".yaml": "yaml",
  }[extension];
}

function relativeForWire(root: string, target: string): string {
  return path.relative(root, target).split(path.sep).join("/");
}

export class FileService extends EventEmitter {
  private watcher?: FSWatcher;

  constructor(
    readonly root: string,
    readonly editableSizeLimit = DEFAULT_EDITABLE_SIZE_LIMIT,
  ) {
    super();
  }

  static async create(root: string, editableSizeLimit?: number): Promise<FileService> {
    return new FileService(await realpath(path.resolve(root)), editableSizeLimit);
  }

  async listTree(): Promise<FileTreeEntry[]> {
    return this.readDirectory(this.root);
  }

  async readFile(requestPath: string): Promise<FileContent> {
    const target = await this.resolveExisting(requestPath);
    const metadata = await stat(target);
    if (!metadata.isFile()) throw new FileServiceError("invalid_path", "파일 경로가 아닙니다");
    const buffer = await readFile(target);
    if (isBinary(buffer)) throw new FileServiceError("binary_file", "바이너리 파일은 편집할 수 없습니다");
    let content: string;
    try {
      content = new TextDecoder("utf-8", { fatal: true }).decode(buffer);
    } catch {
      throw new FileServiceError("encoding_error", "UTF-8 텍스트 파일만 지원합니다");
    }
    return {
      path: relativeForWire(this.root, target),
      content,
      revision: revision(buffer),
      readOnly: metadata.size > this.editableSizeLimit,
      size: metadata.size,
      language: languageFor(target),
    };
  }

  async readImagePreview(requestPath: string): Promise<FileContent> {
    const target = await this.resolveExisting(requestPath);
    const metadata = await stat(target);
    if (!metadata.isFile()) throw new FileServiceError("invalid_path", "파일 경로가 아닙니다");
    if (metadata.size > DEFAULT_IMAGE_PREVIEW_SIZE_LIMIT) {
      throw new FileServiceError("file_too_large", "10MB를 초과하는 이미지는 미리 볼 수 없습니다");
    }
    const buffer = await readFile(target);
    const detectedMime = detectImageMime(buffer);
    const expectedMime = IMAGE_EXTENSION_MIME.get(path.extname(target).toLowerCase());
    if (!detectedMime || detectedMime !== expectedMime) {
      throw new FileServiceError("binary_file", "지원하는 이미지 형식과 실제 파일 내용이 일치하지 않습니다");
    }
    return {
      path: relativeForWire(this.root, target),
      content: "",
      revision: revision(buffer),
      readOnly: true,
      size: metadata.size,
      language: "image",
      mimeType: detectedMime,
      previewUrl: `data:${detectedMime};base64,${buffer.toString("base64")}`,
    };
  }

  async saveFile(request: SaveFileRequest): Promise<SaveFileResult> {
    const target = await this.resolveExisting(request.path);
    const metadata = await stat(target);
    if (!metadata.isFile()) throw new FileServiceError("invalid_path", "파일 경로가 아닙니다");
    if (metadata.size > this.editableSizeLimit) {
      throw new FileServiceError("file_too_large", "2MB를 초과하는 파일은 읽기 전용입니다");
    }
    const current = await readFile(target);
    if (isBinary(current)) throw new FileServiceError("binary_file", "바이너리 파일은 저장할 수 없습니다");
    if (revision(current) !== request.expectedRevision) {
      throw new FileServiceError("file_conflict", "디스크 파일이 마지막 읽기 이후 변경되었습니다");
    }

    const next = Buffer.from(request.content, "utf8");
    if (next.byteLength > this.editableSizeLimit) {
      throw new FileServiceError("file_too_large", "저장할 내용이 2MB 제한을 초과합니다");
    }
    const temporary = path.join(path.dirname(target), `.${path.basename(target)}.${process.pid}.${randomUUID()}.tmp`);
    try {
      await writeFile(temporary, next, { mode: metadata.mode });
      await rename(temporary, target);
    } finally {
      await rm(temporary, { force: true }).catch(() => undefined);
    }
    return { path: relativeForWire(this.root, target), revision: revision(next), size: next.byteLength };
  }

  async startWatching(): Promise<void> {
    if (this.watcher) return;
    this.watcher = watch(this.root, {
      ignoreInitial: true,
      ignored: (candidate) => relativeForWire(this.root, candidate).split("/").some((part) => DEFAULT_IGNORES.has(part)),
      awaitWriteFinish: { stabilityThreshold: 100, pollInterval: 25 },
    });
    for (const event of ["add", "change", "unlink", "addDir", "unlinkDir"] as const) {
      this.watcher.on(event, (candidate) => {
        const absolute = path.resolve(candidate);
        if (this.isInside(absolute)) this.emit("change", { event, path: relativeForWire(this.root, absolute) });
      });
    }
  }

  async close(): Promise<void> {
    await this.watcher?.close();
    this.watcher = undefined;
    this.removeAllListeners();
  }

  private async readDirectory(directory: string): Promise<FileTreeEntry[]> {
    const entries = await readdir(directory, { withFileTypes: true });
    const result: FileTreeEntry[] = [];
    for (const entry of entries.sort((left, right) => {
      if (left.isDirectory() !== right.isDirectory()) return left.isDirectory() ? -1 : 1;
      return left.name.localeCompare(right.name);
    })) {
      if (DEFAULT_IGNORES.has(entry.name)) continue;
      const candidate = path.join(directory, entry.name);
      const info = await lstat(candidate);
      if (info.isSymbolicLink()) {
        try {
          const resolved = await realpath(candidate);
          if (!this.isInside(resolved)) continue;
          result.push({ name: entry.name, path: relativeForWire(this.root, candidate), kind: "symlink" });
        } catch {
          continue;
        }
      } else if (info.isDirectory()) {
        result.push({
          name: entry.name,
          path: relativeForWire(this.root, candidate),
          kind: "directory",
          children: await this.readDirectory(candidate),
        });
      } else if (info.isFile()) {
        result.push({ name: entry.name, path: relativeForWire(this.root, candidate), kind: "file" });
      }
    }
    return result;
  }

  private async resolveExisting(requestPath: string): Promise<string> {
    if (!requestPath || requestPath.includes("\0")) throw new FileServiceError("invalid_path", "잘못된 파일 경로입니다");
    const candidate = path.isAbsolute(requestPath) ? path.resolve(requestPath) : path.resolve(this.root, requestPath);
    if (!this.isInside(candidate)) throw new FileServiceError("path_outside_workspace", "프로젝트 밖 경로입니다");
    try {
      const resolved = await realpath(candidate);
      if (!this.isInside(resolved)) throw new FileServiceError("path_outside_workspace", "심볼릭 링크가 프로젝트 밖을 가리킵니다");
      return resolved;
    } catch (error) {
      if (error instanceof FileServiceError) throw error;
      if ((error as NodeJS.ErrnoException).code === "ENOENT") {
        throw new FileServiceError("file_not_found", "파일을 찾을 수 없습니다");
      }
      throw error;
    }
  }

  private isInside(candidate: string): boolean {
    return isPathInside(this.root, candidate);
  }
}
