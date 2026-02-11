/**
 * Presence store — tracks online users per channel.
 */

import { create } from "zustand";

type PresenceState = Record<
  string,
  { metas: Array<{ online_at?: string; phx_ref?: string }> }
>;

interface PresenceStoreState {
  /** Map of userId -> online status */
  onlineUsers: Set<string>;

  setPresenceState: (state: PresenceState) => void;
  applyPresenceDiff: (diff: {
    joins: PresenceState;
    leaves: PresenceState;
  }) => void;
  isOnline: (userId: string) => boolean;
  clear: () => void;
}

export const usePresenceStore = create<PresenceStoreState>((set, get) => ({
  onlineUsers: new Set(),

  setPresenceState: (state) => {
    const users = new Set(Object.keys(state));
    set({ onlineUsers: users });
  },

  applyPresenceDiff: (diff) => {
    set((prev) => {
      const users = new Set(prev.onlineUsers);
      for (const userId of Object.keys(diff.joins)) {
        users.add(userId);
      }
      for (const userId of Object.keys(diff.leaves)) {
        users.delete(userId);
      }
      return { onlineUsers: users };
    });
  },

  isOnline: (userId) => {
    return get().onlineUsers.has(userId);
  },

  clear: () => {
    set({ onlineUsers: new Set() });
  },
}));
