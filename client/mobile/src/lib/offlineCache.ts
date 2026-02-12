/**
 * SQLite offline cache for messages.
 * Caches recent messages per channel and queues outbound messages for offline send.
 */

import * as SQLite from "expo-sqlite";

const DB_NAME = "cairn_cache.db";
const MAX_CACHED_PER_CHANNEL = 100;

let db: SQLite.SQLiteDatabase | null = null;

async function getDb(): Promise<SQLite.SQLiteDatabase> {
  if (!db) {
    db = await SQLite.openDatabaseAsync(DB_NAME);
    await db.execAsync(`
      CREATE TABLE IF NOT EXISTS cached_messages (
        id TEXT PRIMARY KEY,
        channel_id TEXT NOT NULL,
        content TEXT,
        sender_id TEXT,
        created_at TEXT,
        json TEXT NOT NULL
      );
      CREATE INDEX IF NOT EXISTS idx_cached_channel ON cached_messages(channel_id, created_at);

      CREATE TABLE IF NOT EXISTS outbound_queue (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        channel_id TEXT NOT NULL,
        content TEXT NOT NULL,
        reply_to_id TEXT,
        created_at TEXT DEFAULT CURRENT_TIMESTAMP
      );
    `);
  }
  return db;
}

/** Cache a message (upsert). */
export async function cacheMessage(channelId: string, message: {
  id: string;
  content?: string | null;
  author_id?: string;
  inserted_at?: string;
}): Promise<void> {
  const database = await getDb();
  await database.runAsync(
    `INSERT OR REPLACE INTO cached_messages (id, channel_id, content, sender_id, created_at, json)
     VALUES (?, ?, ?, ?, ?, ?)`,
    message.id,
    channelId,
    message.content ?? null,
    message.author_id ?? null,
    message.inserted_at ?? new Date().toISOString(),
    JSON.stringify(message),
  );

  // Trim to max per channel
  await database.runAsync(
    `DELETE FROM cached_messages WHERE channel_id = ? AND id NOT IN (
      SELECT id FROM cached_messages WHERE channel_id = ?
      ORDER BY created_at DESC LIMIT ?
    )`,
    channelId,
    channelId,
    MAX_CACHED_PER_CHANNEL,
  );
}

/** Get cached messages for a channel. */
export async function getCachedMessages(channelId: string): Promise<unknown[]> {
  const database = await getDb();
  const rows = await database.getAllAsync(
    `SELECT json FROM cached_messages WHERE channel_id = ? ORDER BY created_at ASC`,
    channelId,
  );
  return rows.map((row: any) => JSON.parse(row.json));
}

/** Queue a message for sending when back online. */
export async function queueOutboundMessage(
  channelId: string,
  content: string,
  replyToId?: string,
): Promise<void> {
  const database = await getDb();
  await database.runAsync(
    `INSERT INTO outbound_queue (channel_id, content, reply_to_id) VALUES (?, ?, ?)`,
    channelId,
    content,
    replyToId ?? null,
  );
}

/** Get all queued outbound messages. */
export async function getOutboundQueue(): Promise<Array<{
  id: number;
  channel_id: string;
  content: string;
  reply_to_id: string | null;
}>> {
  const database = await getDb();
  const rows = await database.getAllAsync(
    `SELECT * FROM outbound_queue ORDER BY id ASC`,
  );
  return rows as any[];
}

/** Remove a sent outbound message from the queue. */
export async function removeFromOutboundQueue(id: number): Promise<void> {
  const database = await getDb();
  await database.runAsync(`DELETE FROM outbound_queue WHERE id = ?`, id);
}

/** Clear all cached messages (Settings > Storage > Clear Cache). */
export async function clearCache(): Promise<void> {
  const database = await getDb();
  await database.execAsync(`DELETE FROM cached_messages`);
  await database.execAsync(`DELETE FROM outbound_queue`);
}
