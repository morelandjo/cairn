/**
 * MLS Epoch Tracker — retains group state for recent epochs to handle
 * messages that arrive slightly out of order.
 *
 * MLS groups advance epochs on each commit (add/remove/update).
 * During transitions, messages from the previous epoch may still arrive.
 * This tracker keeps the last N epoch states so they can be decrypted.
 */

const DEFAULT_MAX_EPOCHS = 10;

export interface EpochState {
  epoch: number;
  /** Opaque state data (e.g., serialized group state or decryption keys). */
  data: Uint8Array;
}

export class EpochTracker {
  private states: Map<number, EpochState> = new Map();
  private maxEpochs: number;
  private currentEpoch = 0;

  constructor(maxEpochs = DEFAULT_MAX_EPOCHS) {
    this.maxEpochs = maxEpochs;
  }

  /**
   * Record a new epoch state. Prunes old epochs beyond the retention window.
   */
  setEpoch(epoch: number, data: Uint8Array): void {
    this.states.set(epoch, { epoch, data });

    if (epoch > this.currentEpoch) {
      this.currentEpoch = epoch;
    }

    this.prune();
  }

  /**
   * Get the state for a specific epoch, or null if not retained.
   */
  getEpoch(epoch: number): EpochState | null {
    return this.states.get(epoch) ?? null;
  }

  /**
   * Get the current (latest) epoch number.
   */
  getCurrentEpoch(): number {
    return this.currentEpoch;
  }

  /**
   * Get the current epoch state.
   */
  getCurrentState(): EpochState | null {
    return this.states.get(this.currentEpoch) ?? null;
  }

  /**
   * Check if a specific epoch is still retained.
   */
  hasEpoch(epoch: number): boolean {
    return this.states.has(epoch);
  }

  /**
   * Get the number of retained epochs.
   */
  size(): number {
    return this.states.size;
  }

  /**
   * Clear all epoch state.
   */
  clear(): void {
    this.states.clear();
    this.currentEpoch = 0;
  }

  private prune(): void {
    if (this.states.size <= this.maxEpochs) return;

    // Keep only the most recent maxEpochs entries
    const epochs = Array.from(this.states.keys()).sort((a, b) => a - b);
    const toRemove = epochs.slice(0, epochs.length - this.maxEpochs);
    for (const epoch of toRemove) {
      this.states.delete(epoch);
    }
  }
}
