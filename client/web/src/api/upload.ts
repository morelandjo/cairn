/**
 * File upload API — delegates to @murmuring/proto.
 */

import { uploadApi } from "@murmuring/proto";
import { client } from "./client.ts";

export type { UploadResponse } from "@murmuring/proto/api";

export function uploadFile(file: File) {
  const formData = new FormData();
  formData.append("file", file);
  return uploadApi.uploadFile(client, formData);
}

export function getFileUrl(fileId: string): string {
  return uploadApi.getFileUrl("", fileId);
}
