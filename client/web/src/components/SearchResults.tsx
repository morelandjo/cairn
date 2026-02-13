import { useState } from "react";
import type { SearchResult } from "../api/search.ts";
import { searchMessages } from "../api/search.ts";

interface Props {
  serverId: string;
  onClose: () => void;
}

export default function SearchResults({ serverId, onClose }: Props) {
  const [query, setQuery] = useState("");
  const [results, setResults] = useState<SearchResult[]>([]);
  const [loading, setLoading] = useState(false);
  const [searched, setSearched] = useState(false);

  async function handleSearch() {
    const q = query.trim();
    if (!q) return;
    setLoading(true);
    try {
      const data = await searchMessages(serverId, q);
      setResults(data.results);
      setSearched(true);
    } catch (err) {
      console.error("Search failed:", err);
    } finally {
      setLoading(false);
    }
  }

  return (
    <div className="search-panel">
      <div className="panel-header">
        <h3>Search</h3>
        <button className="btn-close" onClick={onClose}>
          &times;
        </button>
      </div>
      <div className="search-input-row">
        <input
          type="text"
          value={query}
          onChange={(e) => setQuery(e.target.value)}
          placeholder="Search messages..."
          onKeyDown={(e) => {
            if (e.key === "Enter") handleSearch();
          }}
          autoFocus
        />
        <button onClick={handleSearch} disabled={loading}>
          {loading ? "..." : "Search"}
        </button>
      </div>
      <div className="search-results">
        {searched && results.length === 0 && (
          <div className="empty-state">No results found</div>
        )}
        {results.map((r) => (
          <div key={r.id} className="search-result">
            <div className="search-result-header">
              <span className="search-result-author">
                {r.author_username}
              </span>
              <span className="search-result-channel">
                #{r.channel_name}
              </span>
              <span className="search-result-time">
                {new Date(r.inserted_at).toLocaleString()}
              </span>
            </div>
            <div className="search-result-content">{r.content}</div>
          </div>
        ))}
      </div>
    </div>
  );
}
