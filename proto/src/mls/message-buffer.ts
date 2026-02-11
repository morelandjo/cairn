/**
 * MLS Message Buffer — buffers out-of-order protocol messages
 * (proposals, commits) and triggers resync after a timeout.
 *
 * In MLS, proposals must be applied in order within an epoch,
 * and commits advance the epoch. If messages arrive out of order
 * (e.g., proposal arrives before a commit that changes the epoch),
 * they are buffered here until the group state catches up.
 */

const DEFAULT_RESYNC_TIMEOUT_MS = 60_000;

export interface BufferedMessage {
  id: string;
  messageType: string;
  data: Uint8Array;
  epoch: number;
  receivedAt: number;
}

export type ResyncCallback = (groupId: string) => void;

export class MessageBuffer {
  private buffers: Map<string, BufferedMessage[]> = new Map();
  private timers: Map<string, ReturnType<typeof setTimeout>> = new Map();
  private resyncTimeoutMs: number;
  private onResync: ResyncCallback | null = null;

  constructor(resyncTimeoutMs = DEFAULT_RESYNC_TIMEOUT_MS) {
    this.resyncTimeoutMs = resyncTimeoutMs;
  }

  /**
   * Set a callback that fires when buffered messages for a group
   * exceed the resync timeout without being consumed.
   */
  setResyncCallback(cb: ResyncCallback): void {
    this.onResync = cb;
  }

  /**
   * Buffer a message for a group. Starts the resync timer if not already running.
   */
  push(groupId: string, message: BufferedMessage): void {
    let buffer = this.buffers.get(groupId);
    if (!buffer) {
      buffer = [];
      this.buffers.set(groupId, buffer);
    }
    buffer.push(message);

    this.startTimer(groupId);
  }

  /**
   * Get and remove all buffered messages for a group at a specific epoch.
   * Returns messages sorted by receivedAt (oldest first).
   */
  drain(groupId: string, epoch: number): BufferedMessage[] {
    const buffer = this.buffers.get(groupId);
    if (!buffer) return [];

    const matching: BufferedMessage[] = [];
    const remaining: BufferedMessage[] = [];

    for (const msg of buffer) {
      if (msg.epoch === epoch) {
        matching.push(msg);
      } else {
        remaining.push(msg);
      }
    }

    if (remaining.length === 0) {
      this.buffers.delete(groupId);
      this.clearTimer(groupId);
    } else {
      this.buffers.set(groupId, remaining);
    }

    return matching.sort((a, b) => a.receivedAt - b.receivedAt);
  }

  /**
   * Get and remove ALL buffered messages for a group.
   */
  drainAll(groupId: string): BufferedMessage[] {
    const buffer = this.buffers.get(groupId);
    if (!buffer) return [];

    this.buffers.delete(groupId);
    this.clearTimer(groupId);

    return buffer.sort((a, b) => a.receivedAt - b.receivedAt);
  }

  /**
   * Get buffered message count for a group.
   */
  count(groupId: string): number {
    return this.buffers.get(groupId)?.length ?? 0;
  }

  /**
   * Check if there are buffered messages for a group.
   */
  hasMessages(groupId: string): boolean {
    return this.count(groupId) > 0;
  }

  /**
   * Remove stale messages older than maxAgeMs.
   */
  pruneStale(maxAgeMs: number): number {
    const now = Date.now();
    let pruned = 0;

    for (const [groupId, buffer] of this.buffers) {
      const remaining = buffer.filter((m) => now - m.receivedAt < maxAgeMs);
      pruned += buffer.length - remaining.length;

      if (remaining.length === 0) {
        this.buffers.delete(groupId);
        this.clearTimer(groupId);
      } else {
        this.buffers.set(groupId, remaining);
      }
    }

    return pruned;
  }

  /**
   * Clear all buffers and timers.
   */
  clear(): void {
    for (const timer of this.timers.values()) {
      clearTimeout(timer);
    }
    this.timers.clear();
    this.buffers.clear();
  }

  private startTimer(groupId: string): void {
    if (this.timers.has(groupId)) return;

    const timer = setTimeout(() => {
      this.timers.delete(groupId);
      if (this.onResync && this.hasMessages(groupId)) {
        this.onResync(groupId);
      }
    }, this.resyncTimeoutMs);

    this.timers.set(groupId, timer);
  }

  private clearTimer(groupId: string): void {
    const timer = this.timers.get(groupId);
    if (timer) {
      clearTimeout(timer);
      this.timers.delete(groupId);
    }
  }
}
