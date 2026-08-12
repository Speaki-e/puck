import { useMemo, useState } from "react";
import type { FileTreeEntry } from "../../shared/file-contract";
import { Button } from "./ui/button";
import { Input } from "./ui/input";
import { ScrollArea } from "./ui/scroll-area";

interface Props {
  entries: FileTreeEntry[];
  activePath?: string;
  workingPaths: Set<string>;
  onOpen(path: string): void;
}

function Chevron({ expanded }: { expanded: boolean }) {
  return <svg className={`tree-chevron ${expanded ? "expanded" : ""}`} viewBox="0 0 16 16" aria-hidden><path d="m6 3.5 4.5 4.5L6 12.5" fill="none" stroke="currentColor" strokeWidth="1.5" strokeLinecap="round" strokeLinejoin="round" /></svg>;
}

function FolderIcon({ open }: { open: boolean }) {
  return <svg className="tree-kind folder-kind" viewBox="0 0 18 18" aria-hidden fill="none" stroke="currentColor" strokeWidth="1.3"><path d={open ? "M2 6.5h14l-1.6 8H3.2zM2.4 6.5V4h5l1.4 1.5H15v1" : "M2.5 4h5l1.4 1.6h6.6v8.8h-13z"} strokeLinejoin="round" /></svg>;
}

function FileIcon({ extension }: { extension: string }) {
  return <span className="file-kind" data-extension={extension}><span>{extension.slice(0, 2).toUpperCase() || "·"}</span></span>;
}

function filterEntries(entries: FileTreeEntry[], query: string): FileTreeEntry[] {
  if (!query) return entries;
  return entries.flatMap((entry) => {
    if (entry.kind === "file") return entry.name.toLowerCase().includes(query) ? [entry] : [];
    const children = filterEntries(entry.children ?? [], query);
    return entry.name.toLowerCase().includes(query) || children.length ? [{ ...entry, children }] : [];
  });
}

function TreeItem({ entry, activePath, workingPaths, onOpen, depth, searching }: {
  entry: FileTreeEntry;
  activePath?: string;
  workingPaths: Set<string>;
  onOpen(path: string): void;
  depth: number;
  searching: boolean;
}) {
  const [expanded, setExpanded] = useState(depth < 2);
  const isDirectory = entry.kind === "directory";
  const isOpen = searching || expanded;
  const isWorking = workingPaths.has(entry.path);
  const extension = entry.name.includes(".") ? entry.name.split(".").at(-1)!.toLowerCase() : "";

  return (
    <li>
      <button
        type="button"
        className={`tree-row ${activePath === entry.path ? "active" : ""} ${isWorking ? "working" : ""}`}
        style={{ paddingLeft: `${12 + depth * 14}px` }}
        onClick={() => (isDirectory ? setExpanded((value) => !value) : onOpen(entry.path))}
        title={entry.path}
      >
        <span className="tree-chevron-slot">{isDirectory && <Chevron expanded={isOpen} />}</span>
        {isDirectory ? <FolderIcon open={isOpen} /> : <FileIcon extension={extension} />}
        <span className="tree-label">{entry.name}</span>
        {isWorking && <span className="working-dot" title="ACP가 수정 중"><span /></span>}
      </button>
      {isDirectory && isOpen && entry.children && (
        <ul>
          {entry.children.map((child) => (
            <TreeItem key={child.path} entry={child} activePath={activePath} workingPaths={workingPaths} onOpen={onOpen} depth={depth + 1} searching={searching} />
          ))}
        </ul>
      )}
    </li>
  );
}

export function FileTree(props: Props) {
  const [query, setQuery] = useState("");
  const normalized = query.trim().toLowerCase();
  const entries = useMemo(() => filterEntries(props.entries, normalized), [props.entries, normalized]);

  return (
    <div className="tree-container">
      <label className="tree-search">
        <svg viewBox="0 0 20 20" aria-hidden fill="none" stroke="currentColor" strokeWidth="1.5"><circle cx="8.5" cy="8.5" r="5" /><path d="m12.2 12.2 4 4" /></svg>
        <Input value={query} onChange={(event) => setQuery(event.target.value)} placeholder="파일 검색" aria-label="파일 검색" />
        {query && <Button type="button" variant="ghost" size="icon-sm" onClick={() => setQuery("")} aria-label="검색 지우기">×</Button>}
      </label>
      <ScrollArea className="tree-scroll">
        {entries.length === 0 ? (
          <div className="empty-tree">
            <span>{props.entries.length ? "검색 결과가 없습니다" : "프로젝트를 열어주세요"}</span>
            <small>{props.entries.length ? "다른 파일명을 입력해보세요." : "파일과 폴더가 여기에 표시됩니다."}</small>
          </div>
        ) : (
          <ul className="file-tree">
            {entries.map((entry) => <TreeItem key={entry.path} entry={entry} {...props} depth={0} searching={Boolean(normalized)} />)}
          </ul>
        )}
      </ScrollArea>
    </div>
  );
}
