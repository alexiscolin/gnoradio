// A copy of the public catalog in the browser (IndexedDB: it outgrows
// localStorage), so a returning visitor reads only what changed. Every access
// is best effort: private mode, blocked storage or a full quota just mean the
// network, as on a first visit.

import { arr, type Infer, num, obj, str } from "./guard";
import { isAlbum, isArtist, isEvent, isGenres, isInfo, isPlaylist, isStations, isTrack } from "./schemas";

/** CACHE_VERSION: bump it when a stored record's schema or meaning changes; a release that keeps them keeps the visitors' cache. */
export const CACHE_VERSION = 3;

/** Store holds one value; the browser one is IndexedDB, tests pass an in-memory one. */
export interface Store {
  get(): Promise<unknown>;
  set(v: unknown): Promise<void>;
}

// Records are stored as the guards accepted them and re-checked on read with the same guards.
const isSnapshot = obj({
  key: str,
  fullAt: num, // last full read of everything
  metaAt: num, // last full read of artists, albums and playlists
  info: isInfo,
  radio: isStations,
  genres: isGenres,
  events: arr(isEvent),
  tracks: arr(isTrack),
  artists: arr(isArtist),
  albums: arr(isAlbum),
  playlists: arr(isPlaylist),
});
export type Snapshot = Infer<typeof isSnapshot>;

const READ_MS = 1500; // a storage that never answers must not hold the app back

/** readCache returns the stored snapshot for key, or null (none, another key, old shape, corrupt, unreadable). */
export async function readCache(store: Store, key: string): Promise<Snapshot | null> {
  try {
    const v = await Promise.race([store.get(), new Promise((r) => setTimeout(r, READ_MS, null))]);
    return isSnapshot(v) && v.key === key ? v : null;
  } catch {
    return null;
  }
}

/** writeCache stores s, silently giving up when the browser refuses. */
export async function writeCache(store: Store, s: Snapshot): Promise<void> {
  try { await store.set(s); } catch { /* quota, private mode: next visit reads the network */ }
}

const DB = "gnoradio";
const KV = "kv";
const SLOT = "catalog";

const err = (e: DOMException | null) => e ?? new Error("IndexedDB failed");
const done = <T,>(r: IDBRequest<T>) => new Promise<T>((ok, ko) => { r.onsuccess = () => { ok(r.result); }; r.onerror = () => { ko(err(r.error)); }; });

/** idbStore keeps the value in IndexedDB (database gnoradio, one slot). */
export function idbStore(): Store {
  let db: Promise<IDBDatabase> | undefined;
  const open = () => (db ??= new Promise<IDBDatabase>((ok, ko) => {
    const r = indexedDB.open(DB, 1); // throws where IndexedDB is missing: caught by the callers
    r.onupgradeneeded = () => { r.result.createObjectStore(KV); };
    r.onsuccess = () => { ok(r.result); };
    r.onerror = () => { ko(err(r.error)); };
  }));
  return {
    get: async () => done<unknown>((await open()).transaction(KV).objectStore(KV).get(SLOT)),
    set: async (v) => {
      const tx = (await open()).transaction(KV, "readwrite");
      tx.objectStore(KV).put(v, SLOT);
      await new Promise<void>((ok, ko) => { tx.oncomplete = () => { ok(); }; tx.onerror = tx.onabort = () => { ko(err(tx.error)); }; });
    },
  };
}
