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

export interface AltchaChallenge {
  algorithm: string;
  challenge: string;
  maxnumber: number;
  salt: string;
  signature: string;
}

export function register(
  client: ApiClient,
  params: {
    username: string;
    password: string;
    display_name?: string;
    altcha?: string;
    website?: string;
  },
): Promise<RegisterResponse> {
  return client.fetch<RegisterResponse>("/api/v1/auth/register", {
    method: "POST",
    body: JSON.stringify(params),
  });
}

export function getChallenge(client: ApiClient): Promise<AltchaChallenge> {
  return client.fetch<AltchaChallenge>("/api/v1/auth/challenge");
}

export async function solveChallenge(
  challenge: AltchaChallenge,
): Promise<string> {
  const encoder = new TextEncoder();
  for (let n = 0; n <= challenge.maxnumber; n++) {
    const data = encoder.encode(challenge.salt + n.toString());
    const hashBuffer = await crypto.subtle.digest("SHA-256", data);
    const hashHex = Array.from(new Uint8Array(hashBuffer))
      .map((b) => b.toString(16).padStart(2, "0"))
      .join("");
    if (hashHex === challenge.challenge) {
      const payload = {
        algorithm: challenge.algorithm,
        challenge: challenge.challenge,
        number: n,
        salt: challenge.salt,
        signature: challenge.signature,
      };
      return btoa(JSON.stringify(payload));
    }
  }
  throw new Error("Failed to solve ALTCHA challenge");
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
