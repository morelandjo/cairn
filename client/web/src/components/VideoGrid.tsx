import { useVoiceStore } from "../stores/voiceStore.ts";
import VideoTile from "./VideoTile.tsx";

export default function VideoGrid() {
  const peers = useVoiceStore((s) => s.peers);

  const videoPeers = Array.from(peers.values()).filter(
    (p) => p.videoTrack || p.screenSharing,
  );

  if (videoPeers.length === 0) return null;

  // Find screen sharer for spotlight layout
  const screenSharer = videoPeers.find((p) => p.screenSharing);
  const gridClass = screenSharer
    ? "video-grid spotlight"
    : `video-grid grid-${Math.min(videoPeers.length, 4)}`;

  return (
    <div className={gridClass}>
      {screenSharer && (
        <div className="video-spotlight">
          <VideoTile peer={screenSharer} large />
        </div>
      )}
      <div className="video-tiles">
        {videoPeers
          .filter((p) => p !== screenSharer)
          .map((peer) => (
            <VideoTile key={peer.userId} peer={peer} />
          ))}
      </div>
    </div>
  );
}
