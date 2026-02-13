/**
 * Minimal global type declarations for browser/Node.js APIs.
 *
 * This package targets both browser and server environments. Since we don't
 * include lib.dom.d.ts or @types/node, we declare the minimal subset of
 * browser APIs used by our code.
 */

/* eslint-disable @typescript-eslint/no-explicit-any */

// ─── TextEncoder / TextDecoder ───

declare class TextEncoder {
  encode(input?: string): Uint8Array;
  readonly encoding: string;
}

declare class TextDecoder {
  decode(input?: BufferSource, options?: { stream?: boolean }): string;
  readonly encoding: string;
}

// ─── DOM Exception ───

declare class DOMException extends Error {
  readonly code: number;
  readonly name: string;
  readonly message: string;
}

// ─── BufferSource ───

type BufferSource = ArrayBufferView | ArrayBuffer;

// ─── Event ───

interface Event {
  readonly type: string;
}

// ─── IndexedDB ───

interface IDBFactory {
  open(name: string, version?: number): IDBOpenDBRequest;
}

interface IDBDatabase {
  readonly objectStoreNames: DOMStringList;
  createObjectStore(name: string, options?: IDBObjectStoreParameters): IDBObjectStore;
  transaction(storeNames: string | string[], mode?: IDBTransactionMode): IDBTransaction;
  close(): void;
}

interface IDBObjectStoreParameters {
  keyPath?: string | string[] | null;
  autoIncrement?: boolean;
}

type IDBTransactionMode = "readonly" | "readwrite" | "versionchange";

interface IDBTransaction {
  objectStore(name: string): IDBObjectStore;
}

interface IDBObjectStore {
  put(value: any, key?: IDBValidKey): IDBRequest;
  get(key: IDBValidKey): IDBRequest;
  delete(key: IDBValidKey): IDBRequest;
}

type IDBValidKey = number | string | Date | BufferSource | IDBValidKey[];

interface IDBRequest<T = any> {
  result: T;
  error: DOMException | null;
  onsuccess: ((this: IDBRequest<T>, ev: Event) => any) | null;
  onerror: ((this: IDBRequest<T>, ev: Event) => any) | null;
}

interface IDBOpenDBRequest extends IDBRequest<IDBDatabase> {
  onupgradeneeded: ((this: IDBOpenDBRequest, ev: IDBVersionChangeEvent) => any) | null;
  onblocked: ((this: IDBOpenDBRequest, ev: Event) => any) | null;
}

interface IDBVersionChangeEvent extends Event {
  readonly oldVersion: number;
  readonly newVersion: number | null;
}

interface DOMStringList {
  contains(string: string): boolean;
  readonly length: number;
  item(index: number): string | null;
}

declare var indexedDB: IDBFactory;
