import { useEffect, useState } from "react";
import { useParams } from "react-router-dom";
import { useChannelStore } from "../stores/channelStore.ts";
import { useServerStore } from "../stores/serverStore.ts";
import { useVoiceStore } from "../stores/voiceStore.ts";
import { useDmStore } from "../stores/dmStore.ts";
import { getSocket } from "../api/socket.ts";
import MessageList from "../components/MessageList.tsx";
import MessageInput from "../components/MessageInput.tsx";
import TypingIndicator from "../components/TypingIndicator.tsx";
import InviteModal from "../components/InviteModal.tsx";
import PinnedMessages from "../components/PinnedMessages.tsx";
import SearchResults from "../components/SearchResults.tsx";
import VoicePanel from "../components/VoicePanel.tsx";
import DmRequestList from "../components/DmRequestList.tsx";

export default function ChannelView() {
  const { id } = useParams<{ id: string }>();
  const selectChannel = useChannelStore((s) => s.selectChannel);
  const currentChannelId = useChannelStore((s) => s.currentChannelId);
  const channels = useChannelStore((s) => s.channels);
  const currentServerId = useServerStore((s) => s.currentServerId);
  const [showInvite, setShowInvite] = useState(false);
  const [showPins, setShowPins] = useState(false);
  const [showSearch, setShowSearch] = useState(false);
  const [showDmRequests, setShowDmRequests] = useState(false);
  const dmRequestCount = useDmStore((s) => s.receivedRequests.length);

  useEffect(() => {
    if (id && id !== currentChannelId) {
      selectChannel(id);
    }
  }, [id, currentChannelId, selectChannel]);

  const joinVoice = useVoiceStore((s) => s.joinVoice);
  const voiceConnected = useVoiceStore((s) => s.connected);
  const voiceChannelId = useVoiceStore((s) => s.channelId);

  const currentChannel = channels.find((c) => c.id === id);
  const isVoiceChannel = currentChannel?.type === "voice";
  const isConnectedToThis = voiceConnected && voiceChannelId === id;

  return (
    <div className="channel-view">
      <div className="channel-header">
        <h2>
          {currentChannel?.type === "private"
            ? "\u{1F512} "
            : currentChannel?.type === "voice"
              ? "\u{1F50A} "
              : "# "}
          {currentChannel?.name ?? "Loading..."}
        </h2>
        {currentChannel?.type === "private" && (
          <span className="channel-encrypted-badge">E2E Encrypted</span>
        )}
        {currentChannel?.description && (
          <span className="channel-description">
            {currentChannel.description}
          </span>
        )}
        <div className="channel-header-actions">
          {currentServerId && (
            <button
              className="btn-search"
              onClick={() => setShowSearch(!showSearch)}
              title="Search messages"
            >
              &#128269;
            </button>
          )}
          <button
            className="btn-pins"
            onClick={() => setShowPins(!showPins)}
            title="Pinned messages"
          >
            &#128204;
          </button>
          <button
            className="btn-dm-requests"
            onClick={() => setShowDmRequests(!showDmRequests)}
            title="DM Requests"
          >
            DM Requests{dmRequestCount > 0 ? ` (${dmRequestCount})` : ""}
          </button>
          <button
            className="btn-invite"
            onClick={() => setShowInvite(true)}
            title="Invite people"
          >
            Invite
          </button>
        </div>
      </div>
      <div className="channel-body">
        {isVoiceChannel ? (
          <div className="channel-main voice-main">
            {!isConnectedToThis && (
              <div className="voice-join-prompt">
                <button
                  className="voice-join-prompt-btn"
                  onClick={() => {
                    const socket = getSocket();
                    if (socket && id) joinVoice(id, socket);
                  }}
                >
                  Join Voice Channel
                </button>
              </div>
            )}
            <VoicePanel />
          </div>
        ) : (
        <div className="channel-main">
          <MessageList />
          <TypingIndicator />
          <MessageInput />
        </div>
        )}
        {showPins && id && (
          <PinnedMessages
            channelId={id}
            onClose={() => setShowPins(false)}
          />
        )}
        {showSearch && currentServerId && (
          <SearchResults
            serverId={currentServerId}
            onClose={() => setShowSearch(false)}
          />
        )}
      </div>
      {showDmRequests && (
        <DmRequestList onClose={() => setShowDmRequests(false)} />
      )}
      {showInvite && id && (
        <InviteModal channelId={id} onClose={() => setShowInvite(false)} />
      )}
    </div>
  );
}
