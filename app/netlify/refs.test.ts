// @vitest-environment node
import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";
import meta from "./functions/meta.mjs";
import { metaOf, parseIDs } from "./refs";

const AUDIUS = { data: [{ id: "Ab1", title: "Midnight Drive", permalink: "/nt/midnight-drive", is_streamable: true, artwork: { "480x480": "https://creatornode.audius.co/a.jpg" }, user: { id: "u1", name: "Night Tapes" } },
  { id: "Off", title: "Gone", is_streamable: false, user: { name: "X" } }] };
const JAMENDO = { headers: { status: "success" }, results: [{ id: "42", name: "Sunrise", artist_name: "Lobo", artist_id: "7", album_image: "https://usercontent.jamendo.com/a.jpg", shareurl: "https://www.jamendo.com/track/42", audio: "https://prod-1.storage.jamendo.com/?trackid=42&format=mp32" },
  { id: "66", name: "Elsewhere", audio: "https://evil.example/x.mp3" }] };

let net: ReturnType<typeof vi.fn<(url: string, init?: RequestInit) => Promise<Response>>>;
beforeEach(() => {
  vi.stubEnv("JAMENDO_CLIENT_ID", "cid");
  vi.stubEnv("AUDIUS_API_KEY", "akey");
  net = vi.fn((url: string) => {
    if (url.startsWith("https://api.audius.co/v1/tracks?")) return Promise.resolve(Response.json(AUDIUS));
    if (url.startsWith("https://api.jamendo.com/v3.0/tracks/?")) return Promise.resolve(Response.json(JAMENDO));
    return Promise.reject(new Error(`unexpected fetch ${url}`));
  });
  vi.stubGlobal("fetch", net);
});
afterEach(() => { vi.unstubAllGlobals(); vi.unstubAllEnvs(); });

const get = (path: string) => meta(new Request(`https://gnoradio.example${path}`));

describe("parseIDs", () => {
  it("takes 1 to 100 valid pointers, de-duplicated, and refuses anything else", () => {
    expect(parseIDs("audius:Ab1,jamendo:42,audius:Ab1")).toEqual(["audius:Ab1", "jamendo:42"]);
    for (const bad of [null, "", "ipfs:x", "audius:a/b", "audius:" + "a".repeat(33), Array.from({ length: 101 }, (_, i) => `jamendo:${String(i)}`).join(",")]) {
      expect(parseIDs(bad)).toBeNull();
    }
  });
});

describe("metaOf", () => {
  it("asks each platform once for all its ids, on its fixed host only, and keeps only safe URLs", async () => {
    const m = await metaOf(["audius:Ab1", "audius:Off", "audius:Nope", "jamendo:42", "jamendo:66"]);
    expect(net).toHaveBeenCalledTimes(2);
    const [audiusURL, init] = net.mock.calls.find(([u]) => u.includes("audius")) ?? [];
    expect(audiusURL).toBe("https://api.audius.co/v1/tracks?id=Ab1&id=Off&id=Nope&app_name=GnoRadio");
    expect((init?.headers as Record<string, string>)["x-api-key"]).toBe("akey");
    expect(net.mock.calls.find(([u]) => u.includes("jamendo"))?.[0]).toBe("https://api.jamendo.com/v3.0/tracks/?client_id=cid&format=json&limit=50&audioformat=mp32&id=42+66");
    expect(m["audius:Ab1"]).toEqual({ title: "Midnight Drive", artist: "Night Tapes", artistId: "u1", artwork: "https://creatornode.audius.co/a.jpg", permalink: "https://audius.co/nt/midnight-drive", streamable: true });
    expect(m["audius:Off"]?.streamable).toBe(false);
    expect(m["audius:Nope"]).toBeNull();
    expect(m["jamendo:42"]).toMatchObject({ title: "Sunrise", artist: "Lobo", artwork: "https://usercontent.jamendo.com/a.jpg", streamable: true });
    expect(m["jamendo:66"]?.streamable).toBe(false); // an audio URL off jamendo.com is never followed
  });

  it("fails, rather than answering null, when Jamendo has no client id or Audius answers badly", async () => {
    vi.stubEnv("JAMENDO_CLIENT_ID", "");
    await expect(metaOf(["jamendo:42"])).rejects.toThrow(/JAMENDO_CLIENT_ID/);
    expect(net).not.toHaveBeenCalled();
    net.mockResolvedValueOnce(Response.json({ error: "x" }));
    await expect(metaOf(["audius:Ab1"])).rejects.toThrow(/audius/);
  });

  it("drops one malformed artwork URL without failing the batch", async () => {
    net.mockResolvedValueOnce(Response.json({ data: [{ id: "Ab1", title: "A", artwork: { "480x480": "https://[bad" } }, { id: "Cd2", title: "B" }] }));
    const m = await metaOf(["audius:Ab1", "audius:Cd2"]);
    expect(m["audius:Ab1"]).toMatchObject({ title: "A", artwork: "" });
    expect(m["audius:Cd2"]?.title).toBe("B");
  });
});

describe("/api/meta and /api/jamendo", () => {
  it("answers with a 6-hour CDN cache, and refuses malformed ids uncached", async () => {
    const ok = await get("/api/meta?ids=audius:Ab1");
    expect(ok.status).toBe(200);
    expect(ok.headers.get("netlify-cdn-cache-control")).toBe("public, durable, s-maxage=21600, stale-while-revalidate=86400");
    expect(((await ok.json()) as Record<string, { title: string }>)["audius:Ab1"]?.title).toBe("Midnight Drive");
    const bad = await get("/api/meta?ids=https://evil.example");
    expect(bad.status).toBe(400);
    expect(bad.headers.get("cache-control")).toBe("no-store");
  });

  it("redirects a Jamendo stream to jamendo.com only, cached; an upstream failure is a 502 never cached", async () => {
    const r = await get("/api/jamendo/42");
    expect(r.status).toBe(302);
    expect(r.headers.get("location")).toBe("https://prod-1.storage.jamendo.com/?trackid=42&format=mp32");
    expect(r.headers.get("netlify-cdn-cache-control")).toContain("s-maxage=2592000");
    expect((await get("/api/jamendo/66")).status).toBe(404);
    net.mockImplementation(() => Promise.resolve(new Response("", { status: 500 })));
    const down = await get("/api/meta?ids=audius:Ab1");
    expect(down.status).toBe(502);
    expect(down.headers.get("cache-control")).toBe("no-store");
  });
});

describe("a missing Jamendo key", () => {
  it("is an uncached 502 on both endpoints, never a cached 404 or null", async () => {
    vi.stubEnv("JAMENDO_CLIENT_ID", "");
    for (const path of ["/api/jamendo/42", "/api/meta?ids=jamendo:42"]) {
      const r = await get(path);
      expect(r.status).toBe(502);
      expect(r.headers.get("cache-control")).toBe("no-store");
    }
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
