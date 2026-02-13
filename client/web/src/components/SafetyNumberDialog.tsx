interface SafetyNumberDialogProps {
  localFingerprint: string;
  remoteFingerprint: string;
  peerName: string;
  onClose: () => void;
  onVerified: () => void;
}

function formatFingerprint(fp: string): string {
  // Group into blocks of 5 characters for readability
  return fp
    .replace(/\s/g, "")
    .match(/.{1,5}/g)
    ?.join(" ") ?? fp;
}

export default function SafetyNumberDialog({
  localFingerprint,
  remoteFingerprint,
  peerName,
  onClose,
  onVerified,
}: SafetyNumberDialogProps) {
  return (
    <div className="modal-backdrop" onClick={onClose}>
      <div className="modal-content safety-number-dialog" onClick={(e) => e.stopPropagation()}>
        <div className="modal-header">
          <h3>Verify Safety Number</h3>
          <button className="btn-close" onClick={onClose}>
            x
          </button>
        </div>
        <div className="modal-body">
          <p>
            Compare these safety numbers with <strong>{peerName}</strong> using
            a trusted channel (e.g., in person or a phone call).
          </p>
          <div className="safety-numbers">
            <div className="safety-number-block">
              <label>Your fingerprint</label>
              <code>{formatFingerprint(localFingerprint)}</code>
            </div>
            <div className="safety-number-block">
              <label>{peerName}'s fingerprint</label>
              <code>{formatFingerprint(remoteFingerprint)}</code>
            </div>
          </div>
          <p className="safety-number-hint">
            If the numbers match on both devices, your communication is
            end-to-end encrypted and not being intercepted.
          </p>
          <div className="safety-number-actions">
            <button className="btn-primary" onClick={onVerified}>
              I have verified
            </button>
            <button className="btn-secondary" onClick={onClose}>
              Close
            </button>
          </div>
        </div>
      </div>
    </div>
  );
}
