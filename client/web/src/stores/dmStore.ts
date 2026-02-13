/**
 * DM store — manages cross-instance DM requests and federated DM state.
 */

import { create } from "zustand";
import type { DmRequest } from "@cairn/proto";
import {
  listDmRequests,
  listSentDmRequests,
  createFederatedDm,
  respondToDmRequest,
  blockDmSender,
} from "../api/dm.ts";

interface DmState {
  /** Pending DM requests received */
  receivedRequests: DmRequest[];
  /** DM requests sent by this user */
  sentRequests: DmRequest[];
  /** Loading state */
  loading: boolean;
  /** Error message */
  error: string | null;

  /** Fetch received DM requests */
  fetchReceivedRequests: () => Promise<void>;
  /** Fetch sent DM requests */
  fetchSentRequests: () => Promise<void>;
  /** Initiate a federated DM */
  initiateDm: (
    recipientDid: string,
    recipientInstance: string,
  ) => Promise<{ channelId: string; requestId: string } | null>;
  /** Accept a DM request */
  acceptRequest: (requestId: string) => Promise<boolean>;
  /** Reject a DM request */
  rejectRequest: (requestId: string) => Promise<boolean>;
  /** Block a DM request sender */
  blockRequest: (requestId: string) => Promise<boolean>;
  /** Add a DM request from a real-time notification */
  addReceivedRequest: (request: DmRequest) => void;
  /** Remove a request by ID (after response) */
  removeRequest: (requestId: string) => void;
}

export const useDmStore = create<DmState>((set, get) => ({
  receivedRequests: [],
  sentRequests: [],
  loading: false,
  error: null,

  fetchReceivedRequests: async () => {
    set({ loading: true, error: null });
    try {
      const res = await listDmRequests();
      set({ receivedRequests: res.requests, loading: false });
    } catch (err) {
      set({ error: String(err), loading: false });
    }
  },

  fetchSentRequests: async () => {
    set({ loading: true, error: null });
    try {
      const res = await listSentDmRequests();
      set({ sentRequests: res.requests, loading: false });
    } catch (err) {
      set({ error: String(err), loading: false });
    }
  },

  initiateDm: async (recipientDid, recipientInstance) => {
    set({ loading: true, error: null });
    try {
      const res = await createFederatedDm(recipientDid, recipientInstance);
      // Refresh sent requests
      get().fetchSentRequests();
      set({ loading: false });
      return { channelId: res.channel_id, requestId: res.request_id };
    } catch (err) {
      set({ error: String(err), loading: false });
      return null;
    }
  },

  acceptRequest: async (requestId) => {
    try {
      await respondToDmRequest(requestId, "accepted");
      set((state) => ({
        receivedRequests: state.receivedRequests.filter((r) => r.id !== requestId),
      }));
      return true;
    } catch (err) {
      set({ error: String(err) });
      return false;
    }
  },

  rejectRequest: async (requestId) => {
    try {
      await respondToDmRequest(requestId, "rejected");
      set((state) => ({
        receivedRequests: state.receivedRequests.filter((r) => r.id !== requestId),
      }));
      return true;
    } catch (err) {
      set({ error: String(err) });
      return false;
    }
  },

  blockRequest: async (requestId) => {
    try {
      await blockDmSender(requestId);
      set((state) => ({
        receivedRequests: state.receivedRequests.filter((r) => r.id !== requestId),
      }));
      return true;
    } catch (err) {
      set({ error: String(err) });
      return false;
    }
  },

  addReceivedRequest: (request) => {
    set((state) => ({
      receivedRequests: [request, ...state.receivedRequests],
    }));
  },

  removeRequest: (requestId) => {
    set((state) => ({
      receivedRequests: state.receivedRequests.filter((r) => r.id !== requestId),
      sentRequests: state.sentRequests.filter((r) => r.id !== requestId),
    }));
  },
}));
