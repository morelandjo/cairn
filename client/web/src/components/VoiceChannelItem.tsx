import { useVoiceStore } from "../stores/voiceStore.ts";

interface VoiceChannelItemProps {
  channel: { id: string; name: string };
  isActive: boolean;
  onClick: () => void;
  onJoinVoice: () => void;
}

export default function VoiceChannelItem({
  channel,
  isActive,
  onClick,
  onJoinVoice,
}: VoiceChannelItemProps) {
  const connected = useVoiceStore((s) => s.connected);
  const connectedChannelId = useVoiceStore((s) => s.channelId);
  const peers = useVoiceStore((s) => s.peers);

  const isConnectedHere = connected && connectedChannelId === channel.id;
  const peerCount = isConnectedHere ? peers.size + 1 : 0; // +1 for self

  return (
    <div className={`voice-channel-item ${isActive ? "active" : ""}`}>
      <button className="voice-channel-name" onClick={onClick}>
        <span className="voice-icon">&#128266;</span> {channel.name}
        {peerCount > 0 && (
          <span className="voice-peer-count">({peerCount})</span>
        )}
      </button>
      {!isConnectedHere && (
        <button
          className="voice-join-btn"
          onClick={(e) => {
            e.stopPropagation();
            onJoinVoice();
          }}
          title="Join Voice"
        >
          Join
        </button>
      )}
    </div>
  );
}
