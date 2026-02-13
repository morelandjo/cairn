import { useVoiceStore } from "../stores/voiceStore.ts";
import { useChannelStore } from "../stores/channelStore.ts";

export default function VoiceConnectionBar() {
  const connected = useVoiceStore((s) => s.connected);
  const channelId = useVoiceStore((s) => s.channelId);
  const muted = useVoiceStore((s) => s.muted);
  const deafened = useVoiceStore((s) => s.deafened);
  const speaking = useVoiceStore((s) => s.speaking);
  const toggleMute = useVoiceStore((s) => s.toggleMute);
  const toggleDeafen = useVoiceStore((s) => s.toggleDeafen);
  const leaveVoice = useVoiceStore((s) => s.leaveVoice);
  const channels = useChannelStore((s) => s.channels);

  if (!connected) return null;

  const channel = channels.find((c) => c.id === channelId);

  return (
    <div className={`voice-connection-bar ${speaking ? "speaking" : ""}`}>
      <div className="voice-connection-info">
        <span className="voice-connected-label">Voice Connected</span>
        <span className="voice-channel-name">{channel?.name || "Voice"}</span>
      </div>
      <div className="voice-controls">
        <button
          className={`voice-btn ${muted ? "active" : ""}`}
          onClick={toggleMute}
          title={muted ? "Unmute" : "Mute"}
        >
          {muted ? "Unmute" : "Mute"}
        </button>
        <button
          className={`voice-btn ${deafened ? "active" : ""}`}
          onClick={toggleDeafen}
          title={deafened ? "Undeafen" : "Deafen"}
        >
          {deafened ? "Undeafen" : "Deafen"}
        </button>
        <button
          className="voice-btn voice-btn-disconnect"
          onClick={leaveVoice}
          title="Disconnect"
        >
          Disconnect
        </button>
      </div>
    </div>
  );
}
