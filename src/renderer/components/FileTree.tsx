import { useState } from "react";
import type { FileTreeEntry } from "../../shared/file-contract";

interface Props {
  entries: FileTreeEntry[];
  activePath?: string;
  workingPaths: Set<string>;
  onOpen(path: string): void;
}

function TreeItem({ entry, activePath, workingPaths, onOpen }: { entry: FileTreeEntry } & Omit<Props, "entries">) {
  const [expanded, setExpanded] = useState(true);
  const isDirectory = entry.kind === "directory";
  const isWorking = workingPaths.has(entry.path);
  return (
    <li>
      <button
        type="button"
        className={`tree-row ${activePath === entry.path ? "active" : ""} ${isWorking ? "working" : ""}`}
        onClick={() => (isDirectory ? setExpanded((value) => !value) : onOpen(entry.path))}
        title={entry.path}
      >
        <span className="tree-chevron">{isDirectory ? (expanded ? "⌄" : "›") : ""}</span>
        <span aria-hidden>{isDirectory ? "📁" : "📄"}</span>
        <span className="tree-label">{entry.name}</span>
        {isWorking && <span className="working-dot" title="ACP가 수정 중">●</span>}
      </button>
      {isDirectory && expanded && entry.children && (
        <ul>
          {entry.children.map((child) => (
            <TreeItem key={child.path} entry={child} activePath={activePath} workingPaths={workingPaths} onOpen={onOpen} />
          ))}
        </ul>
      )}
    </li>
  );
}

export function FileTree(props: Props) {
  if (props.entries.length === 0) return <p className="empty-tree">프로젝트를 선택하세요.</p>;
  return (
    <ul className="file-tree">
      {props.entries.map((entry) => <TreeItem key={entry.path} entry={entry} {...props} />)}
    </ul>
  );
}
