import { useEffect } from "react";
import { View, StyleSheet } from "react-native";
import { useRouter, useLocalSearchParams } from "expo-router";
import { useChannelStore } from "@/stores/channelStore";
import { ChannelList } from "@/components/ChannelList";

export default function ChannelListScreen() {
  const router = useRouter();
  const { serverId } = useLocalSearchParams<{ serverId: string }>();
  const { channels, fetchChannels, isLoadingChannels } = useChannelStore();

  useEffect(() => {
    if (serverId) {
      fetchChannels(serverId);
    }
  }, [serverId, fetchChannels]);

  const handleSelectChannel = (channelId: string) => {
    router.push(`/(app)/(tabs)/servers/${serverId}/${channelId}`);
  };

  return (
    <View style={styles.container}>
      <ChannelList
        channels={channels}
        isLoading={isLoadingChannels}
        onSelectChannel={handleSelectChannel}
      />
    </View>
  );
}

const styles = StyleSheet.create({
  container: {
    flex: 1,
    backgroundColor: "#1a1a2e",
  },
});
