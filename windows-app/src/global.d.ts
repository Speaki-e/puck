export {};

type TreeNode = { name: string; path: string; kind: 'file' | 'directory'; children?: TreeNode[] };
type WorkspaceResult = { root: string; tree: TreeNode[] };
type ProcessResult = { code: number; stdout: string; stderr: string };

declare global {
  interface Window {
    puck: {
      workspace: { open(): Promise<WorkspaceResult | null>; refresh(): Promise<WorkspaceResult | null> };
      file: { read(path: string): Promise<string>; write(path: string, content: string): Promise<boolean> };
      git: { status(): Promise<ProcessResult | null> };
      terminal: {
        create(): Promise<string>;
        write(id: string, data: string): void;
        resize(id: string, cols: number, rows: number): void;
        dispose(id: string): void;
        onData(listener: (payload: { id: string; data: string }) => void): () => void;
      };
      client: { show(): void };
    };
  }
}
