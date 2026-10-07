import { beforeEach, describe, expect, it, vi } from "vitest";
import { readCache, type Snapshot, type Store } from "./cache";
import { loadCatalog, touchedBy } from "./catalog";
import { REALMS, RealmError, qjson } from "./gno";
import type { Catalog } from "./types";

vi.mock("./gno", async (orig) => ({ ...(await orig<object>()), qjson: vi.fn() }));

// ---- a tiny chain: tracks 1..nTracks (newest first, 100 a page), artists 1..nArtists ----
const chain = { nTracks: 250, nArtists: 3, hidden: new Set<number>(), likes: new Map<number, number>(), followers: 0 };
const track = (id: number) => ({
  id, artist: (id % chain.nArtists) + 1, artistName: "A", claimed: false, origin: "curated", title: `T${String(id)}`, genre: 1, duration: 200,
  license: "CC-BY", cmo: "none", credits: "", audio: "https://x/a.mp3", audioSha256: "", cover: "", coverSha256: "", source: "", attribution: "",
  album: 0, created: id, likes: chain.likes.get(id) ?? 0, tips: 0, supporters: 0, splits: [],
});
const artist = (id: number) => ({ id, name: `A${String(id)}`, kind: "curated", owner: "", bio: "", source: "", joined: 0, tips: 0, followers: id === 1 ? chain.followers : 0, verified: false, tracks: [], albums: [] });
const calls: string[] = [];

function answer(expr: string): unknown {
  const m = /^(\w+)\((\d*)(?:, (\d+))?/.exec(expr);
  const [fn, a = "0"] = [m?.[1], m?.[2]];
  const n = Number(a);
  switch (fn) {
    case "Info": return { version: "v0", admin: "g1admin", artists: chain.nArtists, tracks: chain.nTracks, albums: 0, playlists: 0 };
    case "GenresJSON": return [{ id: 1, name: "Ambient" }];
    case "StationsJSON": return { pending: 0, stations: [{ id: 1, name: "Ambient", genre: 1, tracks: 10, loop: 0, queued: 0, now: { track: 5, offset: 0, queued: false } }] };
    case "EventsJSON": return { events: [] };
    case "TracksJSON": {
      const top = chain.nTracks - n;
      return { tracks: Array.from({ length: Math.max(0, Math.min(100, top)) }, (_, j) => top - j).filter((id) => !chain.hidden.has(id)).map(track) };
    }
    case "TrackJSON":
      if (chain.hidden.has(n) || n > chain.nTracks) throw new RealmError("catalog: unknown track");
      return track(n);
    case "ArtistsJSON": return { artists: Array.from({ length: Math.max(0, Math.min(100, chain.nArtists - n)) }, (_, j) => artist(n + j + 1)) };
    case "ArtistJSON": return artist(n);
    case "AlbumsJSON": return { albums: [] };
    case "PlaylistsJSON": return { playlists: [] };
  }
  throw new Error(`unexpected ${expr}`);
}


const memory = (): Store & { value: unknown } => {
  const s = { value: undefined as unknown, get: () => Promise.resolve(s.value), set: (v: unknown) => { s.value = structuredClone(v); return Promise.resolve(); } };
  return s;
};
const broken: Store = { get: () => Promise.reject(new Error("blocked")), set: () => { throw new Error("quota"); } };
const flush = () => new Promise((r) => setTimeout(r, 0));
const pages = () => calls.filter((c) => c.startsWith("TracksJSON"));

/** warm loads the catalog once into a fresh store, then clears the call log. */
async function warm(): Promise<Store & { value: unknown }> {
  const store = memory();
  await loadCatalog({ store });
  await flush();
  calls.length = 0;
  return store;
}
const age = (store: { value: unknown }, ms: number, field: "fullAt" | "metaAt" = "fullAt") => {
  const s = store.value as { fullAt: number; metaAt: number };
  s[field] -= ms;
  if (field === "fullAt") s.metaAt -= ms;
};

beforeEach(() => {
  // restoreMocks resets the mock before each test
  vi.mocked(qjson).mockImplementation((_pkg, expr) => {
    calls.push(expr);
    return Promise.resolve().then(() => answer(expr) as never);
  });
  Object.assign(chain, { nTracks: 250, nArtists: 3, hidden: new Set(), likes: new Map(), followers: 0 });
  calls.length = 0;
});

describe("catalog cache", () => {
  it("shows the stored catalog before any network read", async () => {
    const store = await warm();
    let first: Catalog | undefined;
    const out = loadCatalog({ store, cached: (c) => { first = c; expect(calls).toEqual([]); } });
    await out;
    expect(first?.tracks).toHaveLength(250);
    expect(first?.artists.size).toBe(3);
  });

  it("revalidates with only the new and recent track pages, keeping artists", async () => {
    const store = await warm();
    chain.nTracks = 260; // 10 new tracks
    const c = await loadCatalog({ store });
    expect(pages()).toEqual(["TracksJSON(0, 100)", "TracksJSON(100, 100)", "TracksJSON(200, 100)"]); // 1 new + 2 recent, capped at 3
    expect(calls.some((x) => x.startsWith("ArtistsJSON"))).toBe(false);
    expect(c.tracks.map((t) => t.id)).toEqual(Array.from({ length: 260 }, (_, i) => 260 - i));
    await flush();
    calls.length = 0;
    chain.nTracks = 1000;
    await loadCatalog({ store }); // 740 new: 8 pages + 2 recent
    expect(pages()).toHaveLength(10);
  });

  it("drops a track hidden since, and re-reads artists when Info() counts change", async () => {
    const store = await warm();
    chain.hidden.add(240);
    chain.nArtists = 4;
    const c = await loadCatalog({ store });
    expect(c.byId.has(240)).toBe(false);
    expect(calls).toContain("ArtistsJSON(0, 100)");
    expect(c.artists.size).toBe(4);
  });

  it("re-reads artists after META_TTL and everything after FULL_TTL", async () => {
    const store = await warm();
    age(store, 7 * 3600_000, "metaAt");
    await loadCatalog({ store });
    expect(calls).toContain("ArtistsJSON(0, 100)");
    expect(pages()).toHaveLength(2);
    await flush();
    calls.length = 0;
    chain.hidden.add(3); // an old track, outside the recent pages
    age(store, 25 * 3600_000);
    const c = await loadCatalog({ store });
    expect(pages()).toHaveLength(3);
    expect(c.byId.has(3)).toBe(false);
  });

  it("re-reads what a transaction touched: a liked old track and its artist, a followed artist", async () => {
    const store = await warm();
    chain.likes.set(7, 1);
    let c = await loadCatalog({ store, touched: touchedBy({ pkg: REALMS.catalog, func: "Like", args: ["7"] }) });
    expect(c.byId.get(7)?.likes).toBe(1);
    expect(calls).toContain("TrackJSON(7)");
    expect(calls).toContain(`ArtistJSON(${String(track(7).artist)})`);
    await flush();
    chain.followers = 5;
    c = await loadCatalog({ store, touched: touchedBy({ pkg: REALMS.catalog, func: "Follow", args: ["1"] }) });
    expect(c.artists.get(1)?.followers).toBe(5);
    await flush();
    chain.hidden.add(9); // the moderator hides an old track
    c = await loadCatalog({ store, touched: touchedBy({ pkg: REALMS.catalog, func: "HideTrack", args: ["9", "true", "spam"] }) });
    expect(c.byId.has(9)).toBe(false);
    await flush();
    chain.hidden.delete(9); // and restores it
    c = await loadCatalog({ store, touched: touchedBy({ pkg: REALMS.catalog, func: "HideTrack", args: ["9", "false", ""] }) });
    expect(c.tracks.map((t) => t.id).slice(-9)).toEqual([9, 8, 7, 6, 5, 4, 3, 2, 1]);
    expect(touchedBy({ pkg: REALMS.catalog, func: "RegisterArtist", args: ["x", ""] })).toBe("all");
    expect(touchedBy({ pkg: REALMS.radio, func: "TipOnAir", args: ["1", "12", "0", ""] })).toEqual({ tracks: [12], artists: [] });
  });

  it("ignores a corrupt or other-format cache, and works when storage is refused", async () => {
    const store = await warm();
    (store.value as Snapshot as { tracks: unknown[] }).tracks.push({ id: "bad" });
    expect(await readCache(store, (store.value as Snapshot).key)).toBeNull();
    let shown = false;
    const c = await loadCatalog({ store, cached: () => { shown = true; } });
    expect(shown).toBe(false);
    expect(c.tracks).toHaveLength(250);
    expect(pages()).toHaveLength(3);
    await flush();
    expect(await readCache(store, (store.value as Snapshot).key)).not.toBeNull(); // rewritten whole

    const c2 = await loadCatalog({ store: broken });
    expect(c2.tracks).toHaveLength(250);
  });
});
