import { useEffect, useState } from "react";
import { useNavigate } from "react-router-dom";
import { useServerStore } from "../stores/serverStore.ts";
import { useConnectionStore } from "../stores/connectionStore.ts";

export default function ServerSidebar() {
  const servers = useServerStore((s) => s.servers);
  const currentServerId = useServerStore((s) => s.currentServerId);
  const fetchServers = useServerStore((s) => s.fetchServers);
  const selectServer = useServerStore((s) => s.selectServer);
  const createServer = useServerStore((s) => s.createServer);
  const connections = useConnectionStore((s) => s.connections);
  const navigate = useNavigate();

  const [showCreate, setShowCreate] = useState(false);
  const [newServerName, setNewServerName] = useState("");

  useEffect(() => {
    fetchServers();
  }, [fetchServers]);

  // Group servers by instance domain
  const homeServers = servers.filter(
    (s) => !s.instance_domain || s.instance_domain === "home",
  );
  const remoteGroups = new Map<string, typeof servers>();
  servers.forEach((s) => {
    if (s.instance_domain && s.instance_domain !== "home") {
      const group = remoteGroups.get(s.instance_domain) || [];
      group.push(s);
      remoteGroups.set(s.instance_domain, group);
    }
  });

  async function handleCreateServer() {
    const name = newServerName.trim();
    if (!name) return;
    try {
      const server = await createServer(name);
      setNewServerName("");
      setShowCreate(false);
      navigate(`/servers/${server.id}`);
    } catch (err) {
      console.error("Failed to create server:", err);
    }
  }

  function handleSelectServer(serverId: string) {
    selectServer(serverId);
    navigate(`/servers/${serverId}`);
  }

  function getConnectionStatus(domain: string) {
    const conn = connections.get(domain);
    return conn?.status || "disconnected";
  }

  function renderServerIcon(
    server: { id: string; name: string; icon_key?: string | null },
  ) {
    return (
      <button
        key={server.id}
        className={`server-icon ${server.id === currentServerId ? "active" : ""}`}
        onClick={() => handleSelectServer(server.id)}
        title={server.name}
      >
        {server.icon_key ? (
          <img src={`/api/v1/files/${server.icon_key}`} alt={server.name} />
        ) : (
          <span className="server-icon-letter">
            {server.name.charAt(0).toUpperCase()}
          </span>
        )}
      </button>
    );
  }

  return (
    <div className="server-sidebar">
      <button
        className={`server-icon server-icon-home ${currentServerId === null ? "active" : ""}`}
        onClick={() => {
          selectServer(null);
          navigate("/channels");
        }}
        title="Direct Messages"
      >
        <svg width="24" height="24" viewBox="0 0 24 24" fill="currentColor">
          <path d="M12 2L3 9v11a2 2 0 002 2h14a2 2 0 002-2V9l-9-7zM12 16a3 3 0 110-6 3 3 0 010 6z" />
        </svg>
      </button>

      <div className="server-separator" />

      {/* Home instance servers */}
      {homeServers.map(renderServerIcon)}

      {/* Remote instance servers, grouped by domain */}
      {Array.from(remoteGroups.entries()).map(([domain, domainServers]) => {
        const status = getConnectionStatus(domain);
        return (
          <div key={domain} className="server-instance-group">
            <div className="server-separator" />
            <div
              className="server-instance-label"
              title={`${domain} (${status})`}
            >
              <span
                className={`connection-dot connection-${status}`}
              />
              <span className="instance-domain">
                {domain.split(".")[0]}
              </span>
            </div>
            {domainServers.map(renderServerIcon)}
          </div>
        );
      })}

      <div className="server-separator" />

      <button
        className="server-icon server-icon-add"
        onClick={() => setShowCreate(true)}
        title="Create Server"
      >
        +
      </button>

      <button
        className="server-icon server-icon-join-remote"
        onClick={() => navigate("/discover")}
        title="Join Remote Server"
      >
        <svg width="20" height="20" viewBox="0 0 24 24" fill="currentColor">
          <path d="M12 2C6.48 2 2 6.48 2 12s4.48 10 10 10 10-4.48 10-10S17.52 2 12 2zm-1 17.93c-3.95-.49-7-3.85-7-7.93 0-.62.08-1.21.21-1.79L9 15v1c0 1.1.9 2 2 2v1.93zm6.9-2.54c-.26-.81-1-1.39-1.9-1.39h-1v-3c0-.55-.45-1-1-1H8v-2h2c.55 0 1-.45 1-1V7h2c1.1 0 2-.9 2-2v-.41c2.93 1.19 5 4.06 5 7.41 0 2.08-.8 3.97-2.1 5.39z" />
        </svg>
      </button>

      {showCreate && (
        <div className="server-create-modal-backdrop" onClick={() => setShowCreate(false)}>
          <div className="server-create-modal" onClick={(e) => e.stopPropagation()}>
            <h3>Create a Server</h3>
            <input
              type="text"
              value={newServerName}
              onChange={(e) => setNewServerName(e.target.value)}
              placeholder="Server name"
              autoFocus
              onKeyDown={(e) => {
                if (e.key === "Enter") handleCreateServer();
                if (e.key === "Escape") setShowCreate(false);
              }}
            />
            <div className="server-create-buttons">
              <button className="btn-primary" onClick={handleCreateServer}>
                Create
              </button>
              <button onClick={() => setShowCreate(false)}>Cancel</button>
            </div>
          </div>
        </div>
      )}
    </div>
  );
}
