/**
 * Dialog for initiating a cross-instance DM with a federated user.
 */

import { useState } from "react";
import { useDmStore } from "../stores/dmStore.ts";

interface Props {
  recipientDid: string;
  recipientInstance: string;
  recipientName: string;
  recipientInsecure?: boolean;
  onClose: () => void;
}

export default function FederatedDmDialog({
  recipientDid,
  recipientInstance,
  recipientName,
  recipientInsecure,
  onClose,
}: Props) {
  const initiateDm = useDmStore((s) => s.initiateDm);
  const [sending, setSending] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const [success, setSuccess] = useState(false);

  async function handleSend() {
    setSending(true);
    setError(null);
    const result = await initiateDm(recipientDid, recipientInstance);
    setSending(false);

    if (result) {
      setSuccess(true);
    } else {
      setError("Failed to send DM request. Please try again.");
    }
  }

  return (
    <div className="modal-overlay" onClick={onClose}>
      <div className="modal-content" onClick={(e) => e.stopPropagation()}>
        <div className="modal-header">
          <h3>Send DM Request</h3>
          <button className="modal-close" onClick={onClose}>
            &times;
          </button>
        </div>
        <div className="modal-body">
          {success ? (
            <div className="dm-request-success">
              <p>DM request sent to <strong>{recipientName}</strong>!</p>
              <p className="dm-request-hint">
                They will receive a notification on their home instance
                ({recipientInstance}). Once they accept, you can exchange
                encrypted messages.
              </p>
              <button className="btn-primary" onClick={onClose}>
                Done
              </button>
            </div>
          ) : (
            <>
              <p>
                Send a DM request to <strong>{recipientName}</strong> on{" "}
                <strong>{recipientInstance}</strong>?
              </p>
              {recipientInsecure && (
                <div className="insecure-dm-warning">
                  <span className="insecure-dm-warning-icon">&#x26A0;</span>
                  <span>
                    This user's server does not use HTTPS. DM request metadata
                    will be sent over an unencrypted connection.
                  </span>
                </div>
              )}
              <p className="dm-request-hint">
                This will create an encrypted DM channel on your instance.
                The recipient must accept before messages can be exchanged.
              </p>
              {error && <p className="dm-request-error">{error}</p>}
              <div className="modal-actions">
                <button
                  className="btn-secondary"
                  onClick={onClose}
                  disabled={sending}
                >
                  Cancel
                </button>
                <button
                  className="btn-primary"
                  onClick={handleSend}
                  disabled={sending}
                >
                  {sending ? "Sending..." : "Send Request"}
                </button>
              </div>
            </>
          )}
        </div>
      </div>
    </div>
  );
}
