// Tracks GnoRadio points to on Audius or Jamendo keep only a pointer on chain
// (audius:<id>, jamendo:<id>, no title): both platforms' API terms allow
// session caching only (the CDN keeps them an hour). Their title, artist and cover come from /api/meta
// (netlify/functions/meta.mts) when a screen shows them, a bucket of on-chain
// ids at a time, and stay in memory for the session: never in the stored
// catalog (lib/cache.ts keeps the chain's records only).
import { useEffect, useMemo, useSyncExternalStore } from "react";
import { safeHttps } from "./safe";
import type { Artist, Catalog, Track } from "./types";

/** RefMeta mirrors netlify/refs.ts. */
export interface RefMeta {
  readonly title: string;
  readonly artist: string;
  readonly artistId: string;
  readonly artwork: string;
  readonly permalink: string;
  readonly streamable: boolean;
}

const REF = /^(audius|jamendo):[A-Za-z0-9]{1,32}$/;
/** CHUNK: a request covers one bucket of CHUNK track ids. Buckets are cut from the on-chain ids, which
 * never move, so every visitor asks the same URLs, the CDN answers them, and a new import only adds a bucket. */
export const CHUNK = 100;
const PARALLEL = 3;
/** LRU bound: a catalog's pointers, with room; least recently used out first. */
const MAX_KEPT = 10_000;

/** isRef: a pointer, by its audio (an artist who claimed it may also store a title). */
export const isRef = (t: Pick<Track, "audio">): boolean => REF.test(t.audio);

const kept = new Map<string, RefMeta | null>(); // insertion order = least recently used first
const asked = new Set<string>(); // in flight
const failed = new Map<number, { at: number; wait: number }>(); // bucket → last failure, and how long to leave it alone
const RETRY_MIN = 60_000, RETRY_MAX = 600_000;
let pointers = new Map<number, string>(); // the last named catalog's pointers: track id → audio
let version = 0;
const listeners = new Set<() => void>();

const touch = (k: string, v: RefMeta | null) => {
  kept.delete(k);
  kept.set(k, v);
  for (const old of kept.keys()) { if (kept.size <= MAX_KEPT) break; kept.delete(old); }
};

/** clearRefs empties the session cache (tests). */
export const clearRefs = (): void => { retrying.forEach(clearTimeout); retrying.clear(); kept.clear(); asked.clear(); failed.clear(); pointers = new Map(); };

const retrying = new Map<number, ReturnType<typeof setTimeout>>(); // bucket → its pending retry

/** loadMeta fetches the buckets holding these pointers (one /api/meta?bucket=N each, the answer holds the pointers
 * the chain has there), PARALLEL at a time; a failed or incomplete bucket is left alone for a minute, doubling up to
 * ten, then asked again by itself. True when it cached new answers. */
export async function loadMeta(tracks: readonly Pick<Track, "id" | "audio">[], fetcher: typeof fetch = fetch): Promise<boolean> {
  const buckets = new Map<number, Set<string>>();
  for (const t of tracks) if (REF.test(t.audio)) buckets.set(Math.floor(t.id / CHUNK), (buckets.get(Math.floor(t.id / CHUNK)) ?? new Set()).add(t.audio));
  const asks = [...buckets].filter(([b, ids]) => {
    const f = failed.get(b);
    return !(f && Date.now() < f.at + f.wait) && [...ids].some((r) => !kept.has(r) && !asked.has(r));
  }).map(([b, ids]) => [b, [...ids].sort()] as const);
  let fresh = false;
  for (let i = 0; i < asks.length; i += PARALLEL) {
    await Promise.all(asks.slice(i, i + PARALLEL).map(async ([b, ids]) => {
      ids.forEach((r) => asked.add(r));
      const r = await fetcher(`/api/meta?bucket=${String(b)}`).catch(() => null);
      // A 200 that is not a JSON object (the page of a deploy without the function) is a failure too.
      const body: unknown = r?.ok ? await r.json().catch(() => null) : null;
      ids.forEach((id) => asked.delete(id));
      const answers = body !== null && typeof body === "object" && !Array.isArray(body) ? (body as Record<string, RefMeta | null>) : null;
      for (const id of ids) if (answers && id in answers) { touch(id, answers[id] ?? null); fresh = true; }
      if (answers && ids.every((id) => id in answers)) { failed.delete(b); return; }
      // Unknown for now (a failed call, or a platform that did not answer): asked again after a pause, never cached as missing.
      const wait = Math.min((failed.get(b)?.wait ?? RETRY_MIN / 2) * 2, RETRY_MAX);
      failed.set(b, { at: Date.now(), wait });
      clearTimeout(retrying.get(b));
      retrying.set(b, setTimeout(() => {
        retrying.delete(b);
        void want(tracks.filter((t) => Math.floor(t.id / CHUNK) === b), fetcher);
      }, wait + 100));
    }));
  }
  return fresh;
}

/** want asks for the meta of the pointers among tracks a screen shows; screens re-render once it arrives. */
export function want(tracks: readonly Pick<Track, "id">[], fetcher: typeof fetch = fetch): Promise<void> {
  const mine = tracks.flatMap((t) => {
    const audio = pointers.get(t.id);
    return audio !== undefined && !kept.has(audio) && !asked.has(audio) ? [{ id: t.id, audio }] : [];
  });
  if (mine.length === 0) return Promise.resolve();
  // The whole bucket of each wanted pointer: the same URL for every visitor (CDN), a screen nearby is ready too.
  const buckets = new Set(mine.map((t) => Math.floor(t.id / CHUNK)));
  const all = [...pointers].filter(([id]) => buckets.has(Math.floor(id / CHUNK))).map(([id, audio]) => ({ id, audio }));
  return loadMeta(all, fetcher).then((fresh) => { if (fresh) { version++; listeners.forEach((f) => { f(); }); } });
}

/** useWant asks for the pointers among tracks once a screen shows them; a new array of the same ids asks nothing. */
export function useWant(tracks: readonly Pick<Track, "id">[]): void {
  const key = tracks.map((t) => t.id).join(",");
  // eslint-disable-next-line react-hooks/exhaustive-deps -- key: the ids are all want reads
  useEffect(() => { void want(tracks); }, [key]);
}

const label = (audio: string, what: string) => `${audio.startsWith("jamendo:") ? "Jamendo" : "Audius"} ${what}`;

/**
 * nameRefs names the catalog's pointers from the meta in memory: title, artist,
 * cover, source link; one not fetched yet reads as its platform ("Audius
 * track"), one the platform no longer serves (unknown, not streamable) leaves
 * the lists for this session (still known by id, so the player does not ask the chain for it). It works on the chain's catalog, never changes it.
 */
export function nameRefs(cat: Catalog): Catalog {
  pointers = new Map(cat.tracks.filter(isRef).map((t) => [t.id, t.audio]));
  if (pointers.size === 0) return cat;
  const names = new Map<number, string>();
  const links = new Map<number, string>(); // a pointer artist's platform link: a live permalink of one of its tracks
  const gone = new Set<number>(); // browse lists leave these out; byId keeps them, so the player knows the id (it fails on its own)
  const named = (t: Track): Track => {
    if (!isRef(t)) return t;
    const m = kept.get(t.audio);
    if (m === undefined) return { ...t, title: t.title || label(t.audio, "track"), artistName: t.artistName || label(t.audio, "artist") };
    if (!m?.streamable) { gone.add(t.id); return { ...t, title: t.title || label(t.audio, "track"), artistName: t.artistName || label(t.audio, "artist") }; }
    if (m.artist) names.set(t.artist, m.artist);
    if (safeHttps(m.permalink)) links.set(t.artist, safeHttps(m.permalink));
    return { ...t, title: t.title || m.title || label(t.audio, "track"), artistName: t.artistName || m.artist || label(t.audio, "artist"), cover: safeHttps(m.artwork), source: safeHttps(m.permalink) };
  };
  const all = cat.tracks.map(named);
  const tracks = all.filter((t) => !gone.has(t.id));
  const withLink = (a: Artist, link = ""): Artist => (a.source === "" && link !== "" && (a.kind === "audius" || a.kind === "jamendo") ? { ...a, source: link } : a);
  const artists = new Map([...cat.artists].map(([id, a]) => [id, withLink(a.name !== "" ? a : { ...a, name: names.get(id) ?? (a.kind === "jamendo" ? "Jamendo artist" : "Audius artist") }, links.get(id))]));
  return { ...cat, tracks, byId: new Map(all.map((t) => [t.id, t])), artists };
}

const subscribe = (f: () => void) => { listeners.add(f); return () => { listeners.delete(f); }; };

/** useNamedRefs is the chain's catalog with its pointers named, renamed as meta arrives. */
export function useNamedRefs(cat: Catalog | null): Catalog | null {
  const v = useSyncExternalStore(subscribe, () => version, () => version);
  // eslint-disable-next-line react-hooks/exhaustive-deps -- v: the meta in memory changed
  return useMemo(() => (cat ? nameRefs(cat) : null), [cat, v]);
}
