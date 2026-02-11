/**
 * Auth API endpoints.
 */

import type { ApiClient } from "./client.js";

export interface User {
  id: string;
  username: string;
  display_name: string | null;
  did?: string;
}

export interface RegisterResponse {
  user: User;
  access_token: string;
  refresh_token: string;
  recovery_codes: string[];
}

export interface LoginResponse {
  user: User;
  access_token: string;
  refresh_token: string;
}

export interface TotpRequiredResponse {
  requires_totp: true;
  user_id: string;
}

export interface TotpAuthResponse {
  user: User;
  access_token: string;
  refresh_token: string;
}

export interface RefreshResponse {
  access_token: string;
  refresh_token: string;
}

export interface MeResponse {
  user: User;
}

export function register(
  client: ApiClient,
  params: { username: string; password: string; display_name?: string },
): Promise<RegisterResponse> {
  return client.fetch<RegisterResponse>("/api/v1/auth/register", {
    method: "POST",
    body: JSON.stringify(params),
  });
}

export function login(
  client: ApiClient,
  params: { username: string; password: string },
): Promise<LoginResponse | TotpRequiredResponse> {
  return client.fetch<LoginResponse | TotpRequiredResponse>(
    "/api/v1/auth/login",
    {
      method: "POST",
      body: JSON.stringify(params),
    },
  );
}

export function refreshTokens(
  client: ApiClient,
  refreshToken: string,
): Promise<RefreshResponse> {
  return client.fetch<RefreshResponse>("/api/v1/auth/refresh", {
    method: "POST",
    body: JSON.stringify({ refresh_token: refreshToken }),
  });
}

export function totpAuthenticate(
  client: ApiClient,
  params: { user_id: string; code: string },
): Promise<TotpAuthResponse> {
  return client.fetch<TotpAuthResponse>("/api/v1/auth/totp/authenticate", {
    method: "POST",
    body: JSON.stringify(params),
  });
}

export function getMe(client: ApiClient): Promise<MeResponse> {
  return client.fetch<MeResponse>("/api/v1/auth/me");
}
