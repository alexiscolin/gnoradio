// @vitest-environment node
import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";
import meta from "./functions/meta.mjs";
import { metaOf, parseIDs } from "./refs";

const AUDIUS = { data: [{ id: "Ab1", title: "Midnight Drive", permalink: "/nt/midnight-drive", is_streamable: true, artwork: { "480x480": "https://creatornode.audius.co/a.jpg" }, user: { id: "u1", name: "Night Tapes" } },
  { id: "Off", title: "Gone", is_streamable: false, user: { name: "X" } }] };
const JAMENDO = { results: [{ id: "42", name: "Sunrise", artist_name: "Lobo", artist_id: "7", album_image: "https://usercontent.jamendo.com/a.jpg", shareurl: "https://www.jamendo.com/track/42", audio: "https://prod-1.storage.jamendo.com/?trackid=42&format=mp32" },
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
    expect(net.mock.calls.find(([u]) => u.includes("jamendo"))?.[0]).toBe("https://api.jamendo.com/v3.0/tracks/?client_id=cid&format=json&limit=100&audioformat=mp32&id=42+66");
    expect(m["audius:Ab1"]).toEqual({ title: "Midnight Drive", artist: "Night Tapes", artistId: "u1", artwork: "https://creatornode.audius.co/a.jpg", permalink: "https://audius.co/nt/midnight-drive", streamable: true });
    expect(m["audius:Off"]?.streamable).toBe(false);
    expect(m["audius:Nope"]).toBeNull();
    expect(m["jamendo:42"]).toMatchObject({ title: "Sunrise", artist: "Lobo", artwork: "https://usercontent.jamendo.com/a.jpg", streamable: true });
    expect(m["jamendo:66"]?.streamable).toBe(false); // an audio URL off jamendo.com is never followed
  });

  it("reads no Jamendo without a client id", async () => {
    vi.stubEnv("JAMENDO_CLIENT_ID", "");
    expect((await metaOf(["jamendo:42"]))["jamendo:42"]).toBeNull();
    expect(net).not.toHaveBeenCalled();
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
