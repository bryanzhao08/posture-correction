// Sessions are kept only in this browser (IndexedDB). Nothing is uploaded.
// If IndexedDB is unavailable (private mode, blocked storage) sessions live in memory for the visit.
import type { Rep } from "../engine/engine.ts";
import type { Summary } from "../engine/scoring.ts";

export interface StoredSession {
  id: string;
  sport: string;
  view: string;
  focus: string | null;
  training: string | null;
  handedness: string;
  source: "camera" | "sample";
  started_at: string;   // ISO time
  duration_s: number;
  summary: Summary;
  reps: Rep[];
}

const DB = "formcoach";
const STORE = "sessions";
let memory: StoredSession[] = [];
let dbPromise: Promise<IDBDatabase | null> | null = null;

function open(): Promise<IDBDatabase | null> {
  dbPromise ??= new Promise((resolve) => {
    try {
      const req = indexedDB.open(DB, 1);
      req.onupgradeneeded = () => req.result.createObjectStore(STORE, { keyPath: "id" });
      req.onsuccess = () => resolve(req.result);
      req.onerror = () => resolve(null);
      req.onblocked = () => resolve(null);
    } catch {
      resolve(null);
    }
  });
  return dbPromise;
}

function run<T>(mode: IDBTransactionMode, fn: (s: IDBObjectStore) => IDBRequest<T>): Promise<T | null> {
  return open().then((db) => new Promise((resolve) => {
    if (!db) return resolve(null);
    try {
      const req = fn(db.transaction(STORE, mode).objectStore(STORE));
      req.onsuccess = () => resolve(req.result);
      req.onerror = () => resolve(null);
    } catch {
      resolve(null);
    }
  }));
}

export async function saveSession(s: StoredSession): Promise<void> {
  const ok = await run("readwrite", (st) => st.put(s));
  if (ok === null) memory = [...memory.filter((m) => m.id !== s.id), s];
}

export async function listSessions(): Promise<StoredSession[]> {
  const rows = (await run<StoredSession[]>("readonly", (st) => st.getAll())) ?? [];
  const all = [...rows, ...memory.filter((m) => !rows.some((r) => r.id === m.id))];
  return all.sort((a, b) => (a.started_at < b.started_at ? 1 : -1));
}

export async function deleteSession(id: string): Promise<void> {
  memory = memory.filter((m) => m.id !== id);
  await run("readwrite", (st) => st.delete(id));
}

export async function clearSessions(): Promise<void> {
  memory = [];
  await run("readwrite", (st) => st.clear());
}

export function storageIsPersistent(): Promise<boolean> {
  return open().then((db) => db !== null);
}

// Small per-visitor preferences.
export function pref<T>(key: string, fallback: T): T {
  try {
    const v = localStorage.getItem("fc." + key);
    return v === null ? fallback : (JSON.parse(v) as T);
  } catch {
    return fallback;
  }
}

export function setPref(key: string, value: unknown) {
  try {
    localStorage.setItem("fc." + key, JSON.stringify(value));
  } catch {
    /* storage blocked: preference lasts for this visit only */
  }
}
