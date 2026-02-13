/**
 * File upload API.
 */

import type { ApiClient } from "./client.js";

export interface UploadResponse {
  id: string;
  filename: string;
  content_type: string;
  size: number;
}

export function uploadFile(
  client: ApiClient,
  file: FormData,
): Promise<UploadResponse> {
  return client.fetch<UploadResponse>("/api/v1/upload", {
    method: "POST",
    body: file,
  });
}

export function getFileUrl(baseUrl: string, fileId: string): string {
  return `${baseUrl}/api/v1/files/${fileId}`;
}
