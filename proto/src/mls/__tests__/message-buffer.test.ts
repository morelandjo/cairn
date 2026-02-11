import { describe, it, expect, vi, afterEach } from "vitest";
import { MessageBuffer, type BufferedMessage } from "../message-buffer.js";

function makeMessage(
  epoch: number,
  type = "commit",
  id?: string,
): BufferedMessage {
  return {
    id: id ?? crypto.randomUUID(),
    messageType: type,
    data: new Uint8Array([epoch]),
    epoch,
    receivedAt: Date.now(),
  };
}

describe("MessageBuffer", () => {
  afterEach(() => {
    vi.restoreAllMocks();
  });

  it("buffers and drains messages by epoch", () => {
    const buffer = new MessageBuffer();
    const groupId = "group-1";

    buffer.push(groupId, makeMessage(1));
    buffer.push(groupId, makeMessage(1));
    buffer.push(groupId, makeMessage(2));

    expect(buffer.count(groupId)).toBe(3);

    const epoch1 = buffer.drain(groupId, 1);
    expect(epoch1).toHaveLength(2);
    expect(epoch1[0].epoch).toBe(1);

    // Epoch 2 message still buffered
    expect(buffer.count(groupId)).toBe(1);

    const epoch2 = buffer.drain(groupId, 2);
    expect(epoch2).toHaveLength(1);
    expect(buffer.count(groupId)).toBe(0);
  });

  it("drain returns empty array for no messages", () => {
    const buffer = new MessageBuffer();
    expect(buffer.drain("nonexistent", 0)).toEqual([]);
  });

  it("drainAll returns all messages for a group", () => {
    const buffer = new MessageBuffer();
    const groupId = "group-1";

    buffer.push(groupId, makeMessage(1));
    buffer.push(groupId, makeMessage(2));
    buffer.push(groupId, makeMessage(3));

    const all = buffer.drainAll(groupId);
    expect(all).toHaveLength(3);
    expect(buffer.hasMessages(groupId)).toBe(false);
  });

  it("drainAll returns messages sorted by receivedAt", () => {
    const buffer = new MessageBuffer();
    const groupId = "group-1";

    const msg1: BufferedMessage = {
      ...makeMessage(1, "commit", "a"),
      receivedAt: 300,
    };
    const msg2: BufferedMessage = {
      ...makeMessage(2, "commit", "b"),
      receivedAt: 100,
    };
    const msg3: BufferedMessage = {
      ...makeMessage(3, "commit", "c"),
      receivedAt: 200,
    };

    buffer.push(groupId, msg1);
    buffer.push(groupId, msg2);
    buffer.push(groupId, msg3);

    const all = buffer.drainAll(groupId);
    expect(all[0].receivedAt).toBe(100);
    expect(all[1].receivedAt).toBe(200);
    expect(all[2].receivedAt).toBe(300);
  });

  it("hasMessages returns correct state", () => {
    const buffer = new MessageBuffer();
    const groupId = "group-1";

    expect(buffer.hasMessages(groupId)).toBe(false);

    buffer.push(groupId, makeMessage(1));
    expect(buffer.hasMessages(groupId)).toBe(true);

    buffer.drainAll(groupId);
    expect(buffer.hasMessages(groupId)).toBe(false);
  });

  it("pruneStale removes old messages", () => {
    const buffer = new MessageBuffer();
    const groupId = "group-1";
    const now = Date.now();

    buffer.push(groupId, { ...makeMessage(1), receivedAt: now - 120_000 });
    buffer.push(groupId, { ...makeMessage(2), receivedAt: now - 30_000 });
    buffer.push(groupId, { ...makeMessage(3), receivedAt: now });

    const pruned = buffer.pruneStale(60_000);
    expect(pruned).toBe(1);
    expect(buffer.count(groupId)).toBe(2);
  });

  it("pruneStale removes entire group when all messages are stale", () => {
    const buffer = new MessageBuffer();
    const groupId = "group-1";
    const now = Date.now();

    buffer.push(groupId, { ...makeMessage(1), receivedAt: now - 120_000 });
    buffer.push(groupId, { ...makeMessage(2), receivedAt: now - 90_000 });

    buffer.pruneStale(60_000);
    expect(buffer.hasMessages(groupId)).toBe(false);
  });

  it("fires resync callback after timeout", async () => {
    vi.useFakeTimers();
    const resyncFn = vi.fn();
    const buffer = new MessageBuffer(100); // 100ms timeout
    buffer.setResyncCallback(resyncFn);

    buffer.push("group-1", makeMessage(5));

    expect(resyncFn).not.toHaveBeenCalled();

    vi.advanceTimersByTime(150);

    expect(resyncFn).toHaveBeenCalledWith("group-1");
    expect(resyncFn).toHaveBeenCalledTimes(1);

    vi.useRealTimers();
  });

  it("does not fire resync if messages are drained before timeout", () => {
    vi.useFakeTimers();
    const resyncFn = vi.fn();
    const buffer = new MessageBuffer(100);
    buffer.setResyncCallback(resyncFn);

    buffer.push("group-1", makeMessage(5));
    buffer.drainAll("group-1");

    vi.advanceTimersByTime(150);

    expect(resyncFn).not.toHaveBeenCalled();

    vi.useRealTimers();
  });

  it("clear removes all buffers and timers", () => {
    vi.useFakeTimers();
    const resyncFn = vi.fn();
    const buffer = new MessageBuffer(100);
    buffer.setResyncCallback(resyncFn);

    buffer.push("group-1", makeMessage(1));
    buffer.push("group-2", makeMessage(2));

    buffer.clear();

    vi.advanceTimersByTime(200);

    expect(resyncFn).not.toHaveBeenCalled();
    expect(buffer.hasMessages("group-1")).toBe(false);
    expect(buffer.hasMessages("group-2")).toBe(false);

    vi.useRealTimers();
  });

  it("isolates messages between groups", () => {
    const buffer = new MessageBuffer();

    buffer.push("group-1", makeMessage(1));
    buffer.push("group-2", makeMessage(2));

    expect(buffer.count("group-1")).toBe(1);
    expect(buffer.count("group-2")).toBe(1);

    buffer.drainAll("group-1");
    expect(buffer.count("group-1")).toBe(0);
    expect(buffer.count("group-2")).toBe(1);
  });
});
