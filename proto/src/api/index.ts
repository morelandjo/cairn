/**
 * Shared API client — platform-agnostic HTTP client for the Cairn API.
 */

export { ApiClient, apiClient } from "./client.js";
export type { ApiClientOptions } from "./client.js";
export type { ApiTransport, ApiResponse } from "./transport.js";
export { FetchTransport } from "./transport.js";

// Namespace exports (for calling functions)
export * as authApi from "./auth.js";
export * as channelsApi from "./channels.js";
export * as serversApi from "./servers.js";
export * as moderationApi from "./moderation.js";
export * as uploadApi from "./upload.js";
export * as searchApi from "./search.js";
export * as invitesApi from "./invites.js";
export * as notificationsApi from "./notifications.js";
export * as discoveryApi from "./discovery.js";
export * as webhooksApi from "./webhooks.js";
export * as mlsApi from "./mls.js";
export * as voiceApi from "./voice.js";
export * as pushTokensApi from "./pushTokens.js";
export * as identityApi from "./identity.js";
export * as federationApi from "./federation.js";
export * as dmApi from "./dm.js";

// Type re-exports (for importing types directly)
export type {
  User,
  RegisterResponse,
  LoginResponse,
  TotpRequiredResponse,
  TotpAuthResponse,
  RefreshResponse,
  MeResponse,
  AltchaChallenge,
} from "./auth.js";

export type {
  Channel,
  Reaction,
  ReplyToSummary,
  Message,
  Member,
} from "./channels.js";

export type { Server, ServerMember, ServerRole } from "./servers.js";

export type {
  Mute,
  Ban,
  ModLogEntry,
  MessageReport,
  AutoModRule,
} from "./moderation.js";

export type { UploadResponse } from "./upload.js";
export type { SearchResult } from "./search.js";
export type { Invite, InviteInfo } from "./invites.js";
export type { NotificationPreference } from "./notifications.js";
export type { DirectoryEntry } from "./discovery.js";
export type { Webhook, BotAccount } from "./webhooks.js";
export type { MlsProtocolMessage } from "./mls.js";
export type { IceServerConfig } from "./voice.js";
export type { PushTokenResponse } from "./pushTokens.js";
export type {
  RotateSigningKeyParams,
  RotateSigningKeyResponse,
  DIDOperationsResponse,
} from "./identity.js";
export type {
  FederatedTokenResponse,
  JoinServerResponse,
  FederatedChannel,
  ServerChannelsResponse,
} from "./federation.js";
export type {
  CreateFederatedDmResponse,
  DmRequestsResponse,
  RespondToDmRequestResponse,
} from "./dm.js";
