/**
 * File upload API — delegates to @cairn/proto.
 */

import { uploadApi } from "@cairn/proto";
import { client } from "./client";
import { getApiBaseUrl } from "../lib/config";

export type { UploadResponse } from "@cairn/proto/api";

export function uploadFile(formData: FormData) {
  return uploadApi.uploadFile(client, formData);
}

export function getFileUrl(fileId: string): string {
  return uploadApi.getFileUrl(getApiBaseUrl(), fileId);
}
