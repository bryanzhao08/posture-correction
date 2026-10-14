// Node 23+: node scripts/check-storage.ts. Exercises request-success followed by transaction abort.
import assert from "node:assert/strict";
import { pref, setPref, saveSession, listSessions, type StoredSession } from "../src/app/store.ts";

Object.defineProperty(globalThis, "localStorage", { value: {
  getItem: () => null, setItem: () => { throw new Error("Storage blocked"); },
} });
setPref("handedness", "left");
assert.equal(pref("handedness", "right"), "left");

let complete: (() => void) | undefined;
let abort: (() => void) | undefined;
let requestError: (() => void) | undefined;
let write = false;
Object.defineProperty(globalThis, "indexedDB", { value: {
  open: () => {
    const req = { result: { transaction: (storeName: string, mode: string) => {
      write = mode === "readwrite";
      const tx = { oncomplete: null as (() => void) | null, onabort: null as (() => void) | null,
        onerror: null as (() => void) | null, objectStore: () => ({
          put: () => request("test-session"), getAll: () => request([]),
        }) };
      function request(result: unknown) {
        const r = { result, onsuccess: null as (() => void) | null, onerror: null as (() => void) | null };
        queueMicrotask(() => {
          r.onsuccess?.();
          complete = () => tx.oncomplete?.();
          abort = () => tx.onabort?.();
          requestError = () => { r.onerror?.(); tx.onerror?.(); };
          if (!write) complete();
        });
        return r;
      }
      return tx;
    } }, onsuccess: null as (() => void) | null };
    queueMicrotask(() => req.onsuccess?.());
    return req;
  },
} });
const session = { id: "test-session", started_at: "2026-10-13T00:00:00Z" } as StoredSession;
let settled = false;
const saving = saveSession(session).then(() => { settled = true; });
await new Promise((resolve) => setTimeout(resolve, 0));
assert.equal(settled, false, "Request success must not settle a write before transaction commit");
abort!();
await saving;
assert.deepEqual(await listSessions(), [session], "Aborted write must fall back to memory");
settled = false;
const committing = saveSession({ ...session, id: "committed-session" }).then(() => { settled = true; });
await new Promise((resolve) => setTimeout(resolve, 0));
assert.equal(settled, false);
complete!();
await committing;
assert.equal(settled, true, "Transaction completion must settle the write");
settled = false;
const failing = saveSession({ ...session, id: "failed-session" }).then(() => { settled = true; });
await new Promise((resolve) => setTimeout(resolve, 0));
requestError!();
await new Promise((resolve) => setTimeout(resolve, 0));
assert.equal(settled, false, "Request error must wait for transaction abort");
abort!();
await failing;
assert.equal(settled, true);
assert((await listSessions()).some((s) => s.id === "failed-session"));
console.log("Preferences and transaction-abort regression checks passed");
