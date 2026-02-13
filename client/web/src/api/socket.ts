/**
 * Phoenix Socket management for real-time channel communication.
 *
 * The `phoenix` npm package has no TypeScript declarations,
 * so we use `any` for the socket and channel references.
 */

// @ts-expect-error phoenix has no type declarations
import { Socket } from "phoenix";

type PresenceState = Record<
  string,
  { metas: Array<{ online_at?: string; phx_ref?: string }> }
>;

/* eslint-disable @typescript-eslint/no-explicit-any */
let socket: any = null;
let currentChannel: any = null;
let userChannel: any = null;
/* eslint-enable @typescript-eslint/no-explicit-any */

interface SocketCallbacks {
  onNewMessage: (msg: unknown) => void;
  onEditMessage: (msg: unknown) => void;
  onDeleteMessage: (msg: unknown) => void;
  onTyping: (data: unknown) => void;
  onPresenceState: (state: PresenceState) => void;
  onPresenceDiff: (diff: {
    joins: PresenceState;
    leaves: PresenceState;
  }) => void;
  onMlsCommit?: (data: unknown) => void;
  onMlsWelcome?: (data: unknown) => void;
  onMlsProposal?: (data: unknown) => void;
  onReactionAdded?: (data: unknown) => void;
  onReactionRemoved?: (data: unknown) => void;
  onLinkPreview?: (data: unknown) => void;
  onDmRequest?: (data: unknown) => void;
  onDmRequestResponse?: (data: unknown) => void;
}

let callbacks: SocketCallbacks | null = null;

export function setSocketCallbacks(cb: SocketCallbacks) {
  callbacks = cb;
}

export function connectSocket(token: string) {
  if (socket) {
    socket.disconnect();
  }
  socket = new Socket("/socket", {
    params: { token },
  });
  socket.connect();
}

export function disconnectSocket() {
  if (userChannel) {
    userChannel.leave();
    userChannel = null;
  }
  if (currentChannel) {
    currentChannel.leave();
    currentChannel = null;
  }
  if (socket) {
    socket.disconnect();
    socket = null;
  }
}

export function joinUserChannel(userId: string) {
  if (!socket) return;

  if (userChannel) {
    userChannel.leave();
    userChannel = null;
  }

  const channel = socket.channel(`user:${userId}`, {});

  channel.on("dm_request", (data: unknown) => {
    callbacks?.onDmRequest?.(data);
  });

  channel.on("dm_request_response", (data: unknown) => {
    callbacks?.onDmRequestResponse?.(data);
  });

  channel
    .join()
    .receive("ok", () => {
      console.log(`Joined user:${userId}`);
    })
    .receive("error", (resp: unknown) => {
      console.error(`Failed to join user:${userId}`, resp);
    });

  userChannel = channel;
}

export function joinChannel(channelId: string) {
  if (!socket) return;

  if (currentChannel) {
    currentChannel.leave();
    currentChannel = null;
  }

  const channel = socket.channel(`channel:${channelId}`, {});

  channel.on("new_msg", (msg: unknown) => {
    callbacks?.onNewMessage(msg);
  });

  channel.on("edit_msg", (msg: unknown) => {
    callbacks?.onEditMessage(msg);
  });

  channel.on("delete_msg", (msg: unknown) => {
    callbacks?.onDeleteMessage(msg);
  });

  channel.on("typing", (data: unknown) => {
    callbacks?.onTyping(data);
  });

  channel.on("presence_state", (state: PresenceState) => {
    callbacks?.onPresenceState(state);
  });

  channel.on(
    "presence_diff",
    (diff: { joins: PresenceState; leaves: PresenceState }) => {
      callbacks?.onPresenceDiff(diff);
    },
  );

  channel.on("mls_commit", (data: unknown) => {
    callbacks?.onMlsCommit?.(data);
  });

  channel.on("mls_welcome", (data: unknown) => {
    callbacks?.onMlsWelcome?.(data);
  });

  channel.on("mls_proposal", (data: unknown) => {
    callbacks?.onMlsProposal?.(data);
  });

  channel.on("reaction_added", (data: unknown) => {
    callbacks?.onReactionAdded?.(data);
  });

  channel.on("reaction_removed", (data: unknown) => {
    callbacks?.onReactionRemoved?.(data);
  });

  channel.on("link_preview", (data: unknown) => {
    callbacks?.onLinkPreview?.(data);
  });

  channel
    .join()
    .receive("ok", () => {
      console.log(`Joined channel:${channelId}`);
    })
    .receive("error", (resp: unknown) => {
      console.error(`Failed to join channel:${channelId}`, resp);
    });

  currentChannel = channel;
}

export function sendChannelMessage(
  content: string,
  opts?: {
    encrypted_content?: string;
    nonce?: string;
    mls_epoch?: number;
    reply_to_id?: string;
  },
) {
  if (!currentChannel) return;
  if (opts?.encrypted_content) {
    currentChannel.push("new_msg", {
      content: null,
      encrypted_content: opts.encrypted_content,
      nonce: opts.nonce ?? "",
      mls_epoch: opts.mls_epoch,
      reply_to_id: opts?.reply_to_id,
    });
  } else {
    currentChannel.push("new_msg", {
      content,
      reply_to_id: opts?.reply_to_id,
    });
  }
}

export function sendReaction(messageId: string, emoji: string) {
  if (!currentChannel) return;
  currentChannel.push("add_reaction", { message_id: messageId, emoji });
}

export function removeReaction(messageId: string, emoji: string) {
  if (!currentChannel) return;
  currentChannel.push("remove_reaction", { message_id: messageId, emoji });
}

export function sendMlsMessage(
  type: "mls_commit" | "mls_welcome" | "mls_proposal",
  data: string,
  opts?: { epoch?: number; recipient_id?: string },
) {
  if (!currentChannel) return;
  currentChannel.push(type, { data, ...opts });
}

export function sendTyping() {
  if (!currentChannel) return;
  currentChannel.push("typing", {});
}

export function leaveChannel() {
  if (currentChannel) {
    currentChannel.leave();
    currentChannel = null;
  }
}

export function getSocket() {
  return socket;
}
