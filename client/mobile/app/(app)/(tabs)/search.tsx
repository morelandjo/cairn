import { useState } from "react";
import {
  View,
  Text,
  TextInput,
  FlatList,
  StyleSheet,
  ActivityIndicator,
} from "react-native";
import * as searchApi from "@/api/search";
import type { SearchResult } from "@/api/search";
import { useServerStore } from "@/stores/serverStore";

export default function SearchScreen() {
  const currentServerId = useServerStore((s) => s.currentServerId);
  const [query, setQuery] = useState("");
  const [results, setResults] = useState<SearchResult[]>([]);
  const [isSearching, setIsSearching] = useState(false);

  const handleSearch = async () => {
    if (!query.trim() || !currentServerId) return;
    setIsSearching(true);
    try {
      const data = await searchApi.searchMessages(currentServerId, query.trim());
      setResults(data.results);
    } catch (err) {
      console.error("Search failed:", err);
    } finally {
      setIsSearching(false);
    }
  };

  return (
    <View style={styles.container}>
      <View style={styles.header}>
        <Text style={styles.headerTitle}>Search</Text>
      </View>

      <View style={styles.searchBar}>
        <TextInput
          style={styles.input}
          placeholder="Search messages..."
          placeholderTextColor="#888"
          value={query}
          onChangeText={setQuery}
          onSubmitEditing={handleSearch}
          returnKeyType="search"
        />
      </View>

      {isSearching ? (
        <ActivityIndicator color="#5865f2" style={styles.loader} />
      ) : (
        <FlatList
          data={results}
          keyExtractor={(item, index) => `${item.id ?? index}`}
          renderItem={({ item }) => (
            <View style={styles.resultItem}>
              <Text style={styles.resultAuthor}>
                {(item as Record<string, unknown>).author_username as string ?? "Unknown"}
              </Text>
              <Text style={styles.resultContent} numberOfLines={3}>
                {(item as Record<string, unknown>).content as string ?? ""}
              </Text>
            </View>
          )}
          ListEmptyComponent={
            query.trim() ? (
              <Text style={styles.empty}>No results found</Text>
            ) : (
              <Text style={styles.empty}>Enter a search query</Text>
            )
          }
        />
      )}
    </View>
  );
}

const styles = StyleSheet.create({
  container: {
    flex: 1,
    backgroundColor: "#1a1a2e",
  },
  header: {
    paddingHorizontal: 16,
    paddingTop: 56,
    paddingBottom: 12,
    backgroundColor: "#16162a",
    borderBottomWidth: 1,
    borderBottomColor: "#333355",
  },
  headerTitle: {
    fontSize: 20,
    fontWeight: "bold",
    color: "#e0e0ff",
  },
  searchBar: {
    padding: 12,
  },
  input: {
    backgroundColor: "#252540",
    borderRadius: 8,
    padding: 12,
    fontSize: 16,
    color: "#e0e0ff",
    borderWidth: 1,
    borderColor: "#333355",
  },
  loader: {
    marginTop: 40,
  },
  resultItem: {
    paddingVertical: 12,
    paddingHorizontal: 16,
    borderBottomWidth: 1,
    borderBottomColor: "#252540",
  },
  resultAuthor: {
    fontSize: 14,
    fontWeight: "600",
    color: "#5865f2",
    marginBottom: 4,
  },
  resultContent: {
    fontSize: 14,
    color: "#ccc",
  },
  empty: {
    color: "#888",
    textAlign: "center",
    marginTop: 40,
    fontSize: 15,
  },
});
