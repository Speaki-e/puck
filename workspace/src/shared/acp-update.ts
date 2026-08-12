import path from "node:path";

export interface AcpUpdatePayload {
  sessionUpdate?: string;
  content?: { type?: string; text?: string };
  locations?: Array<{ path?: string }>;
}

export function workingPathsFromUpdate(projectPath: string, payload: AcpUpdatePayload): string[] {
  return [...new Set((payload.locations ?? []).flatMap((location) => {
    if (!location.path) return [];
    const relative = path.relative(projectPath, location.path);
    return !relative || relative.startsWith("..") || path.isAbsolute(relative)
      ? []
      : [relative.split(path.sep).join("/")];
  }))];
}
