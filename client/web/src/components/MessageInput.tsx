import { useState, useRef } from "react";
import type { FormEvent, KeyboardEvent } from "react";
import { useChannelStore } from "../stores/channelStore.ts";
import { sendTyping } from "../api/socket.ts";
import FileUpload from "./FileUpload.tsx";
import { getFileUrl } from "../api/upload.ts";

export default function MessageInput() {
  const [content, setContent] = useState("");
  const sendMessage = useChannelStore((s) => s.sendMessage);
  const replyingTo = useChannelStore((s) => s.replyingTo);
  const setReplyingTo = useChannelStore((s) => s.setReplyingTo);
  const lastTypingSent = useRef(0);

  function doSend() {
    const trimmed = content.trim();
    if (!trimmed) return;
    sendMessage(trimmed);
    setContent("");
  }

  function handleSubmit(e: FormEvent) {
    e.preventDefault();
    doSend();
  }

  function handleKeyDown(e: KeyboardEvent<HTMLTextAreaElement>) {
    if (e.key === "Enter" && !e.shiftKey) {
      e.preventDefault();
      doSend();
    }
    if (e.key === "Escape" && replyingTo) {
      setReplyingTo(null);
    }
  }

  function handleChange(value: string) {
    setContent(value);
    const now = Date.now();
    if (now - lastTypingSent.current > 2000) {
      lastTypingSent.current = now;
      sendTyping();
    }
  }

  function handleFileUploaded(file: { id: string; filename: string }) {
    const url = getFileUrl(file.id);
    sendMessage(`[${file.filename}](${url})`);
  }

  return (
    <div className="message-input-wrapper">
      {replyingTo && (
        <div className="reply-preview">
          <span className="reply-icon">&#8617;</span>
          <span>
            Replying to{" "}
            <strong>
              {replyingTo.author_display_name || replyingTo.author_username}
            </strong>
          </span>
          <button
            className="btn-cancel-reply"
            onClick={() => setReplyingTo(null)}
          >
            &times;
          </button>
        </div>
      )}
      <form className="message-input" onSubmit={handleSubmit}>
        <FileUpload onUploaded={handleFileUploaded} />
        <textarea
          value={content}
          onChange={(e) => handleChange(e.target.value)}
          onKeyDown={handleKeyDown}
          placeholder={
            replyingTo
              ? `Reply to ${replyingTo.author_username}...`
              : "Type a message..."
          }
          rows={1}
        />
        <button type="submit" className="btn-send" disabled={!content.trim()}>
          Send
        </button>
      </form>
    </div>
  );
}
