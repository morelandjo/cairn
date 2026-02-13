import { useEffect, useState } from "react";
import { useNavigate } from "react-router-dom";
import * as discoveryApi from "../api/discovery.ts";
import type { DirectoryEntry } from "../api/discovery.ts";
import { joinServer } from "../api/servers.ts";

export default function ServerDiscovery() {
  const [entries, setEntries] = useState<DirectoryEntry[]>([]);
  const [loading, setLoading] = useState(true);
  const [tagFilter, setTagFilter] = useState("");
  const navigate = useNavigate();

  useEffect(() => {
    loadDirectory();
  }, []);

  async function loadDirectory(tag?: string) {
    setLoading(true);
    try {
      const data = await discoveryApi.listDirectory({
        limit: 50,
        tag: tag || undefined,
      });
      setEntries(data.servers);
    } catch (err) {
      console.error("Failed to load directory:", err);
    } finally {
      setLoading(false);
    }
  }

  function handleTagSearch() {
    const tag = tagFilter.trim();
    loadDirectory(tag || undefined);
  }

  async function handleJoin(serverId: string) {
    try {
      await joinServer(serverId);
      navigate(`/servers/${serverId}`);
    } catch (err) {
      console.error("Failed to join server:", err);
    }
  }

  return (
    <div className="server-discovery">
      <h2>Discover Servers</h2>
      <div className="discovery-search">
        <input
          type="text"
          value={tagFilter}
          onChange={(e) => setTagFilter(e.target.value)}
          placeholder="Filter by tag..."
          onKeyDown={(e) => {
            if (e.key === "Enter") handleTagSearch();
          }}
        />
        <button onClick={handleTagSearch}>Search</button>
      </div>
      {loading ? (
        <div className="loading">Loading...</div>
      ) : entries.length === 0 ? (
        <div className="empty-state">No public servers found</div>
      ) : (
        <div className="discovery-grid">
          {entries.map((entry) => (
            <div key={entry.id} className="discovery-card">
              <h3>{entry.server_name}</h3>
              {entry.description && <p>{entry.description}</p>}
              <div className="discovery-meta">
                <span>{entry.member_count} members</span>
                {entry.tags.length > 0 && (
                  <div className="discovery-tags">
                    {entry.tags.map((tag) => (
                      <span key={tag} className="tag">
                        {tag}
                      </span>
                    ))}
                  </div>
                )}
              </div>
              <button
                className="btn-join"
                onClick={() => handleJoin(entry.server_id)}
              >
                Join
              </button>
            </div>
          ))}
        </div>
      )}
    </div>
  );
}
