import type { FileContent } from "../shared/file-contract";

export interface EditorTab extends FileContent {
  savedContent: string;
  diskChanged: boolean;
}

export interface EditorState {
  tabs: EditorTab[];
  activePath?: string;
}

export type EditorAction =
  | { type: "open"; file: FileContent }
  | { type: "activate"; path: string }
  | { type: "edit"; path: string; content: string }
  | { type: "saved"; path: string; revision: string; size: number }
  | { type: "diskChanged"; path: string }
  | { type: "reload"; file: FileContent }
  | { type: "keepMine"; path: string }
  | { type: "close"; path: string };

export function isDirty(tab: EditorTab): boolean {
  return tab.content !== tab.savedContent;
}

export function editorReducer(state: EditorState, action: EditorAction): EditorState {
  switch (action.type) {
    case "open": {
      const existing = state.tabs.find((tab) => tab.path === action.file.path);
      if (existing) return { ...state, activePath: existing.path };
      return {
        tabs: [...state.tabs, { ...action.file, savedContent: action.file.content, diskChanged: false }],
        activePath: action.file.path,
      };
    }
    case "activate":
      return { ...state, activePath: action.path };
    case "edit":
      return {
        ...state,
        tabs: state.tabs.map((tab) => (tab.path === action.path ? { ...tab, content: action.content } : tab)),
      };
    case "saved":
      return {
        ...state,
        tabs: state.tabs.map((tab) =>
          tab.path === action.path
            ? { ...tab, revision: action.revision, size: action.size, savedContent: tab.content, diskChanged: false }
            : tab,
        ),
      };
    case "diskChanged":
      return {
        ...state,
        tabs: state.tabs.map((tab) => (tab.path === action.path ? { ...tab, diskChanged: true } : tab)),
      };
    case "reload":
      return {
        ...state,
        tabs: state.tabs.map((tab) =>
          tab.path === action.file.path
            ? { ...action.file, savedContent: action.file.content, diskChanged: false }
            : tab,
        ),
      };
    case "keepMine":
      return {
        ...state,
        tabs: state.tabs.map((tab) => (tab.path === action.path ? { ...tab, diskChanged: false } : tab)),
      };
    case "close": {
      const index = state.tabs.findIndex((tab) => tab.path === action.path);
      const tabs = state.tabs.filter((tab) => tab.path !== action.path);
      const activePath = state.activePath === action.path
        ? tabs[Math.min(index, tabs.length - 1)]?.path
        : state.activePath;
      return { tabs, activePath };
    }
  }
}
