/**
 * File upload API — delegates to @cairn/proto.
 */

import { uploadApi } from "@cairn/proto";
import { client } from "./client.ts";

export type { UploadResponse } from "@cairn/proto/api";

export function uploadFile(file: File) {
  const formData = new FormData();
  formData.append("file", file);
  return uploadApi.uploadFile(client, formData);
}

export function getFileUrl(fileId: string): string {
  return uploadApi.getFileUrl("", fileId);
}
