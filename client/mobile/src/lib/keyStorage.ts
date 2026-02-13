/**
 * Key storage — uses expo-secure-store with 2KB chunking for larger values.
 * Same interface as web keyStorage.ts.
 */

import * as SecureStore from "expo-secure-store";

const CHUNK_SIZE = 2000; // expo-secure-store 2KB limit per item

async function setChunked(key: string, value: string): Promise<void> {
  if (value.length <= CHUNK_SIZE) {
    await SecureStore.setItemAsync(key, value);
    await SecureStore.deleteItemAsync(`${key}_chunks`).catch(() => {});
    return;
  }

  const chunks = Math.ceil(value.length / CHUNK_SIZE);
  await SecureStore.setItemAsync(`${key}_chunks`, String(chunks));
  for (let i = 0; i < chunks; i++) {
    const chunk = value.slice(i * CHUNK_SIZE, (i + 1) * CHUNK_SIZE);
    await SecureStore.setItemAsync(`${key}_chunk_${i}`, chunk);
  }
}

async function getChunked(key: string): Promise<string | null> {
  const chunksStr = await SecureStore.getItemAsync(`${key}_chunks`);
  if (!chunksStr) {
    return SecureStore.getItemAsync(key);
  }

  const chunks = parseInt(chunksStr, 10);
  let result = "";
  for (let i = 0; i < chunks; i++) {
    const chunk = await SecureStore.getItemAsync(`${key}_chunk_${i}`);
    if (chunk === null) return null;
    result += chunk;
  }
  return result;
}

async function deleteChunked(key: string): Promise<void> {
  const chunksStr = await SecureStore.getItemAsync(`${key}_chunks`);
  if (chunksStr) {
    const chunks = parseInt(chunksStr, 10);
    for (let i = 0; i < chunks; i++) {
      await SecureStore.deleteItemAsync(`${key}_chunk_${i}`).catch(() => {});
    }
    await SecureStore.deleteItemAsync(`${key}_chunks`).catch(() => {});
  }
  await SecureStore.deleteItemAsync(key).catch(() => {});
}

export async function storeKey(key: string, value: string): Promise<void> {
  await setChunked(`murmur_${key}`, value);
}

export async function loadKey(key: string): Promise<string | null> {
  return getChunked(`murmur_${key}`);
}

export async function deleteKey(key: string): Promise<void> {
  await deleteChunked(`murmur_${key}`);
}

/** Synchronous load — uses expo-secure-store sync API (SDK 52+). */
export function loadKeySync(key: string): string | null {
  return SecureStore.getItem(`murmur_${key}`);
}

/** Synchronous store — stores sync + async for chunked fallback. */
export function storeKeySync(key: string, value: string): void {
  if (value.length <= CHUNK_SIZE) {
    SecureStore.setItem(`murmur_${key}`, value);
  } else {
    // Fall back to async for chunked values
    storeKey(key, value).catch(() => {});
  }
}

/** Synchronous delete. */
export function deleteKeySync(key: string): void {
  SecureStore.deleteItemAsync(`murmur_${key}`).catch(() => {});
  // Also clean up chunks
  deleteChunked(`murmur_${key}`).catch(() => {});
}
