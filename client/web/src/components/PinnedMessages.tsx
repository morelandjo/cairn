import { useEffect, useState } from "react";
import * as channelsApi from "../api/channels.ts";
import type { Message } from "../api/channels.ts";

interface Pin {
  id: string;
  message_id: string;
  pinned_by_id: string;
  inserted_at: string;
  message: Message;
}

interface Props {
  channelId: string;
  onClose: () => void;
}

export default function PinnedMessages({ channelId, onClose }: Props) {
  const [pins, setPins] = useState<Pin[]>([]);
  const [loading, setLoading] = useState(true);

  useEffect(() => {
    channelsApi
      .listPins(channelId)
      .then((data) => setPins(data.pins))
      .catch(console.error)
      .finally(() => setLoading(false));
  }, [channelId]);

  async function handleUnpin(messageId: string) {
    try {
      await channelsApi.unpinMessage(channelId, messageId);
      setPins((prev) => prev.filter((p) => p.message_id !== messageId));
    } catch (err) {
      console.error("Failed to unpin:", err);
    }
  }

  return (
    <div className="pinned-messages-panel">
      <div className="panel-header">
        <h3>Pinned Messages</h3>
        <button className="btn-close" onClick={onClose}>
          &times;
        </button>
      </div>
      <div className="pinned-list">
        {loading && <div className="loading">Loading...</div>}
        {!loading && pins.length === 0 && (
          <div className="empty-state">No pinned messages</div>
        )}
        {pins.map((pin) => (
          <div key={pin.id} className="pinned-message">
            <div className="pinned-message-header">
              <span className="pinned-author">
                {pin.message.author_display_name || pin.message.author_username}
              </span>
              <span className="pinned-time">
                {new Date(pin.message.inserted_at).toLocaleString()}
              </span>
            </div>
            <div className="pinned-message-content">
              {pin.message.content}
            </div>
            <button
              className="btn-unpin"
              onClick={() => handleUnpin(pin.message_id)}
            >
              Unpin
            </button>
          </div>
        ))}
      </div>
    </div>
  );
}
