import { describe, expect, it, vi } from "vitest";
import { audioURLs, batched, cleanArtist, loadCatalog, settle, sortTracks } from "./catalog";
import { CACHE_VERSION, type Snapshot } from "./cache";
import { isArtist } from "./schemas";
import type { Track } from "./types";
import { CHAIN_ID, DataError, REALMS, RealmError } from "./gno";

// The chain's reads by expression prefix (loadCatalog's own reads only).
const reads = vi.hoisted((): { answer: (expr: string) => unknown } => ({ answer: () => ({}) }));
vi.mock("./gno", async (orig) => ({ ...(await orig<object>()), qjson: (_pkg: string, expr: string) => Promise.resolve(reads.answer(expr)) }));

describe("audioURLs", () => {
  it("resolves every supported scheme", () => {
    expect(audioURLs({ id: 1, audio: "ipfs://bafy123" })).toEqual(["https://ipfs.io/ipfs/bafy123", "https://dweb.link/ipfs/bafy123", "https://cloudflare-ipfs.com/ipfs/bafy123"]);
    expect(audioURLs({ id: 1, audio: "ar://abc" })).toEqual(["https://arweave.net/abc"]);
    expect(audioURLs({ id: 1, audio: "audius:x5dg3" })).toEqual(["https://api.audius.co/v1/tracks/x5dg3/stream?app_name=GnoRadio"]);
    expect(audioURLs({ id: 205, audio: "jamendo:1886257" })).toEqual([]); // its stream comes with the bucket meta (lib/refs.ts)
    expect(audioURLs({ id: 1, audio: "https://archive.org/download/a/b.mp3" })).toEqual(["https://archive.org/download/a/b.mp3"]);
  });
});

describe("settle", () => {
  it("skips realm refusals and bad records but fails on network errors", async () => {
    const warn = vi.spyOn(console, "warn").mockImplementation(() => undefined);
    await expect(settle([Promise.resolve(1), Promise.reject(new RealmError("hidden")), Promise.reject(new DataError("bad")), Promise.resolve(4)])).resolves.toEqual([1, 4]);
    expect(warn).toHaveBeenCalledTimes(1);
    await expect(settle([Promise.resolve(1), Promise.reject(new Error("RPC returned 502"))])).rejects.toThrow("RPC returned 502");
    warn.mockRestore();
  });
});

describe("batched", () => {
  it("re-reads a batch item by item when one record is bad, losing only that record", async () => {
    const warn = vi.spyOn(console, "warn").mockImplementation(() => undefined);
    const many = (o: number) => (o === 0 ? Promise.reject(new DataError("bad record")) : Promise.resolve([o + 1]));
    const one = (id: number) => (id === 2 ? Promise.reject(new DataError("bad")) : Promise.resolve(id));
    const out = await batched(103, many, one);
    expect(out).toHaveLength(100); // 99 of ids 1..100 (id 2 is bad), plus [101] from the second batch
    expect(out).not.toContain(2);
    expect(out).toContain(101);
    warn.mockRestore();
  });
});

describe("sortTracks", () => {
  const t = (id: number, likes = 0, tips = 0) => ({ id, likes, tips, created: id }) as Track;
  const ids = (ts: readonly Track[]) => ts.map((x) => x.id);
  const all = Array.from({ length: 50 }, (_, i) => t(i + 1, i % 3, (i * 7) % 5));
  it("mixes the same way all day and differently the next day", () => {
    expect(ids(sortTracks(all, "mix", 100))).toEqual(ids(sortTracks(all, "mix", 100)));
    expect(ids(sortTracks(all, "mix", 101))).not.toEqual(ids(sortTracks(all, "mix", 100)));
    expect(new Set(ids(sortTracks(all, "mix", 100))).size).toBe(50);
  });
  it("puts the most liked, most tipped and newest first", () => {
    expect(sortTracks(all, "liked", 1)[0]?.likes).toBe(2);
    expect(sortTracks(all, "tipped", 1)[0]?.tips).toBe(4);
    expect(sortTracks(all, "new", 1)[0]?.id).toBe(50);
  });
});

describe("cleanArtist", () => {
  const raw = { id: 3, name: "Ana", kind: "artist", owner: "g1x", bio: "", source: "", joined: 1, tips: 0, followers: 0, verified: true, tracks: [], albums: [] };
  it("reads a verified artist's proof host from ArtistJSON, a bare host name only", () => {
    const a = { ...raw, proofHost: "Ana.Example" };
    expect(isArtist(a)).toBe(true);
    expect(cleanArtist(a as never).proofHost).toBe("ana.example");
    expect(cleanArtist({ ...raw, proofHost: "<b>x</b>" } as never).proofHost).toBe("");
    expect(cleanArtist({ ...raw, verified: false, proofHost: "ana.example" } as never).proofHost).toBe("");
    expect(cleanArtist(raw as never).proofHost).toBe(""); // an older realm
  });
});

describe("loadCatalog revalidation", () => {
  it("drops a cached track the moderator hid, even at the bottom of the re-read range", async () => {
    const tr = (id: number) => ({
      id, artist: 1, artistName: "A", claimed: true, origin: "artist", title: `T${String(id)}`, genre: 1, duration: 100, license: "CC0", cmo: "none",
      credits: "", audio: `https://media.example/${String(id)}.mp3`, audioSha256: "", cover: "", coverSha256: "", source: "", attribution: "", album: 0,
      created: id, likes: 0, tips: 0, supporters: 0, splits: [],
    });
    const info = { version: "v1", admin: "g1admin", artists: 1, tracks: 4, albums: 0, playlists: 0 };
    const artist = { id: 1, name: "A", kind: "artist", owner: "", bio: "", source: "", joined: 0, tips: 0, followers: 0, verified: false, tracks: [1, 2, 3, 4], albums: [] };
    const snap = {
      key: [CHAIN_ID, REALMS.catalog, REALMS.radio, REALMS.tickets, String(CACHE_VERSION)].join("|"), fullAt: Date.now(), metaAt: Date.now(),
      info, radio: { pending: 0, stations: [] }, genres: [], events: [], tracks: [4, 3, 2, 1].map(tr), artists: [artist], albums: [], playlists: [],
    } as unknown as Snapshot;
    // Track 1 is hidden now: the page holds 2..4, and the lowest id it returns (2) is above it.
    reads.answer = (expr) => {
      if (expr.startsWith("Info(")) return info;
      if (expr.startsWith("GenresJSON")) return [];
      if (expr.startsWith("StationsJSON")) return { pending: 0, stations: [] };
      if (expr.startsWith("EventsJSON")) return { events: [] };
      if (expr.startsWith("TracksJSON")) return { total: 4, tracks: [4, 3, 2].map(tr) };
      throw new Error(`unexpected read ${expr}`);
    };
    const store = { get: () => Promise.resolve(snap), set: () => Promise.resolve() };
    const cat = await loadCatalog({ store });
    expect(cat.tracks.map((t) => t.id)).toEqual([4, 3, 2]);
  });
});

describe("loadCatalog bad page", () => {
  it("re-reads a bad page by ids counted from the page-0 total, not Info()", async () => {
    const tr = (id: number) => ({
      id, artist: 1, artistName: "A", claimed: true, origin: "artist", title: `T${String(id)}`, genre: 1, duration: 100, license: "CC0", cmo: "none",
      credits: "", audio: `https://media.example/${String(id)}.mp3`, audioSha256: "", cover: "", coverSha256: "", source: "", attribution: "", album: 0,
      created: id, likes: 0, tips: 0, supporters: 0, splits: [],
    });
    const asked: string[] = [];
    // Info() says 101 tracks; one was published since, so page 0 is cut from 102.
    reads.answer = (expr) => {
      if (expr.startsWith("Info(")) return { version: "v1", admin: "g1admin", artists: 0, tracks: 101, albums: 0, playlists: 0 };
      if (expr.startsWith("GenresJSON")) return [];
      if (expr.startsWith("StationsJSON")) return { pending: 0, stations: [] };
      if (expr.startsWith("EventsJSON")) return { events: [] };
      if (expr.startsWith("TracksJSON(0,")) return { total: 102, tracks: [] };
      if (expr.startsWith("TracksJSON(")) return Promise.reject(new DataError("bad record"));
      asked.push(expr);
      return tr(Number(/\d+/.exec(expr)?.[0]));
    };
    await loadCatalog({ store: { get: () => Promise.resolve(undefined), set: () => Promise.resolve() } });
    expect(asked).toEqual(["TrackJSON(2)", "TrackJSON(1)"]);
  });
});
