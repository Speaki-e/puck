import { StrictMode } from "react";
import { createRoot } from "react-dom/client";
import "./styles.css";

function App() {
  return (
    <main className="bootstrap-shell">
      <h1>Workspace</h1>
      <p>PetAgent 코드 워크스페이스를 준비하고 있습니다.</p>
    </main>
  );
}

createRoot(document.getElementById("root")!).render(
  <StrictMode>
    <App />
  </StrictMode>,
);
