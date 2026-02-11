/**
 * Sync manager — handles offline message queue and reconnection.
 * On reconnect: sends queued outbound messages, fetches missed messages.
 */

import { getOutboundQueue, removeFromOutboundQueue } from "./offlineCache";
import { sendChannelMessage } from "../api/socket";

/**
 * Flush the outbound message queue.
 * Sends each queued message and removes it from the queue on success.
 */
export async function flushOutboundQueue(): Promise<void> {
  const queue = await getOutboundQueue();

  for (const item of queue) {
    try {
      sendChannelMessage(item.content, {
        reply_to_id: item.reply_to_id ?? undefined,
      });
      await removeFromOutboundQueue(item.id);
    } catch (err) {
      console.error("Failed to send queued message:", err);
      // Stop on first failure to preserve order
      break;
    }
  }
}

/**
 * Called when the app reconnects to the server.
 * Flushes outbound queue.
 */
export async function onReconnect(): Promise<void> {
  await flushOutboundQueue();
}
