import { useState } from "react";
import { createInvite } from "../api/invites.ts";

interface InviteModalProps {
  channelId: string;
  onClose: () => void;
}

export default function InviteModal({ channelId, onClose }: InviteModalProps) {
  const [inviteCode, setInviteCode] = useState<string | null>(null);
  const [maxUses, setMaxUses] = useState("");
  const [isCreating, setIsCreating] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const [copied, setCopied] = useState(false);

  async function handleCreate() {
    setIsCreating(true);
    setError(null);
    try {
      const opts: { channel_id: string; max_uses?: number } = {
        channel_id: channelId,
      };
      if (maxUses) {
        opts.max_uses = parseInt(maxUses, 10);
      }
      const data = await createInvite(opts);
      setInviteCode(data.invite.code);
    } catch (err) {
      const message = err instanceof Error ? err.message : "Failed to create invite";
      setError(message);
    } finally {
      setIsCreating(false);
    }
  }

  function handleCopy() {
    if (!inviteCode) return;
    const url = `${window.location.origin}/invite/${inviteCode}`;
    navigator.clipboard.writeText(url).then(() => {
      setCopied(true);
      setTimeout(() => setCopied(false), 2000);
    });
  }

  return (
    <div className="modal-backdrop" onClick={onClose}>
      <div className="modal-content" onClick={(e) => e.stopPropagation()}>
        <div className="modal-header">
          <h3>Invite People</h3>
          <button className="btn-close" onClick={onClose}>
            x
          </button>
        </div>
        <div className="modal-body">
          {inviteCode ? (
            <>
              <p>Share this invite link:</p>
              <div className="invite-link-display">
                <code>{window.location.origin}/invite/{inviteCode}</code>
                <button onClick={handleCopy} className="btn-copy">
                  {copied ? "Copied!" : "Copy"}
                </button>
              </div>
            </>
          ) : (
            <>
              <div className="form-group">
                <label htmlFor="max-uses">Max Uses (optional)</label>
                <input
                  id="max-uses"
                  type="number"
                  min="1"
                  value={maxUses}
                  onChange={(e) => setMaxUses(e.target.value)}
                  placeholder="Unlimited"
                />
              </div>
              {error && <div className="form-error">{error}</div>}
              <button
                className="btn-primary"
                onClick={handleCreate}
                disabled={isCreating}
              >
                {isCreating ? "Creating..." : "Create Invite Link"}
              </button>
            </>
          )}
        </div>
      </div>
    </div>
  );
}
