export type FileEntryKind = "file" | "directory" | "symlink";

export interface FileTreeEntry {
  name: string;
  path: string;
  kind: FileEntryKind;
  children?: FileTreeEntry[];
}

export interface FileContent {
  path: string;
  content: string;
  revision: string;
  readOnly: boolean;
  size: number;
  language?: string;
  previewUrl?: string;
  mimeType?: string;
}

export interface SaveFileRequest {
  path: string;
  content: string;
  expectedRevision: string;
}

export interface SaveFileResult {
  path: string;
  revision: string;
  size: number;
}

export type FileServiceErrorCode =
  | "path_outside_workspace"
  | "file_not_found"
  | "file_conflict"
  | "file_too_large"
  | "binary_file"
  | "encoding_error"
  | "invalid_path";

export class FileServiceError extends Error {
  constructor(
    readonly code: FileServiceErrorCode,
    message: string,
  ) {
    super(message);
    this.name = "FileServiceError";
  }
}
