import { useEffect, useState } from "react";
import * as channelsApi from "../api/channels.ts";
import type { Message } from "../api/channels.ts";

interface Props {
  channelId: string;
  messageId: string;
  onClose: () => void;
}

export default function ThreadView({ channelId, messageId, onClose }: Props) {
  const [parent, setParent] = useState<Message | null>(null);
  const [replies, setReplies] = useState<Message[]>([]);
  const [loading, setLoading] = useState(true);

  useEffect(() => {
    channelsApi
      .getThread(channelId, messageId)
      .then((data) => {
        setParent(data.parent);
        setReplies(data.replies);
      })
      .catch(console.error)
      .finally(() => setLoading(false));
  }, [channelId, messageId]);

  function formatTime(iso: string): string {
    return new Date(iso).toLocaleTimeString([], {
      hour: "2-digit",
      minute: "2-digit",
    });
  }

  return (
    <div className="thread-panel">
      <div className="panel-header">
        <h3>Thread</h3>
        <button className="btn-close" onClick={onClose}>
          &times;
        </button>
      </div>
      {loading && <div className="loading">Loading...</div>}
      {parent && (
        <div className="thread-content">
          <div className="thread-parent">
            <div className="message-header">
              <span className="message-author">
                {parent.author_display_name || parent.author_username}
              </span>
              <span className="message-time">
                {formatTime(parent.inserted_at)}
              </span>
            </div>
            <div className="message-content">{parent.content}</div>
          </div>
          <div className="thread-divider">
            {replies.length} {replies.length === 1 ? "reply" : "replies"}
          </div>
          <div className="thread-replies">
            {replies.map((reply) => (
              <div key={reply.id} className="message thread-reply">
                <div className="message-header">
                  <span className="message-author">
                    {reply.author_display_name || reply.author_username}
                  </span>
                  <span className="message-time">
                    {formatTime(reply.inserted_at)}
                  </span>
                </div>
                <div className="message-content">{reply.content}</div>
              </div>
            ))}
          </div>
        </div>
      )}
    </div>
  );
}
