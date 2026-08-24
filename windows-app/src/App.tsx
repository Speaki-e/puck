import { useEffect, useMemo, useRef, useState } from 'react';
import Editor from '@monaco-editor/react';
import { Terminal } from '@xterm/xterm';
import { FitAddon } from '@xterm/addon-fit';
import '@xterm/xterm/css/xterm.css';

type TreeNode = { name: string; path: string; kind: 'file' | 'directory'; children?: TreeNode[] };
type Tab = { path: string; name: string; content: string; saved: string };

const languageByExtension: Record<string, string> = {
  ts: 'typescript', tsx: 'typescript', js: 'javascript', jsx: 'javascript', json: 'json',
  py: 'python', java: 'java', kt: 'kotlin', kts: 'kotlin', swift: 'swift', rs: 'rust',
  c: 'c', h: 'c', cpp: 'cpp', hpp: 'cpp', cs: 'csharp', go: 'go', css: 'css',
  html: 'html', md: 'markdown', yml: 'yaml', yaml: 'yaml', xml: 'xml', sh: 'shell'
};

function languageFor(path: string) {
  const ext = path.split('.').pop()?.toLowerCase() ?? '';
  return languageByExtension[ext] ?? 'plaintext';
}

function Tree({ nodes, openFile }: { nodes: TreeNode[]; openFile: (node: TreeNode) => void }) {
  return <>{nodes.map(node => node.kind === 'directory' ? (
    <details key={node.path} className="tree-dir">
      <summary>▸ <span>{node.name}</span></summary>
      <div className="tree-children"><Tree nodes={node.children ?? []} openFile={openFile} /></div>
    </details>
  ) : (
    <button key={node.path} className="tree-file" onClick={() => openFile(node)} title={node.path}>
      <span className="file-dot" />{node.name}
    </button>
  ))}</>;
}

function TerminalPane({ root }: { root: string }) {
  const host = useRef<HTMLDivElement>(null);
  useEffect(() => {
    if (!host.current) return;
    const term = new Terminal({ convertEol: true, cursorBlink: true, fontFamily: 'Cascadia Mono, Consolas, monospace', fontSize: 13, theme: { background: '#0d0e10', foreground: '#e8e8e8', cursor: '#ffffff' } });
    const fit = new FitAddon();
    term.loadAddon(fit);
    term.open(host.current);
    fit.fit();
    let terminalId = '';
    let disposed = false;
    const removeData = window.puck.terminal.onData(({ id, data }) => { if (id === terminalId) term.write(data); });
    window.puck.terminal.create().then(id => {
      if (disposed) return window.puck.terminal.dispose(id);
      terminalId = id;
      term.onData(data => window.puck.terminal.write(id, data));
      fit.fit();
      window.puck.terminal.resize(id, term.cols, term.rows);
    });
    const resize = new ResizeObserver(() => {
      fit.fit();
      if (terminalId) window.puck.terminal.resize(terminalId, term.cols, term.rows);
    });
    resize.observe(host.current);
    return () => {
      disposed = true;
      resize.disconnect();
      removeData();
      if (terminalId) window.puck.terminal.dispose(terminalId);
      term.dispose();
    };
  }, [root]);
  return <div className="terminal" ref={host} />;
}

export default function App() {
  const [root, setRoot] = useState('');
  const [tree, setTree] = useState<TreeNode[]>([]);
  const [tabs, setTabs] = useState<Tab[]>([]);
  const [active, setActive] = useState('');
  const [git, setGit] = useState('No workspace');
  const [terminalOpen, setTerminalOpen] = useState(true);
  const activeTab = useMemo(() => tabs.find(tab => tab.path === active), [tabs, active]);

  async function openWorkspace() {
    const result = await window.puck.workspace.open();
    if (!result) return;
    setRoot(result.root);
    setTree(result.tree);
    setTabs([]);
    setActive('');
    refreshGit();
  }

  async function refreshWorkspace() {
    const result = await window.puck.workspace.refresh();
    if (result) setTree(result.tree);
    refreshGit();
  }

  async function refreshGit() {
    const result = await window.puck.git.status();
    if (!result) return setGit('No workspace');
    if (result.code !== 0) return setGit('Not a Git repository');
    const lines = result.stdout.trim().split(/\r?\n/).filter(Boolean);
    const branch = lines[0]?.replace(/^##\s*/, '') || 'Git';
    const changes = Math.max(0, lines.length - 1);
    setGit(`${branch}${changes ? ` · ${changes} change${changes === 1 ? '' : 's'}` : ' · clean'}`);
  }

  async function openFile(node: TreeNode) {
    const existing = tabs.find(tab => tab.path === node.path);
    if (existing) return setActive(existing.path);
    try {
      const content = await window.puck.file.read(node.path);
      const tab = { path: node.path, name: node.name, content, saved: content };
      setTabs(current => [...current, tab]);
      setActive(node.path);
    } catch (error) {
      console.error(error);
    }
  }

  function changeContent(value: string | undefined) {
    setTabs(current => current.map(tab => tab.path === active ? { ...tab, content: value ?? '' } : tab));
  }

  async function saveActive() {
    const tab = tabs.find(item => item.path === active);
    if (!tab) return;
    await window.puck.file.write(tab.path, tab.content);
    setTabs(current => current.map(item => item.path === active ? { ...item, saved: item.content } : item));
    refreshGit();
  }

  function closeTab(path: string) {
    setTabs(current => current.filter(tab => tab.path !== path));
    if (active === path) {
      const index = tabs.findIndex(tab => tab.path === path);
      setActive(tabs[index - 1]?.path ?? tabs[index + 1]?.path ?? '');
    }
  }

  useEffect(() => {
    const onKey = (event: KeyboardEvent) => {
      if ((event.ctrlKey || event.metaKey) && event.key.toLowerCase() === 's') {
        event.preventDefault();
        saveActive();
      }
      if ((event.ctrlKey || event.metaKey) && event.key.toLowerCase() === 'o') {
        event.preventDefault();
        openWorkspace();
      }
    };
    window.addEventListener('keydown', onKey);
    return () => window.removeEventListener('keydown', onKey);
  });

  return (
    <div className="app-shell">
      <header className="titlebar">
        <div className="brand"><span className="brand-mark">P</span><strong>Puck</strong><span className="platform">Windows</span></div>
        <div className="title-actions">
          <button onClick={openWorkspace}>Open folder</button>
          <button onClick={refreshWorkspace} disabled={!root}>Refresh</button>
          <button onClick={saveActive} disabled={!activeTab || activeTab.content === activeTab.saved}>Save</button>
        </div>
      </header>

      <div className="workspace-grid">
        <aside className="sidebar">
          <div className="section-title"><span>EXPLORER</span><span className="muted">{root ? root.split(/[\\/]/).pop() : ''}</span></div>
          <div className="tree">{root ? <Tree nodes={tree} openFile={openFile} /> : <div className="empty small">Open a folder to start.</div>}</div>
        </aside>

        <main className="editor-column">
          <div className="tabs">
            {tabs.map(tab => <button className={`tab ${active === tab.path ? 'active' : ''}`} key={tab.path} onClick={() => setActive(tab.path)}>
              <span>{tab.name}{tab.content !== tab.saved ? ' ●' : ''}</span>
              <span className="tab-close" onClick={(event) => { event.stopPropagation(); closeTab(tab.path); }}>×</span>
            </button>)}
          </div>
          <div className="editor-wrap">
            {activeTab ? <Editor
              path={activeTab.path}
              language={languageFor(activeTab.path)}
              value={activeTab.content}
              onChange={changeContent}
              theme="vs-dark"
              options={{ automaticLayout: true, minimap: { enabled: false }, fontFamily: 'Cascadia Code, Consolas, monospace', fontSize: 13, smoothScrolling: true, renderWhitespace: 'selection', padding: { top: 12 } }}
            /> : <div className="empty"><div className="empty-logo">P</div><h2>Puck Workspace</h2><p>Open a file from Explorer or press Ctrl+O to choose a workspace.</p></div>}
          </div>
          {terminalOpen && root && <div className="terminal-panel"><div className="terminal-heading">TERMINAL <span>PowerShell</span></div><TerminalPane root={root} /></div>}
          <footer className="statusbar"><span>{git}</span><button onClick={() => setTerminalOpen(value => !value)}>{terminalOpen ? 'Hide terminal' : 'Show terminal'}</button><span>{activeTab ? languageFor(activeTab.path) : 'Ready'}</span></footer>
        </main>

        <aside className="agent-panel">
          <div className="section-title">AGENT</div>
          <div className="agent-empty"><div className="spark">✦</div><strong>Puck agent bridge</strong><p>The Windows workspace is ready. Agent/desktop-control parity will attach here without coupling Monaco to the pet process.</p></div>
        </aside>
      </div>
    </div>
  );
}
