import { View, Text, TouchableOpacity, StyleSheet } from "react-native";
import { sendReaction } from "../api/socket";

interface Props {
  messageId: string;
  channelId: string;
  onClose: () => void;
}

const QUICK_REACTIONS = ["\u{1F44D}", "\u{2764}\u{FE0F}", "\u{1F602}", "\u{1F622}", "\u{1F525}", "\u{1F440}"];

export function ReactionPicker({ messageId, onClose }: Props) {
  const handleReaction = (emoji: string) => {
    sendReaction(messageId, emoji);
    onClose();
  };

  return (
    <View style={styles.container}>
      {QUICK_REACTIONS.map((emoji) => (
        <TouchableOpacity
          key={emoji}
          style={styles.emojiButton}
          onPress={() => handleReaction(emoji)}
        >
          <Text style={styles.emoji}>{emoji}</Text>
        </TouchableOpacity>
      ))}
    </View>
  );
}

const styles = StyleSheet.create({
  container: {
    flexDirection: "row",
    backgroundColor: "#252540",
    borderRadius: 20,
    paddingHorizontal: 8,
    paddingVertical: 4,
    marginTop: 4,
    marginLeft: 40,
    alignSelf: "flex-start",
  },
  emojiButton: {
    padding: 6,
  },
  emoji: {
    fontSize: 20,
  },
});
