import { View, Text, StyleSheet } from "react-native";

interface Props {
  typingUsers: Map<string, number>;
}

export function TypingIndicator({ typingUsers }: Props) {
  if (typingUsers.size === 0) return null;

  const userIds = Array.from(typingUsers.keys());
  let text: string;

  if (userIds.length === 1) {
    text = "Someone is typing...";
  } else if (userIds.length <= 3) {
    text = `${userIds.length} people are typing...`;
  } else {
    text = "Several people are typing...";
  }

  return (
    <View style={styles.container}>
      <Text style={styles.text}>{text}</Text>
    </View>
  );
}

const styles = StyleSheet.create({
  container: {
    paddingHorizontal: 16,
    paddingVertical: 4,
    backgroundColor: "#16162a",
  },
  text: {
    color: "#888",
    fontSize: 12,
    fontStyle: "italic",
  },
});
