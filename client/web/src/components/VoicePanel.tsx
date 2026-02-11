import { useVoiceStore } from "../stores/voiceStore.ts";
import { useAuthStore } from "../stores/authStore.ts";
import VideoGrid from "./VideoGrid.tsx";

export default function VoicePanel() {
  const connected = useVoiceStore((s) => s.connected);
  const peers = useVoiceStore((s) => s.peers);
  const muted = useVoiceStore((s) => s.muted);
  const deafened = useVoiceStore((s) => s.deafened);
  const speaking = useVoiceStore((s) => s.speaking);
  const currentUser = useAuthStore((s) => s.user);

  if (!connected) {
    return (
      <div className="voice-panel">
        <div className="voice-panel-empty">
          <p>Click "Join Voice" to connect to this voice channel.</p>
        </div>
      </div>
    );
  }

  const peerList = Array.from(peers.values());

  const hasVideo = peerList.some((p) => p.videoTrack || p.screenSharing);

  return (
    <div className="voice-panel">
      {hasVideo && <VideoGrid />}
      <div className="voice-participants">
        {/* Current user */}
        <div className={`voice-participant ${speaking ? "speaking" : ""}`}>
          <div className="voice-participant-avatar">
            {currentUser?.username?.[0]?.toUpperCase() || "?"}
          </div>
          <span className="voice-participant-name">
            {currentUser?.display_name || currentUser?.username || "You"}
          </span>
          <div className="voice-participant-indicators">
            {muted && <span className="indicator-muted" title="Muted">M</span>}
            {deafened && <span className="indicator-deafened" title="Deafened">D</span>}
          </div>
        </div>

        {/* Remote peers */}
        {peerList.map((peer) => (
          <div
            key={peer.userId}
            className={`voice-participant ${peer.speaking ? "speaking" : ""}`}
          >
            <div className="voice-participant-avatar">
              {peer.userId[0]?.toUpperCase() || "?"}
            </div>
            <span className="voice-participant-name">{peer.userId}</span>
            <div className="voice-participant-indicators">
              {peer.muted && <span className="indicator-muted" title="Muted">M</span>}
              {peer.deafened && <span className="indicator-deafened" title="Deafened">D</span>}
            </div>
          </div>
        ))}
      </div>
    </div>
  );
}
