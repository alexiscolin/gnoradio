// @vitest-environment node
import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";
import meta from "./functions/meta.mjs";
import { bucketOf, metaOf, parseBucket } from "./refs";
import { chain } from "./testing";

const AUDIUS = { data: [{ id: "Ab1", title: "Midnight Drive", permalink: "/nt/midnight-drive", is_streamable: true, artwork: { "480x480": "https://creatornode.audius.co/a.jpg" }, user: { id: "u1", name: "Night Tapes" } },
  { id: "Off", title: "Gone", is_streamable: false, user: { name: "X" } }] };
const JAMENDO = { headers: { status: "success" }, results: [{ id: "42", name: "Sunrise", artist_name: "Lobo", artist_id: "7", album_image: "https://usercontent.jamendo.com/a.jpg", shareurl: "https://www.jamendo.com/track/42", audio: "https://prod-1.storage.jamendo.com/?trackid=42&format=mp32" },
  { id: "66", name: "Elsewhere", audio: "https://evil.example/x.mp3" }] };

let net: ReturnType<typeof vi.fn<(url: string, init?: RequestInit) => Promise<Response>>>;
/** The chain: 205 tracks, newest first like TracksJSON; 101-104 are pointers, 150 is hidden. */
const AUDIO: Record<number, string> = { 101: "audius:Ab1", 102: "jamendo:42", 103: "jamendo:66", 104: "audius:Off", 105: "ipfs://bafy", 150: "audius:Hidden", 205: "audius:Nope" };
const HIDDEN = new Set([150]);
const world = (q: string): unknown => {
  const m = /TracksJSON\((\d+), (\d+)\)/.exec(q);
  if (m) {
    const offset = Number(m[1]), limit = Number(m[2]);
    const ids = Array.from({ length: 205 }, (_, k) => 205 - k).slice(offset, offset + limit).filter((id) => !HIDDEN.has(id));
    return { total: 205, tracks: ids.map((id) => ({ id, audio: AUDIO[id] ?? `ipfs://t${String(id)}` })) };
  }
  const t = /TrackJSON\((\d+)\)/.exec(q);
  if (t) return AUDIO[Number(t[1])] && !HIDDEN.has(Number(t[1])) ? { id: Number(t[1]), audio: AUDIO[Number(t[1])] } : undefined;
  return undefined;
};
beforeEach(() => {
  vi.stubEnv("VITE_WALLET_RPC", "https://rpc.test");
  vi.stubEnv("JAMENDO_CLIENT_ID", "cid");
  vi.stubEnv("AUDIUS_API_KEY", "akey");
  net = vi.fn((url: string, init?: RequestInit) => {
    if (url === "https://rpc.test") return chain(world)(url, init);
    if (url.startsWith("https://api.audius.co/v1/tracks?")) return Promise.resolve(Response.json(AUDIUS));
    if (url.startsWith("https://api.jamendo.com/v3.0/tracks/?")) return Promise.resolve(Response.json(JAMENDO));
    return Promise.reject(new Error(`unexpected fetch ${url}`));
  });
  vi.stubGlobal("fetch", net);
});
afterEach(() => { vi.unstubAllGlobals(); vi.unstubAllEnvs(); });

const get = (path: string) => meta(new Request(`https://gnoradio.example${path}`));

describe("parseBucket", () => {
  it("takes one canonical bucket number and no other parameter", () => {
    const q = (s: string) => parseBucket(new URL(`https://x/api/meta${s}`).searchParams);
    expect(q("?bucket=0")).toBe(0);
    expect(q("?bucket=12")).toBe(12);
    for (const bad of ["", "?bucket=", "?bucket=01", "?bucket=-1", "?bucket=1.5", "?bucket=1e3", "?bucket=1234567", "?bucket=1&x=2", "?bucket=1&bucket=2", "?ids=audius:Ab1", "?x=1&bucket=1"]) expect(q(bad)).toBeNull();
  });
});

describe("bucketOf", () => {
  it("reads one page from the chain: the pointers of the bucket's ids, hidden tracks and other buckets left out", async () => {
    expect(await bucketOf("https://rpc.test", 1)).toEqual(["audius:Ab1", "audius:Off", "jamendo:42", "jamendo:66"]);
    expect(await bucketOf("https://rpc.test", 2)).toEqual(["audius:Nope"]); // ids 200-205
    expect(await bucketOf("https://rpc.test", 3)).toEqual([]); // past the last id
    expect(net.mock.calls.every(([u]) => u === "https://rpc.test")).toBe(true); // the chain only
  });
});

describe("metaOf", () => {
  it("asks each platform once for all its ids, on its fixed host only, and keeps only safe URLs", async () => {
    const { meta: m, partial } = await metaOf(["audius:Ab1", "audius:Off", "audius:Nope", "jamendo:42", "jamendo:66"]);
    expect(partial).toBe(false);
    expect(net).toHaveBeenCalledTimes(2);
    const [audiusURL, init] = net.mock.calls.find(([u]) => u.includes("audius")) ?? [];
    expect(audiusURL).toBe("https://api.audius.co/v1/tracks?id=Ab1&id=Off&id=Nope&app_name=GnoRadio");
    expect((init?.headers as Record<string, string>)["x-api-key"]).toBe("akey");
    expect(net.mock.calls.find(([u]) => u.includes("jamendo"))?.[0]).toBe("https://api.jamendo.com/v3.0/tracks/?client_id=cid&format=json&limit=50&audioformat=mp32&id=42+66");
    expect(m["audius:Ab1"]).toEqual({ title: "Midnight Drive", artist: "Night Tapes", artistId: "u1", artwork: "https://creatornode.audius.co/a.jpg", permalink: "https://audius.co/nt/midnight-drive", streamable: true }); // no stream for Audius
    expect(m["audius:Off"]?.streamable).toBe(false);
    expect(m["audius:Nope"]).toBeNull();
    expect(m["jamendo:42"]).toMatchObject({ title: "Sunrise", artist: "Lobo", artwork: "https://usercontent.jamendo.com/a.jpg", streamable: true, stream: "https://prod-1.storage.jamendo.com/?trackid=42&format=mp32" });
    expect(m["jamendo:66"]?.streamable).toBe(false); // an audio URL off jamendo.com is never followed
  });

  it("answers the platform that works and leaves the failed one's refs out (unknown, never null)", async () => {
    vi.stubEnv("JAMENDO_CLIENT_ID", "");
    const { meta, partial } = await metaOf(["audius:Ab1", "jamendo:42"]);
    expect(partial).toBe(true);
    expect(meta["audius:Ab1"]?.title).toBe("Midnight Drive");
    expect("jamendo:42" in meta).toBe(false);
    net.mockImplementation((url: string) => Promise.resolve(url.includes("jamendo") ? Response.json({ headers: { status: "failed" }, results: [] }) : Response.json(AUDIUS)));
    vi.stubEnv("JAMENDO_CLIENT_ID", "cid");
    expect("jamendo:42" in (await metaOf(["audius:Ab1", "jamendo:42"])).meta).toBe(false);
  });

  it("fails only when every platform asked failed", async () => {
    vi.stubEnv("JAMENDO_CLIENT_ID", "");
    await expect(metaOf(["jamendo:42"])).rejects.toThrow();
    expect(net).not.toHaveBeenCalled();
    net.mockResolvedValueOnce(Response.json({ error: "x" }));
    await expect(metaOf(["audius:Ab1"])).rejects.toThrow();
  });

  it("drops one malformed artwork URL without failing the batch", async () => {
    net.mockResolvedValueOnce(Response.json({ data: [{ id: "Ab1", title: "A", artwork: { "480x480": "https://[bad" } }, { id: "Cd2", title: "B" }] }));
    const { meta: m } = await metaOf(["audius:Ab1", "audius:Cd2"]);
    expect(m["audius:Ab1"]).toMatchObject({ title: "A", artwork: "" });
    expect(m["audius:Cd2"]?.title).toBe("B");
  });
});

const platformCalls = () => net.mock.calls.filter(([u]) => u !== "https://rpc.test").length;

describe("/api/meta", () => {
  it("is bounded by the chain: the pointers of the bucket only, three hours of cache, one key per bucket", async () => {
    const ok = await get("/api/meta?bucket=1");
    expect(ok.status).toBe(200);
    expect(ok.headers.get("netlify-cdn-cache-control")).toBe("public, durable, s-maxage=10800, stale-while-revalidate=300");
    expect(ok.headers.get("netlify-vary")).toBe("query=bucket");
    expect(ok.headers.get("cache-control")).toBe("public, max-age=300");
    const body = (await ok.json()) as Record<string, { title: string } | null>;
    expect(Object.keys(body).sort()).toEqual(["audius:Ab1", "audius:Off", "jamendo:42", "jamendo:66"]);
    expect(body["audius:Ab1"]?.title).toBe("Midnight Drive");
    expect(net.mock.calls.find(([u]) => u.includes("api.audius.co"))?.[0]).not.toContain("Hidden");
  });

  it("calls no platform for a bucket without pointers, and refuses any other parameter, uncached", async () => {
    expect((await (await get("/api/meta?bucket=3")).json())).toEqual({});
    expect(platformCalls()).toBe(0);
    for (const bad of ["/api/meta", "/api/meta?ids=audius:Ab1", "/api/meta?bucket=1&x=1", "/api/meta?bucket=01", "/api/meta?bucket=abc"]) {
      const r = await get(bad);
      expect(r.status).toBe(400);
      expect(r.headers.get("cache-control")).toBe("no-store");
    }
    expect(platformCalls()).toBe(0);
  });

  it("answers a partial result with a minute of cache at most, and a total failure with a short 502", async () => {
    vi.stubEnv("JAMENDO_CLIENT_ID", "");
    const part = await get("/api/meta?bucket=1");
    expect(part.status).toBe(200);
    expect(part.headers.get("cache-control")).toBe("no-store");
    expect(part.headers.get("netlify-cdn-cache-control")).toBe("public, s-maxage=60");
    expect(Object.keys((await part.json()) as object).sort()).toEqual(["audius:Ab1", "audius:Off"]);
    net.mockImplementation((url: string, init?: RequestInit) => (url === "https://rpc.test" ? chain(world)(url, init) : Promise.resolve(new Response("", { status: 500 }))));
    const down = await get("/api/meta?bucket=1");
    expect(down.status).toBe(502);
    expect(down.headers.get("cache-control")).toBe("no-store");
    net.mockImplementation(() => Promise.reject(new Error("rpc down")));
    expect((await get("/api/meta?bucket=1")).status).toBe(502); // the chain unreachable
  });
});

describe("jamendo limits", () => {
  it("asks Jamendo 50 ids a call (it refuses more), and a 'failed' answer is an error, not unknown tracks", async () => {
    await metaOf(Array.from({ length: 60 }, (_, i) => `jamendo:${String(i + 1)}`));
    const calls = net.mock.calls.map(([u]) => u).filter((u) => u.startsWith("https://api.jamendo.com/"));
    expect(calls).toHaveLength(2);
    expect(calls.map((u) => new URL(u).searchParams.get("id")?.split(/[+ ]/).length)).toEqual([50, 10]);
    net.mockImplementation(() => Promise.resolve(Response.json({ headers: { status: "failed" }, results: [] })));
    await expect(metaOf(["jamendo:1"])).rejects.toThrow();
  });
});
