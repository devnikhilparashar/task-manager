import { StrictMode, useEffect, useState } from "react";
import { createRoot } from "react-dom/client";
import type { PublicStatus } from "@ambiant-memory/contracts";
import "./styles.css";

function App(): React.JSX.Element {
  const [status, setStatus] = useState<PublicStatus | null>(null);
  const [error, setError] = useState<string | null>(null);

  useEffect(() => {
    const unsubscribe = window.activityJournal.subscribeStatus(setStatus);
    void window.activityJournal.status().then(setStatus, () => setError("Status is temporarily unavailable."));
    return unsubscribe;
  }, []);

  return (
    <main>
      <p className="eyebrow">PRIVATE BY DESIGN</p>
      <h1>AmbiantMemory</h1>
      <p className="lede">Your local timeline will appear here after capture is implemented and you choose to enable it.</p>
      <section aria-live="polite" className="status-card">
        <span className="status-dot" aria-hidden="true" />
        <div>
          <strong>{error ?? (status ? `Capture is ${status.mode}` : "Checking local status…")}</strong>
          <p>No activity is captured by this foundation build.</p>
        </div>
      </section>
    </main>
  );
}

const root = document.getElementById("root");
if (root === null) throw new Error("Missing application root");
createRoot(root).render(<StrictMode><App /></StrictMode>);
