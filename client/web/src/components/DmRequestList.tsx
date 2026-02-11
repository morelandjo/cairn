/**
 * List of pending DM requests with accept/reject/block actions.
 */

import { useEffect } from "react";
import { useDmStore } from "../stores/dmStore.ts";

interface Props {
  onClose: () => void;
}

export default function DmRequestList({ onClose }: Props) {
  const receivedRequests = useDmStore((s) => s.receivedRequests);
  const fetchReceivedRequests = useDmStore((s) => s.fetchReceivedRequests);
  const acceptRequest = useDmStore((s) => s.acceptRequest);
  const rejectRequest = useDmStore((s) => s.rejectRequest);
  const blockRequest = useDmStore((s) => s.blockRequest);
  const loading = useDmStore((s) => s.loading);

  useEffect(() => {
    fetchReceivedRequests();
  }, [fetchReceivedRequests]);

  return (
    <div className="dm-request-list-panel">
      <div className="dm-request-list-header">
        <h3>DM Requests</h3>
        <button className="modal-close" onClick={onClose}>
          &times;
        </button>
      </div>
      <div className="dm-request-list-body">
        {loading && <p className="dm-request-loading">Loading...</p>}
        {!loading && receivedRequests.length === 0 && (
          <p className="dm-request-empty">No pending DM requests.</p>
        )}
        {receivedRequests.map((request) => (
          <div key={request.id} className="dm-request-item">
            <div className="dm-request-info">
              <span className="dm-request-sender">
                {request.sender_display_name || request.sender_username || "Unknown"}
              </span>
              <span className="dm-request-instance">
                @{request.recipient_instance}
              </span>
              <span className="dm-request-time">
                {new Date(request.inserted_at).toLocaleDateString()}
              </span>
            </div>
            <div className="dm-request-actions">
              <button
                className="btn-accept"
                onClick={() => acceptRequest(request.id)}
                title="Accept DM request"
              >
                Accept
              </button>
              <button
                className="btn-reject"
                onClick={() => rejectRequest(request.id)}
                title="Decline DM request"
              >
                Decline
              </button>
              <button
                className="btn-block"
                onClick={() => blockRequest(request.id)}
                title="Block this user from sending DM requests"
              >
                Block
              </button>
            </div>
          </div>
        ))}
      </div>
    </div>
  );
}
