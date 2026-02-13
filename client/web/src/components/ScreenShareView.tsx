import { useVoiceStore } from "../stores/voiceStore.ts";

export default function ScreenShareView() {
  const screenSharing = useVoiceStore((s) => s.screenSharing);

  if (!screenSharing) return null;

  return (
    <div className="screen-share-controls">
      <span className="screen-share-label">You are sharing your screen</span>
      <button
        className="voice-btn voice-btn-disconnect"
        onClick={() => {
          // Stop screen share is handled by voiceStore
          // For now, this acts as a visual indicator
        }}
      >
        Stop Sharing
      </button>
    </div>
  );
}
