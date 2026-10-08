import { renderHook } from "@testing-library/react";
import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";
import { CHUNK, clearRefs, isRef, loadMeta, nameRefs, type RefMeta, useWant, want } from "./refs";
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

/** api answers /api/meta?bucket=N with its table (the pointers the chain holds) and records every URL asked. */
function api(table: Record<string, RefMeta | null>, ok = true, body?: string) {
  const asked: string[] = [];
  const f = vi.fn((url: string) => {
    asked.push(url);
    return Promise.resolve(new Response(body ?? JSON.stringify(table), { status: ok ? 200 : 502 }));
  });
  return { f: f as unknown as typeof fetch, asked };
}

beforeEach(clearRefs);
afterEach(() => { vi.useRealTimers(); });

describe("isRef", () => {
  it("is a pointer by its audio, whether or not a claimed artist named it", () => {
    expect(isRef(track(1, "audius:Ab1"))).toBe(true);
    expect(isRef(track(1, "jamendo:42"))).toBe(true);
    expect(isRef(track(1, "audius:Ab1", "Named by its artist"))).toBe(true);
    expect(isRef(track(1, "ipfs://bafy"))).toBe(false);
  });
});

describe("loadMeta", () => {
  it("asks one URL per bucket of on-chain ids (the same for every visitor), and nothing it already holds", async () => {
    const { f, asked } = api({ "audius:a": meta("A"), "audius:b": meta("B"), "jamendo:9": meta("J") });
    const tracks = [track(5, "audius:b"), track(3, "audius:a"), track(3 + CHUNK, "jamendo:9"), track(6, "audius:a")];
    await loadMeta(tracks, f);
    expect(asked).toEqual(["/api/meta?bucket=0", "/api/meta?bucket=1"]); // one per bucket, the same for every visitor
    await loadMeta(tracks, f);
    expect(asked).toHaveLength(2);
  });

  it("keeps nothing from a failed call, so the screen asks again once the pause is over", async () => {
    vi.useFakeTimers();
    await loadMeta([track(1, "audius:a")], api({}, false).f);
    vi.advanceTimersByTime(61_000);
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
    expect(asked).toEqual(["/api/meta?bucket=0"]); // the whole bucket, one URL
    const out = nameRefs(cat);
    expect(out.tracks.map((t) => t.id)).toEqual([1, 4]);
    expect(out.byId.has(2) && out.byId.has(3)).toBe(true); // out of the lists, still known by id: the player does not ask the chain for them
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

describe("a named pointer", () => {
  it("shows the owner's title with the live artwork, link and streamable check", async () => {
    const cat = catalogOf([track(1, "audius:a", "Owner's title"), track(2, "audius:b", "Taken down")]);
    nameRefs(cat);
    await want([{ id: 1 }], api({ "audius:a": meta("Platform title"), "audius:b": null }).f);
    const out = nameRefs(cat);
    expect(out.byId.get(1)).toMatchObject({ title: "Owner's title", cover: "https://creatornode.audius.co/a.jpg", source: "https://audius.co/nt/x" });
    expect(out.tracks.some((t) => t.id === 2)).toBe(false); // not streamable any more: out of the lists
  });
});

describe("failures", () => {
  it("are left alone for a minute, then two, never cached as missing, and asked again by themselves", async () => {
    vi.useFakeTimers();
    nameRefs(catalogOf([track(1, "audius:a")]));
    const bad = api({}, false);
    await want([{ id: 1 }], bad.f);
    expect(bad.asked).toHaveLength(1);
    await want([{ id: 1 }], bad.f);
    vi.advanceTimersByTime(59_000);
    await want([{ id: 1 }], bad.f);
    expect(bad.asked).toHaveLength(1); // still backing off
    await vi.advanceTimersByTimeAsync(2_000); // the pause is over: the screen need not change for it to ask again
    expect(bad.asked).toHaveLength(2);
    await vi.advanceTimersByTimeAsync(119_000);
    expect(bad.asked).toHaveLength(2); // the pause doubled: 2 minutes
    await vi.advanceTimersByTimeAsync(2_000);
    expect(bad.asked).toHaveLength(3);
  });

  it("includes a 200 that is not a JSON object (a deploy without the function), and a platform that left ids out", async () => {
    vi.useFakeTimers();
    nameRefs(catalogOf([track(1, "audius:a"), track(2, "jamendo:9")]));
    const html = api({}, true, "<!doctype html><html></html>");
    await expect(want([{ id: 1 }], html.f)).resolves.toBeUndefined();
    await expect(loadMeta([track(1, "audius:a")], api({}, true, "[]").f)).resolves.toBe(false);
    clearRefs();
    nameRefs(catalogOf([track(1, "audius:a"), track(2, "jamendo:9")]));
    const half = api({ "audius:a": meta("A") }); // Jamendo did not answer: its ref is left out, not null
    await want([{ id: 1 }], half.f);
    expect(nameRefs(catalogOf([track(1, "audius:a"), track(2, "jamendo:9")])).byId.get(1)?.title).toBe("A");
    expect(nameRefs(catalogOf([track(2, "jamendo:9")])).byId.get(2)?.title).toBe("Jamendo track"); // unknown: not dropped
    await want([{ id: 1 }], half.f);
    expect(half.asked).toHaveLength(1); // backing off, as for a failed call
    await vi.advanceTimersByTimeAsync(61_000);
    expect(half.asked).toHaveLength(2);
  });

  it("notify listeners only when answers were cached", async () => {
    nameRefs(catalogOf([track(1, "audius:a")]));
    expect(await loadMeta([track(1, "audius:a")], api({}, false).f)).toBe(false);
    clearRefs();
    nameRefs(catalogOf([track(1, "audius:a")]));
    expect(await loadMeta([track(1, "audius:a")], api({ "audius:a": meta("A") }).f)).toBe(true);
  });
});

describe("claimed pointers and artist links", () => {
  it("keeps a claimed artist's own name on the track, and links a pointer artist to the platform", async () => {
    const claimed = { ...track(1, "audius:a", "Mine"), artistName: "Chosen Name", claimed: true };
    const cat = catalogOf([claimed]);
    nameRefs(cat);
    await want([{ id: 1 }], api({ "audius:a": meta("Platform title", "Platform Name") }).f);
    const out = nameRefs(cat);
    expect(out.byId.get(1)?.artistName).toBe("Chosen Name");
    expect(out.artists.get(7)?.source).toBe("https://audius.co/nt/x");
  });
});

describe("useWant", () => {
  it("does not ask again when a render hands it a new array of the same ids", () => {
    nameRefs(catalogOf([track(1, "audius:a")]));
    const f = vi.fn(() => new Promise<Response>(() => undefined));
    vi.stubGlobal("fetch", f);
    const { rerender } = renderHook(({ ids }) => { useWant(ids.map((id) => ({ id }))); }, { initialProps: { ids: [1] } });
    rerender({ ids: [1] });
    rerender({ ids: [1] });
    expect(f).toHaveBeenCalledTimes(1);
    vi.unstubAllGlobals();
  });
});
