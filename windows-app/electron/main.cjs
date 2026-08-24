const { app, BrowserWindow, dialog, ipcMain, shell } = require('electron');
const fs = require('node:fs/promises');
const path = require('node:path');
const { spawn } = require('node:child_process');
const pty = require('node-pty');

let clientWindow;
let petWindow;
let workspaceRoot = null;
const terminals = new Map();
const ignored = new Set(['.git', 'node_modules', '.idea', '.vs', 'dist', 'build', '.next']);

function rendererURL(mode) {
  const dev = process.env.VITE_DEV_SERVER_URL;
  if (dev) return `${dev}/?mode=${mode}`;
  return `file://${path.join(__dirname, '..', 'dist', 'index.html')}?mode=${mode}`;
}

function commonWebPreferences() {
  return {
    preload: path.join(__dirname, 'preload.cjs'),
    contextIsolation: true,
    nodeIntegration: false,
    sandbox: false
  };
}

function createClientWindow() {
  clientWindow = new BrowserWindow({
    width: 1440,
    height: 900,
    minWidth: 960,
    minHeight: 640,
    show: false,
    backgroundColor: '#0d0e10',
    title: 'Puck',
    webPreferences: commonWebPreferences()
  });
  clientWindow.removeMenu();
  clientWindow.loadURL(rendererURL('client'));
  clientWindow.once('ready-to-show', () => clientWindow.show());
  clientWindow.webContents.setWindowOpenHandler(({ url }) => {
    if (/^https?:/i.test(url)) shell.openExternal(url);
    return { action: 'deny' };
  });
}

function createPetWindow() {
  const area = require('electron').screen.getPrimaryDisplay().workArea;
  petWindow = new BrowserWindow({
    width: 170,
    height: 170,
    x: Math.max(area.x, area.x + area.width - 210),
    y: Math.max(area.y, area.y + area.height - 210),
    transparent: true,
    frame: false,
    alwaysOnTop: true,
    resizable: false,
    skipTaskbar: true,
    hasShadow: false,
    webPreferences: commonWebPreferences()
  });
  petWindow.setAlwaysOnTop(true, 'floating');
  petWindow.loadURL(rendererURL('pet'));
}

function isInsideWorkspace(target) {
  if (!workspaceRoot) return false;
  const root = path.resolve(workspaceRoot).toLowerCase();
  const resolved = path.resolve(target).toLowerCase();
  return resolved === root || resolved.startsWith(root + path.sep);
}

function assertWorkspacePath(target) {
  if (!isInsideWorkspace(target)) throw new Error('Path is outside the active workspace.');
}

async function readTree(dir, budget = { remaining: 5000 }) {
  if (budget.remaining <= 0) return [];
  const entries = await fs.readdir(dir, { withFileTypes: true });
  entries.sort((a, b) => Number(b.isDirectory()) - Number(a.isDirectory()) || a.name.localeCompare(b.name));
  const result = [];
  for (const entry of entries) {
    if (budget.remaining-- <= 0) break;
    if (ignored.has(entry.name)) continue;
    const fullPath = path.join(dir, entry.name);
    if (entry.isDirectory()) {
      result.push({ name: entry.name, path: fullPath, kind: 'directory', children: await readTree(fullPath, budget) });
    } else if (entry.isFile()) {
      result.push({ name: entry.name, path: fullPath, kind: 'file' });
    }
  }
  return result;
}

function run(command, args, cwd) {
  return new Promise((resolve) => {
    const child = spawn(command, args, { cwd, windowsHide: true, shell: false });
    let stdout = '';
    let stderr = '';
    child.stdout.on('data', (data) => stdout += data.toString());
    child.stderr.on('data', (data) => stderr += data.toString());
    child.on('error', (error) => resolve({ code: -1, stdout, stderr: error.message }));
    child.on('close', (code) => resolve({ code: code ?? -1, stdout, stderr }));
  });
}

function registerIPC() {
  ipcMain.handle('workspace:open', async () => {
    const result = await dialog.showOpenDialog(clientWindow, { properties: ['openDirectory'] });
    if (result.canceled || !result.filePaths[0]) return null;
    workspaceRoot = path.resolve(result.filePaths[0]);
    return { root: workspaceRoot, tree: await readTree(workspaceRoot) };
  });

  ipcMain.handle('workspace:refresh', async () => {
    if (!workspaceRoot) return null;
    return { root: workspaceRoot, tree: await readTree(workspaceRoot) };
  });

  ipcMain.handle('file:read', async (_event, filePath) => {
    assertWorkspacePath(filePath);
    return fs.readFile(filePath, 'utf8');
  });

  ipcMain.handle('file:write', async (_event, filePath, content) => {
    assertWorkspacePath(filePath);
    await fs.writeFile(filePath, content, 'utf8');
    return true;
  });

  ipcMain.handle('git:status', async () => {
    if (!workspaceRoot) return null;
    return run('git.exe', ['-C', workspaceRoot, 'status', '--porcelain=v1', '--branch'], workspaceRoot);
  });

  ipcMain.handle('terminal:create', async () => {
    if (!workspaceRoot) throw new Error('Open a workspace first.');
    const id = crypto.randomUUID();
    let proc;
    try {
      proc = pty.spawn('pwsh.exe', ['-NoLogo'], { name: 'xterm-256color', cwd: workspaceRoot, cols: 100, rows: 30, env: process.env });
    } catch {
      proc = pty.spawn('powershell.exe', ['-NoLogo'], { name: 'xterm-256color', cwd: workspaceRoot, cols: 100, rows: 30, env: process.env });
    }
    terminals.set(id, proc);
    proc.onData((data) => clientWindow?.webContents.send('terminal:data', { id, data }));
    proc.onExit(() => terminals.delete(id));
    return id;
  });

  ipcMain.on('terminal:write', (_event, { id, data }) => terminals.get(id)?.write(data));
  ipcMain.on('terminal:resize', (_event, { id, cols, rows }) => {
    if (cols > 1 && rows > 1) terminals.get(id)?.resize(cols, rows);
  });
  ipcMain.on('terminal:dispose', (_event, id) => {
    terminals.get(id)?.kill();
    terminals.delete(id);
  });
  ipcMain.on('client:show', () => {
    if (!clientWindow || clientWindow.isDestroyed()) createClientWindow();
    clientWindow.show();
    clientWindow.focus();
  });
}

app.whenReady().then(() => {
  registerIPC();
  createClientWindow();
  createPetWindow();
  app.on('activate', () => {
    if (!clientWindow || clientWindow.isDestroyed()) createClientWindow();
  });
});

app.on('before-quit', () => {
  for (const proc of terminals.values()) proc.kill();
  terminals.clear();
});
app.on('window-all-closed', () => app.quit());
