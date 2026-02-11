/**
 * File upload API — delegates to @murmuring/proto.
 */

import { uploadApi } from "@murmuring/proto";
import { client } from "./client";
import { getApiBaseUrl } from "../lib/config";

export type { UploadResponse } from "@murmuring/proto/api";

export function uploadFile(formData: FormData) {
  return uploadApi.uploadFile(client, formData);
}

export function getFileUrl(fileId: string): string {
  return uploadApi.getFileUrl(getApiBaseUrl(), fileId);
}
