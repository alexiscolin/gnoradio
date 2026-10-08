import { beforeEach, describe, expect, it, vi } from "vitest";
import { CHUNK, clearRefs, isRef, loadMeta, nameRefs, type RefMeta, want } from "./refs";
import type { Artist, Catalog, Track } from "./types";

const meta = (title: string, artist = "Night Tapes", streamable = true): RefMeta =>
  ({ title, artist, artistId: "u1", artwork: "https://creatornode.audius.co/a.jpg", permalink: "https://audius.co/nt/x", streamable });

const track = (id: number, audio: string, title = ""): Track => ({
  id, artist: 7, artistName: "", claimed: false, origin: audio.startsWith("jamendo:") ? "jamendo" : "audius", title, genre: 1, duration: 200,
  license: "Audius-OML", cmo: "none", credits: "", audio, audioSha256: "", cover: "", coverSha256: "", source: "", attribution: "",
  album: 0, created: 0, likes: 0, tips: 0, supporters: 0, splits: [],
});

const artist: Artist = { id: 7, name: "", kind: "audius", owner: "", bio: "", source: "", joined: 0, tips: 0, followers: 0, verified: false, promo: 0, sponsor: undefined, proofHost: "", tracks: [], albums: [] };
const catalogOf = (tracks: Track[]): Catalog => ({
  tracks, byId: new Map(tracks.map((t) => [t.id, t])), artists: new Map([[7, artist]]),
  albums: [], playlists: [], genres: [], stations: [], pending: 0, newFloor: 0, events: [], admin: "",
});

/** api answers /api/meta from a table and records every URL asked. */
function api(table: Record<string, RefMeta | null>, ok = true) {
  const asked: string[] = [];
  const f = vi.fn((url: string) => {
    asked.push(url);
    const ids = new URL(url, "https://x").searchParams.get("ids")?.split(",") ?? [];
    return Promise.resolve(new Response(JSON.stringify(Object.fromEntries(ids.map((i) => [i, table[i] ?? null]))), { status: ok ? 200 : 502 }));
  });
  return { f: f as unknown as typeof fetch, asked };
}

beforeEach(clearRefs);

describe("isRef", () => {
  it("is a pointer only while the chain stores no title (a claimed artist may name it)", () => {
    expect(isRef(track(1, "audius:Ab1"))).toBe(true);
    expect(isRef(track(1, "jamendo:42"))).toBe(true);
    expect(isRef(track(1, "audius:Ab1", "Named by its artist"))).toBe(false);
    expect(isRef(track(1, "ipfs://bafy"))).toBe(false);
  });
});

describe("loadMeta", () => {
  it("asks one URL per bucket of on-chain ids (the same for every visitor), and nothing it already holds", async () => {
    const { f, asked } = api({ "audius:a": meta("A"), "audius:b": meta("B"), "jamendo:9": meta("J") });
    const tracks = [track(5, "audius:b"), track(3, "audius:a"), track(3 + CHUNK, "jamendo:9"), track(6, "audius:a")];
    await loadMeta(tracks, f);
    expect(asked).toEqual(["/api/meta?ids=audius:a,audius:b", "/api/meta?ids=jamendo:9"]); // sorted, de-duplicated, per bucket
    await loadMeta(tracks, f);
    expect(asked).toHaveLength(2);
  });

  it("keeps nothing from a failed call, so the next screen asks again", async () => {
    await loadMeta([track(1, "audius:a")], api({}, false).f);
    const up = api({ "audius:a": meta("A") });
    await loadMeta([track(1, "audius:a")], up.f);
    expect(up.asked).toHaveLength(1);
  });
});

describe("nameRefs and want", () => {
  it("names pointers once a screen wants them, drops what the platform no longer streams, and never changes the chain's catalog", async () => {
    const cat = catalogOf([track(1, "audius:a"), track(2, "audius:gone"), track(3, "jamendo:off"), track(4, "ipfs://bafy", "Own song")]);
    const before = nameRefs(cat);
    expect(before.byId.get(1)).toMatchObject({ title: "Audius track", artistName: "Audius artist" }); // not fetched yet
    expect(before.artists.get(7)?.name).toBe("Audius artist");
    const { f, asked } = api({ "audius:a": meta("Midnight Drive"), "audius:gone": null, "jamendo:off": meta("Off", "X", false) });
    await want([{ id: 1 }], f);
    expect(asked).toEqual(["/api/meta?ids=audius:a,audius:gone,jamendo:off"]); // the whole bucket, one URL
    const out = nameRefs(cat);
    expect(out.tracks.map((t) => t.id)).toEqual([1, 4]);
    expect(out.byId.get(1)).toMatchObject({ title: "Midnight Drive", artistName: "Night Tapes", cover: "https://creatornode.audius.co/a.jpg", source: "https://audius.co/nt/x" });
    expect(out.artists.get(7)?.name).toBe("Night Tapes");
    expect(cat.byId.get(1)?.title).toBe(""); // the stored catalog keeps the chain's records only
    await want([{ id: 1 }, { id: 4 }], f);
    expect(asked).toHaveLength(1); // nothing new to ask
  });

  it("leaves a catalog without pointers as it is", () => {
    const cat = catalogOf([track(4, "ipfs://bafy", "Own song")]);
    expect(nameRefs(cat)).toBe(cat);
  });
});
