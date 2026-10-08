import { useEffect, useSyncExternalStore } from "react";
import { mediaURLs } from "./safe";
import type { Track } from "./types";

// Some tracks point to audio that does not exist (a wrong CID, a host that
// went away). The app finds out before anyone presses play: a detached <audio>
// reads only each source's metadata, a few at a time, and the answer is kept in
// the browser (a working track for a week, a dead one for 6 hours, so a
// gateway outage does not hide a track for long). The player also reports a
// track whose every source failed.

type Media = Pick<Track, "id" | "audio">;
type Status = "ok" | "dead";

const KEY = "gnoradio.playable";
const TTL: Readonly<Record<Status, number>> = { ok: 7 * 86400_000, dead: 6 * 3600_000 };
export const PROBE_MS = 8000;
const PARALLEL = 3;
export const UNAVAILABLE = "Audio unavailable";

let known = new Map<number, { s: Status; at: number }>();
try {
  known = new Map(JSON.parse(localStorage.getItem(KEY) ?? "[]") as [number, { s: Status; at: number }][]);
} catch { /* no storage: probe again */ }

let version = 0;
const subscribers = new Set<() => void>();

function record(id: number, s: Status) {
  known.set(id, { s, at: Date.now() });
  try { localStorage.setItem(KEY, JSON.stringify([...known].filter(([, v]) => Date.now() - v.at < TTL[v.s]))); } catch { /* memory only */ }
  version++;
  subscribers.forEach((f) => { f(); });
}

/** status is what is known of a track's audio: "dead" with no source at all, undefined until probed. */
export function status(t: Media): Status | undefined {
  if (mediaURLs(t.audio).length === 0) return "dead";
  const k = known.get(t.id);
  return k && Date.now() - k.at < TTL[k.s] ? k.s : undefined;
}

export const isDead = (t: Media | undefined): boolean => t !== undefined && status(t) === "dead";

/** markDead is the player's report: every source of this track failed. Offline, nothing is learnt. */
export function markDead(id: number) {
  if (typeof navigator === "undefined" || navigator.onLine) record(id, "dead");
}

/** probeURL resolves true once url's metadata loads, false on an error or after PROBE_MS. */
function probeURL(url: string): Promise<boolean> {
  return new Promise((resolve) => {
    const a = new Audio();
    a.preload = "metadata";
    const done = (ok: boolean) => {
      window.clearTimeout(timer);
      a.onloadedmetadata = a.onerror = null;
      a.removeAttribute("src");
      resolve(ok);
    };
    const timer = window.setTimeout(() => { done(false); }, PROBE_MS);
    a.onloadedmetadata = () => { done(true); };
    a.onerror = () => { done(false); };
    a.src = url;
  });
}

/** probe tries every source of a track in order (IPFS has several gateways). */
export async function probe(t: Media): Promise<boolean> {
  for (const url of mediaURLs(t.audio)) if (await probeURL(url)) return true;
  return false;
}

const waiting: Media[] = [];
const queued = new Set<number>();
let running = 0;

function pump() {
  while (running < PARALLEL && waiting.length > 0) {
    const t = waiting.shift();
    if (!t) return;
    running++;
    void probe(t).then((ok) => {
      if (ok) record(t.id, "ok");
      else markDead(t.id);
    }).finally(() => { running--; queued.delete(t.id); pump(); });
  }
}

/** check queues a probe of t unless its status is known or one is on its way. */
export function check(t: Media) {
  if (status(t) !== undefined || queued.has(t.id)) return;
  queued.add(t.id);
  waiting.push(t);
  pump();
}

// Rows probe when they scroll into view, not all at once.
const seen = new WeakMap<Element, Media>();
let io: IntersectionObserver | null = null;

/** checkWhenSeen is a ref callback: it probes t once its element is on screen. */
export const checkWhenSeen = (t: Media) => (el: Element | null) => {
  if (!el || status(t) !== undefined) return;
  if (typeof IntersectionObserver === "undefined") { check(t); return; }
  io ??= new IntersectionObserver((entries) => {
    for (const e of entries) {
      const m = seen.get(e.target);
      if (!e.isIntersecting || !m) continue;
      io?.unobserve(e.target);
      check(m);
    }
  });
  seen.set(el, t);
  io.observe(el);
};

const subscribe = (f: () => void) => { subscribers.add(f); return () => { subscribers.delete(f); }; };

/**
 * usePlayable re-renders on every new answer. With tracks, it probes them now
 * (the page's main play buttons); allDead is true only when every one is known dead.
 */
export function usePlayable(tracks: readonly Media[] = []): { readonly allDead: boolean } {
  useSyncExternalStore(subscribe, () => version);
  useEffect(() => { tracks.forEach(check); }, [tracks]); // check is a no-op once a status is known
  return { allDead: tracks.length > 0 && tracks.every(isDead) };
}

/** resetPlayable forgets everything (tests). */
export function resetPlayable() {
  known.clear();
  waiting.length = 0;
  queued.clear();
  running = 0;
  version++;
}
