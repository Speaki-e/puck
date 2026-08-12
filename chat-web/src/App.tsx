import { useState } from "react";

export function App() {
  const [count, setCount] = useState(0);

  return (
    <div style={{ fontFamily: "sans-serif", padding: 24, color: "#ededed", background: "#090909", minHeight: "100vh" }}>
      <h1>chat-web Phase 0 spike</h1>
      <p>location.href: {location.href}</p>
      <p>location.protocol: {location.protocol}</p>
      <button type="button" onClick={() => setCount((n) => n + 1)}>
        count: {count}
      </button>
    </div>
  );
}
