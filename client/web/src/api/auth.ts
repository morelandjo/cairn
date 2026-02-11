/**
 * Auth API endpoints — delegates to @murmuring/proto.
 */

import { authApi } from "@murmuring/proto";
import { client } from "./client.ts";

export type {
  User,
  RegisterResponse,
  LoginResponse,
  TotpRequiredResponse,
  TotpAuthResponse,
  RefreshResponse,
  MeResponse,
} from "@murmuring/proto/api";

export function register(params: {
  username: string;
  password: string;
  display_name?: string;
  altcha?: string;
  website?: string;
}) {
  return authApi.register(client, params);
}

export function login(params: { username: string; password: string }) {
  return authApi.login(client, params);
}

export function refreshTokens(refreshToken: string) {
  return authApi.refreshTokens(client, refreshToken);
}

export function totpAuthenticate(params: { user_id: string; code: string }) {
  return authApi.totpAuthenticate(client, params);
}

export function getMe() {
  return authApi.getMe(client);
}
