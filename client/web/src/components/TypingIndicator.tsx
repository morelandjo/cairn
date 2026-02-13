import { useChannelStore } from "../stores/channelStore.ts";
import { useAuthStore } from "../stores/authStore.ts";

export default function TypingIndicator() {
  const typingUsers = useChannelStore((s) => s.typingUsers);
  const members = useChannelStore((s) => s.members);
  const currentUser = useAuthStore((s) => s.user);

  // Filter out current user from typing list
  const typingOthers = Array.from(typingUsers.keys()).filter(
    (uid) => uid !== currentUser?.id,
  );

  if (typingOthers.length === 0) return null;

  const names = typingOthers.map((uid) => {
    const member = members.find((m) => m.id === uid);
    return member?.display_name || member?.username || "Someone";
  });

  let text: string;
  if (names.length === 1) {
    text = `${names[0]} is typing...`;
  } else if (names.length === 2) {
    text = `${names[0]} and ${names[1]} are typing...`;
  } else {
    text = "Several people are typing...";
  }

  return <div className="typing-indicator">{text}</div>;
}
