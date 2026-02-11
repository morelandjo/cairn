import { useState } from "react";
import { sendReaction } from "../api/socket.ts";

const COMMON_EMOJIS = [
  "\u{1F44D}", "\u{1F44E}", "\u{2764}\u{FE0F}", "\u{1F602}", "\u{1F62E}",
  "\u{1F389}", "\u{1F525}", "\u{1F440}", "\u{2705}", "\u{274C}",
  "\u{1F64F}", "\u{1F4AF}", "\u{1F914}", "\u{1F60D}", "\u{1F622}",
];

interface Props {
  messageId: string;
  onClose: () => void;
}

export default function ReactionPicker({ messageId, onClose }: Props) {
  const [customEmoji, setCustomEmoji] = useState("");

  function handlePick(emoji: string) {
    sendReaction(messageId, emoji);
    onClose();
  }

  function handleCustomSubmit() {
    const trimmed = customEmoji.trim();
    if (trimmed) {
      sendReaction(messageId, trimmed);
      setCustomEmoji("");
      onClose();
    }
  }

  return (
    <div className="reaction-picker" onClick={(e) => e.stopPropagation()}>
      <div className="reaction-grid">
        {COMMON_EMOJIS.map((emoji) => (
          <button
            key={emoji}
            className="reaction-emoji-btn"
            onClick={() => handlePick(emoji)}
          >
            {emoji}
          </button>
        ))}
      </div>
      <div className="reaction-custom">
        <input
          type="text"
          value={customEmoji}
          onChange={(e) => setCustomEmoji(e.target.value)}
          placeholder="Custom..."
          maxLength={64}
          onKeyDown={(e) => {
            if (e.key === "Enter") handleCustomSubmit();
            if (e.key === "Escape") onClose();
          }}
        />
      </div>
    </div>
  );
}
