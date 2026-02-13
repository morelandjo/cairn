import { useRef, useEffect, useCallback, useState } from "react";
import { useChannelStore } from "../stores/channelStore.ts";
import { useAuthStore } from "../stores/authStore.ts";
import { removeReaction as socketRemoveReaction } from "../api/socket.ts";
import ReactionPicker from "./ReactionPicker.tsx";

export default function MessageList() {
  const messages = useChannelStore((s) => s.messages);
  const currentChannelId = useChannelStore((s) => s.currentChannelId);
  const fetchMessages = useChannelStore((s) => s.fetchMessages);
  const isLoadingMessages = useChannelStore((s) => s.isLoadingMessages);
  const hasMoreMessages = useChannelStore((s) => s.hasMoreMessages);
  const setReplyingTo = useChannelStore((s) => s.setReplyingTo);
  const currentUser = useAuthStore((s) => s.user);

  const [reactionPickerMsgId, setReactionPickerMsgId] = useState<string | null>(null);

  const bottomRef = useRef<HTMLDivElement>(null);
  const listRef = useRef<HTMLDivElement>(null);
  const prevMessageCount = useRef(0);

  // Auto-scroll to bottom when new messages arrive
  useEffect(() => {
    if (messages.length > prevMessageCount.current) {
      const isNewMessage = messages.length - prevMessageCount.current <= 2;
      if (isNewMessage) {
        bottomRef.current?.scrollIntoView({ behavior: "smooth" });
      }
    }
    prevMessageCount.current = messages.length;
  }, [messages.length]);

  // Scroll to bottom on channel switch
  useEffect(() => {
    bottomRef.current?.scrollIntoView();
    prevMessageCount.current = messages.length;
  }, [currentChannelId, messages.length]);

  const handleScroll = useCallback(() => {
    const el = listRef.current;
    if (!el || isLoadingMessages || !hasMoreMessages || !currentChannelId) return;
    if (el.scrollTop < 100 && messages.length > 0) {
      const oldestMessage = messages[0];
      fetchMessages(currentChannelId, oldestMessage.inserted_at);
    }
  }, [isLoadingMessages, hasMoreMessages, currentChannelId, messages, fetchMessages]);

  function formatTime(iso: string): string {
    const d = new Date(iso);
    return d.toLocaleTimeString([], { hour: "2-digit", minute: "2-digit" });
  }

  return (
    <div className="message-list" ref={listRef} onScroll={handleScroll}>
      {isLoadingMessages && (
        <div className="loading-more">Loading older messages...</div>
      )}
      {messages.map((msg) => {
        const isOwn = msg.author_id === currentUser?.id;
        const displayName =
          msg.author_display_name || msg.author_username || "Unknown";
        return (
          <div key={msg.id} className={`message ${isOwn ? "message-own" : ""}`}>
            {msg.reply_to && (
              <div className="message-reply-ref">
                <span className="reply-icon">&#8617;</span>
                <span className="reply-author">{msg.reply_to.author_username}</span>
                <span className="reply-snippet">
                  {msg.reply_to.content_snippet || "..."}
                </span>
              </div>
            )}
            <div className="message-header">
              <span className="message-author">
                {displayName}
                {msg.home_instance && (
                  <span className="message-author-instance" title={`From ${msg.home_instance}`}>
                    @{msg.home_instance}
                  </span>
                )}
                {msg.is_bot && <span className="bot-badge">BOT</span>}
                {msg.is_federated && (
                  <span className="federated-badge" title="Federated message">
                    <svg width="12" height="12" viewBox="0 0 24 24" fill="currentColor" style={{ opacity: 0.5, verticalAlign: "middle", marginLeft: 4 }}>
                      <path d="M12 2C6.48 2 2 6.48 2 12s4.48 10 10 10 10-4.48 10-10S17.52 2 12 2zm-1 17.93c-3.95-.49-7-3.85-7-7.93 0-.62.08-1.21.21-1.79L9 15v1c0 1.1.9 2 2 2v1.93zm6.9-2.54c-.26-.81-1-1.39-1.9-1.39h-1v-3c0-.55-.45-1-1-1H8v-2h2c.55 0 1-.45 1-1V7h2c1.1 0 2-.9 2-2v-.41c2.93 1.19 5 4.06 5 7.41 0 2.08-.8 3.97-2.1 5.39z" />
                    </svg>
                  </span>
                )}
              </span>
              <span className="message-time">{formatTime(msg.inserted_at)}</span>
              {msg.edited_at && <span className="message-edited">(edited)</span>}
              <div className="message-actions">
                <button
                  className="btn-action"
                  title="Reply"
                  onClick={() => setReplyingTo(msg)}
                >
                  &#8617;
                </button>
                <button
                  className="btn-action"
                  title="React"
                  onClick={() =>
                    setReactionPickerMsgId(
                      reactionPickerMsgId === msg.id ? null : msg.id,
                    )
                  }
                >
                  +
                </button>
              </div>
            </div>
            <div
              className={`message-content ${msg.content === "[Unable to decrypt]" ? "message-decrypt-failed" : ""}`}
            >
              {msg.deleted_at ? (
                <em>Message deleted</em>
              ) : msg.content === "[Unable to decrypt]" ? (
                <em className="decrypt-error">Unable to decrypt message</em>
              ) : (
                msg.content
              )}
            </div>
            {msg.reactions && msg.reactions.length > 0 && (
              <div className="message-reactions">
                {msg.reactions.map((r) => (
                  <button
                    key={r.emoji}
                    className="reaction-chip"
                    onClick={() => {
                      if (currentChannelId) {
                        socketRemoveReaction(msg.id, r.emoji);
                      }
                    }}
                    title={`${r.emoji} (${r.count})`}
                  >
                    {r.emoji} {r.count}
                  </button>
                ))}
              </div>
            )}
            {reactionPickerMsgId === msg.id && (
              <ReactionPicker
                messageId={msg.id}
                onClose={() => setReactionPickerMsgId(null)}
              />
            )}
          </div>
        );
      })}
      <div ref={bottomRef} />
    </div>
  );
}
