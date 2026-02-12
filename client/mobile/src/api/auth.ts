/**
 * Auth API endpoints — delegates to @cairn/proto.
 */

import { authApi } from "@cairn/proto";
import { client } from "./client";

export type {
  User,
  RegisterResponse,
  LoginResponse,
  TotpRequiredResponse,
  TotpAuthResponse,
  RefreshResponse,
  MeResponse,
} from "@cairn/proto/api";

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
