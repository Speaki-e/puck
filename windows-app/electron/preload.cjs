const { contextBridge, ipcRenderer } = require('electron');

contextBridge.exposeInMainWorld('puck', {
  workspace: {
    open: () => ipcRenderer.invoke('workspace:open'),
    refresh: () => ipcRenderer.invoke('workspace:refresh')
  },
  file: {
    read: (path) => ipcRenderer.invoke('file:read', path),
    write: (path, content) => ipcRenderer.invoke('file:write', path, content)
  },
  git: {
    status: () => ipcRenderer.invoke('git:status')
  },
  terminal: {
    create: () => ipcRenderer.invoke('terminal:create'),
    write: (id, data) => ipcRenderer.send('terminal:write', { id, data }),
    resize: (id, cols, rows) => ipcRenderer.send('terminal:resize', { id, cols, rows }),
    dispose: (id) => ipcRenderer.send('terminal:dispose', id),
    onData: (listener) => {
      const wrapped = (_event, payload) => listener(payload);
      ipcRenderer.on('terminal:data', wrapped);
      return () => ipcRenderer.removeListener('terminal:data', wrapped);
    }
  },
  client: { show: () => ipcRenderer.send('client:show') }
});
