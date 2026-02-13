import { describe, it, expect } from "vitest";
import { EpochTracker } from "../epoch-tracker.js";

describe("EpochTracker", () => {
  it("stores and retrieves epoch state", () => {
    const tracker = new EpochTracker();
    const data = new Uint8Array([1, 2, 3]);

    tracker.setEpoch(0, data);

    const state = tracker.getEpoch(0);
    expect(state).not.toBeNull();
    expect(state!.epoch).toBe(0);
    expect(state!.data).toEqual(data);
  });

  it("tracks current epoch", () => {
    const tracker = new EpochTracker();

    expect(tracker.getCurrentEpoch()).toBe(0);

    tracker.setEpoch(1, new Uint8Array([1]));
    expect(tracker.getCurrentEpoch()).toBe(1);

    tracker.setEpoch(5, new Uint8Array([5]));
    expect(tracker.getCurrentEpoch()).toBe(5);

    // Setting a lower epoch doesn't change current
    tracker.setEpoch(3, new Uint8Array([3]));
    expect(tracker.getCurrentEpoch()).toBe(5);
  });

  it("returns null for missing epochs", () => {
    const tracker = new EpochTracker();
    expect(tracker.getEpoch(99)).toBeNull();
  });

  it("prunes old epochs beyond max retention", () => {
    const tracker = new EpochTracker(3);

    for (let i = 0; i < 5; i++) {
      tracker.setEpoch(i, new Uint8Array([i]));
    }

    // Should only retain epochs 2, 3, 4 (last 3)
    expect(tracker.size()).toBe(3);
    expect(tracker.hasEpoch(0)).toBe(false);
    expect(tracker.hasEpoch(1)).toBe(false);
    expect(tracker.hasEpoch(2)).toBe(true);
    expect(tracker.hasEpoch(3)).toBe(true);
    expect(tracker.hasEpoch(4)).toBe(true);
  });

  it("getCurrentState returns the latest epoch state", () => {
    const tracker = new EpochTracker();
    expect(tracker.getCurrentState()).toBeNull();

    const data = new Uint8Array([42]);
    tracker.setEpoch(7, data);

    const state = tracker.getCurrentState();
    expect(state).not.toBeNull();
    expect(state!.epoch).toBe(7);
    expect(state!.data).toEqual(data);
  });

  it("clear removes all state", () => {
    const tracker = new EpochTracker();
    tracker.setEpoch(1, new Uint8Array([1]));
    tracker.setEpoch(2, new Uint8Array([2]));

    tracker.clear();

    expect(tracker.size()).toBe(0);
    expect(tracker.getCurrentEpoch()).toBe(0);
    expect(tracker.getEpoch(1)).toBeNull();
  });

  it("default max is 10 epochs", () => {
    const tracker = new EpochTracker();

    for (let i = 0; i < 15; i++) {
      tracker.setEpoch(i, new Uint8Array([i]));
    }

    expect(tracker.size()).toBe(10);
    expect(tracker.hasEpoch(0)).toBe(false);
    expect(tracker.hasEpoch(4)).toBe(false);
    expect(tracker.hasEpoch(5)).toBe(true);
    expect(tracker.hasEpoch(14)).toBe(true);
  });
});
