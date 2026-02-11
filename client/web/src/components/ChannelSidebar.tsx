import { useEffect, useState } from "react";
import { useNavigate, useParams } from "react-router-dom";
import { useChannelStore } from "../stores/channelStore.ts";
import { useServerStore } from "../stores/serverStore.ts";
import { useAuthStore } from "../stores/authStore.ts";
import { useVoiceStore } from "../stores/voiceStore.ts";
import { getSocket } from "../api/socket.ts";
import VoiceChannelItem from "./VoiceChannelItem.tsx";

export default function ChannelSidebar() {
  const channels = useChannelStore((s) => s.channels);
  const currentChannelId = useChannelStore((s) => s.currentChannelId);
  const fetchChannels = useChannelStore((s) => s.fetchChannels);
  const createChannel = useChannelStore((s) => s.createChannel);
  const user = useAuthStore((s) => s.user);
  const logout = useAuthStore((s) => s.logout);
  const navigate = useNavigate();

  const servers = useServerStore((s) => s.servers);
  const currentServerId = useServerStore((s) => s.currentServerId);
  const { serverId } = useParams<{ serverId?: string }>();

  const [showCreate, setShowCreate] = useState(false);
  const [newChannelName, setNewChannelName] = useState("");
  const [isPrivate, setIsPrivate] = useState(false);

  // Sync URL param with store
  useEffect(() => {
    if (serverId && serverId !== currentServerId) {
      useServerStore.getState().selectServer(serverId);
    }
  }, [serverId, currentServerId]);

  useEffect(() => {
    fetchChannels(currentServerId ?? undefined);
  }, [fetchChannels, currentServerId]);

  const currentServer = servers.find((s) => s.id === currentServerId);
  const joinVoice = useVoiceStore((s) => s.joinVoice);

  const publicChannels = channels.filter((ch) => ch.type !== "private" && ch.type !== "voice");
  const privateChannels = channels.filter((ch) => ch.type === "private");
  const voiceChannels = channels.filter((ch) => ch.type === "voice");

  async function handleCreateChannel() {
    const name = newChannelName.trim();
    if (!name) return;
    try {
      const channel = await createChannel(
        name,
        isPrivate ? "private" : "public",
        undefined,
        currentServerId ?? undefined,
      );
      setNewChannelName("");
      setIsPrivate(false);
      setShowCreate(false);
      if (currentServerId) {
        navigate(`/servers/${currentServerId}/channels/${channel.id}`);
      } else {
        navigate(`/channels/${channel.id}`);
      }
    } catch (err) {
      console.error("Failed to create channel:", err);
    }
  }

  function handleLogout() {
    logout();
    navigate("/login");
  }

  function channelPath(channelId: string) {
    if (currentServerId) {
      return `/servers/${currentServerId}/channels/${channelId}`;
    }
    return `/channels/${channelId}`;
  }

  return (
    <div className="channel-sidebar">
      <div className="sidebar-header">
        <h3>{currentServer?.name || "Direct Messages"}</h3>
        <button
          className="btn-settings"
          onClick={() => navigate("/settings")}
          title="Settings"
        >
          &#9881;
        </button>
      </div>
      <div className="channel-list">
        {publicChannels.length > 0 && (
          <div className="channel-section">
            <div className="channel-section-header">Channels</div>
            {publicChannels.map((ch) => (
              <button
                key={ch.id}
                className={`channel-item ${ch.id === currentChannelId ? "active" : ""}`}
                onClick={() => navigate(channelPath(ch.id))}
              >
                # {ch.name}
              </button>
            ))}
          </div>
        )}
        {voiceChannels.length > 0 && (
          <div className="channel-section">
            <div className="channel-section-header">Voice</div>
            {voiceChannels.map((ch) => (
              <VoiceChannelItem
                key={ch.id}
                channel={ch}
                isActive={ch.id === currentChannelId}
                onClick={() => navigate(channelPath(ch.id))}
                onJoinVoice={() => {
                  const socket = getSocket();
                  if (socket) joinVoice(ch.id, socket);
                }}
              />
            ))}
          </div>
        )}
        {privateChannels.length > 0 && (
          <div className="channel-section">
            <div className="channel-section-header">Private</div>
            {privateChannels.map((ch) => (
              <button
                key={ch.id}
                className={`channel-item ${ch.id === currentChannelId ? "active" : ""}`}
                onClick={() => navigate(channelPath(ch.id))}
              >
                <span className="channel-lock">&#128274;</span> {ch.name}
              </button>
            ))}
          </div>
        )}
      </div>
      <div className="sidebar-actions">
        {showCreate ? (
          <div className="create-channel-form">
            <input
              type="text"
              value={newChannelName}
              onChange={(e) => setNewChannelName(e.target.value)}
              placeholder="Channel name"
              autoFocus
              onKeyDown={(e) => {
                if (e.key === "Enter") handleCreateChannel();
                if (e.key === "Escape") setShowCreate(false);
              }}
            />
            <label className="private-toggle">
              <input
                type="checkbox"
                checked={isPrivate}
                onChange={(e) => setIsPrivate(e.target.checked)}
              />
              <span>Private (E2E Encrypted)</span>
            </label>
            <div className="create-channel-buttons">
              <button onClick={handleCreateChannel}>Create</button>
              <button onClick={() => setShowCreate(false)}>Cancel</button>
            </div>
          </div>
        ) : (
          <button
            className="btn-create-channel"
            onClick={() => setShowCreate(true)}
          >
            + New Channel
          </button>
        )}
      </div>
      <div className="sidebar-user">
        <span className="user-name">
          {user?.display_name || user?.username || "User"}
        </span>
        <button className="btn-logout" onClick={handleLogout}>
          Logout
        </button>
      </div>
    </div>
  );
}
