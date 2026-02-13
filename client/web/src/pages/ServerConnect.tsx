/**
 * Server connection page — desktop first-run experience.
 * Shown when no server URL is configured (desktop app only).
 * Allows user to enter a Cairn server URL to connect to.
 */

import { useState, useEffect, type FormEvent } from "react";

interface ServerConnectProps {
  onConnect: (serverUrl: string) => void;
}

export default function ServerConnect({ onConnect }: ServerConnectProps) {
  const [url, setUrl] = useState("");
  const [error, setError] = useState("");
  const [checking, setChecking] = useState(false);
  const [recentServers, setRecentServers] = useState<string[]>([]);
  const [insecureUrl, setInsecureUrl] = useState<string | null>(null);

  useEffect(() => {
    // Load recent servers from localStorage
    const saved = localStorage.getItem("cairn_recent_servers");
    if (saved) {
      try {
        setRecentServers(JSON.parse(saved));
      } catch {
        // ignore
      }
    }
  }, []);

  async function handleSubmit(e: FormEvent) {
    e.preventDefault();
    setError("");

    let serverUrl = url.trim().replace(/\/$/, "");
    if (!serverUrl.startsWith("http")) {
      serverUrl = `https://${serverUrl}`;
    }

    setChecking(true);
    try {
      const resp = await fetch(`${serverUrl}/health`, { signal: AbortSignal.timeout(5000) });
      if (!resp.ok) throw new Error("Server returned an error");

      // Save to recent
      const updated = [serverUrl, ...recentServers.filter((s) => s !== serverUrl)].slice(0, 5);
      localStorage.setItem("cairn_recent_servers", JSON.stringify(updated));

      // Warn if connecting over plain HTTP
      if (serverUrl.startsWith("http://")) {
        setInsecureUrl(serverUrl);
      } else {
        onConnect(serverUrl);
      }
    } catch {
      setError("Could not connect to server. Check the URL and try again.");
    } finally {
      setChecking(false);
    }
  }

  function handleSelectRecent(serverUrl: string) {
    setUrl(serverUrl);
    onConnect(serverUrl);
  }

  return (
    <div style={{ display: "flex", alignItems: "center", justifyContent: "center", minHeight: "100vh", background: "#1a1a2e" }}>
      <div style={{ width: 400, padding: 32, background: "#16213e", borderRadius: 12, color: "#e0e0e0" }}>
        <h1 style={{ fontSize: 24, marginBottom: 8 }}>Cairn</h1>
        <p style={{ color: "#888", marginBottom: 24 }}>Connect to a Cairn server</p>

        <form onSubmit={handleSubmit}>
          <input
            type="text"
            placeholder="cairn.example.com"
            value={url}
            onChange={(e) => setUrl(e.target.value)}
            style={{ width: "100%", padding: 12, borderRadius: 8, border: "1px solid #333", background: "#0f3460", color: "#fff", fontSize: 16, boxSizing: "border-box" }}
            autoFocus
          />
          {error && <p style={{ color: "#e74c3c", fontSize: 14, marginTop: 8 }}>{error}</p>}
          <button
            type="submit"
            disabled={!url.trim() || checking}
            style={{ width: "100%", padding: 12, marginTop: 16, borderRadius: 8, border: "none", background: "#533483", color: "#fff", fontSize: 16, cursor: "pointer", opacity: checking ? 0.6 : 1 }}
          >
            {checking ? "Connecting..." : "Connect"}
          </button>
        </form>

        {recentServers.length > 0 && (
          <div style={{ marginTop: 24 }}>
            <p style={{ color: "#888", fontSize: 14, marginBottom: 8 }}>Recent servers</p>
            {recentServers.map((s) => (
              <button
                key={s}
                onClick={() => handleSelectRecent(s)}
                style={{ display: "block", width: "100%", padding: 8, marginBottom: 4, borderRadius: 6, border: "1px solid #333", background: "transparent", color: "#aaa", cursor: "pointer", textAlign: "left", fontSize: 14 }}
              >
                {s.replace(/^https?:\/\//, "")}
              </button>
            ))}
          </div>
        )}
      </div>

      {insecureUrl && (
        <div style={{ position: "fixed", inset: 0, background: "rgba(0,0,0,0.6)", display: "flex", alignItems: "center", justifyContent: "center", zIndex: 1000 }}>
          <div style={{ width: 420, padding: 28, background: "#16213e", borderRadius: 12, color: "#e0e0e0", border: "1px solid #e74c3c" }}>
            <h2 style={{ fontSize: 18, color: "#e74c3c", marginBottom: 12 }}>Insecure Connection</h2>
            <p style={{ fontSize: 14, lineHeight: 1.5, marginBottom: 20 }}>
              This server does not use an encrypted connection. Your messages, credentials, and other data could be intercepted by third parties. This is only safe on trusted private networks (e.g. home LAN, Tailscale).
            </p>
            <div style={{ display: "flex", gap: 12, justifyContent: "flex-end" }}>
              <button
                onClick={() => setInsecureUrl(null)}
                style={{ padding: "8px 20px", borderRadius: 6, border: "1px solid #555", background: "transparent", color: "#ccc", cursor: "pointer" }}
              >
                Cancel
              </button>
              <button
                onClick={() => { setInsecureUrl(null); onConnect(insecureUrl); }}
                style={{ padding: "8px 20px", borderRadius: 6, border: "none", background: "#e74c3c", color: "#fff", cursor: "pointer" }}
              >
                Continue Anyway
              </button>
            </div>
          </div>
        </div>
      )}
    </div>
  );
}
