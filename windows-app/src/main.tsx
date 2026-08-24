import React from 'react';
import ReactDOM from 'react-dom/client';
import App from './App';
import './styles.css';

function Pet() {
  return (
    <main className="pet-shell" title="Double-click to open Puck" onDoubleClick={() => window.puck.client.show()}>
      <div className="pet-shadow" />
      <button className="pet" onClick={() => window.puck.client.show()} aria-label="Open Puck">
        <span className="pet-face">◕‿◕</span>
      </button>
    </main>
  );
}

const mode = new URLSearchParams(location.search).get('mode');
ReactDOM.createRoot(document.getElementById('root')!).render(
  <React.StrictMode>{mode === 'pet' ? <Pet /> : <App />}</React.StrictMode>
);
