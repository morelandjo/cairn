import { supportsInsertableStreams } from "@murmuring/proto";

interface VoiceE2EWarningProps {
  onConsent: () => void;
  onCancel: () => void;
}

export default function VoiceE2EWarning({
  onConsent,
  onCancel,
}: VoiceE2EWarningProps) {
  const supported = supportsInsertableStreams();

  if (supported) return null;

  return (
    <div className="voice-e2e-warning-overlay">
      <div className="voice-e2e-warning">
        <h3>End-to-End Encryption Not Available</h3>
        <p>
          Your browser does not support Insertable Streams, which is required
          for end-to-end encrypted voice. Your audio will be encrypted in
          transit (DTLS-SRTP) but will not have end-to-end encryption.
        </p>
        <p>
          For full E2E encryption, use a Chromium-based browser (Chrome, Edge,
          Brave).
        </p>
        <div className="voice-e2e-warning-actions">
          <button className="btn-primary" onClick={onConsent}>
            Join Anyway
          </button>
          <button onClick={onCancel}>Cancel</button>
        </div>
      </div>
    </div>
  );
}
