import { useEffect, useRef } from "react";
import type { VoicePeer } from "../stores/voiceStore.ts";

interface VideoTileProps {
  peer: VoicePeer;
  large?: boolean;
}

export default function VideoTile({ peer, large }: VideoTileProps) {
  const videoRef = useRef<HTMLVideoElement>(null);

  useEffect(() => {
    if (videoRef.current && peer.videoTrack) {
      videoRef.current.srcObject = new MediaStream([peer.videoTrack]);
    }
    return () => {
      if (videoRef.current) {
        videoRef.current.srcObject = null;
      }
    };
  }, [peer.videoTrack]);

  return (
    <div
      className={`video-tile ${large ? "large" : ""} ${peer.speaking ? "speaking" : ""}`}
    >
      {peer.videoTrack ? (
        <video ref={videoRef} autoPlay playsInline muted />
      ) : (
        <div className="video-tile-placeholder">
          <span className="video-tile-avatar">
            {peer.userId[0]?.toUpperCase() || "?"}
          </span>
        </div>
      )}
      <div className="video-tile-info">
        <span className="video-tile-name">{peer.userId}</span>
        {peer.muted && <span className="indicator-muted">M</span>}
        {peer.speaking && <span className="indicator-speaking" />}
      </div>
    </div>
  );
}
