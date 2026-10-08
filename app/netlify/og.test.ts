// @vitest-environment node
import { readFileSync } from "node:fs";
import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";
import og, { composition, cover, dims, render } from "./functions/og.mjs";
import { REALMS } from "../src/lib/realms";
import { WALLET, chain } from "./testing";

const PNG = readFileSync(new URL("../public/og.png", import.meta.url));
const TRACK = { id: 12, title: "Night Drive", artistName: "Ana", cover: "ipfs://bafycover", audio: "ipfs://bafy" };
const WORLD: Record<string, unknown> = {
  [`${REALMS.catalog}.TrackJSON(12)`]: TRACK,
  [`${REALMS.catalog}.TrackJSON(13)`]: { ...TRACK, id: 13, cover: "" },
  [`${REALMS.catalog}.TrackJSON(14)`]: { ...TRACK, id: 14, cover: "", audio: "audius:Ab1" },
  [`${REALMS.catalog}.ArtistJSON(3)`]: { name: "Ana", bio: "", tracks: [12] },
  [`${REALMS.catalog}.AlbumJSON(2)`]: { title: "Roads", cover: "", tracks: [13] },
  [`${REALMS.catalog}.PlaylistJSON(5)`]: { title: "Late", tracks: [] },
  [`${REALMS.radio}.StationsJSON()`]: { stations: [{ id: 3, name: "Ambient", now: { track: 13 } }] },
  [`${REALMS.radio}.CuratorJSON(`]: { picks: 1 },
  [`${REALMS.tickets}.func() string { e, ok := EventInfo(4)`]: { id: 4, artistName: "Ana", title: "Release Party", venue: "La Station", start: 1795208400, cancelled: false },
};
const rpc = chain((q) => Object.entries(WORLD).find(([k]) => q.startsWith(k))?.[1]);

let net: ReturnType<typeof vi.fn<(url: string, init?: RequestInit) => Promise<Response>>>;
beforeEach(() => {
  vi.stubEnv("VITE_WALLET_RPC", "https://rpc.test");
  net = vi.fn((url: string, init?: RequestInit) => {
    if (url === "https://rpc.test") return rpc(url, init);
    if (url === "https://ipfs.io/ipfs/bafycover") return Promise.resolve(new Response(PNG));
    if (url.startsWith("https://api.audius.co/v1/tracks/Ab1")) return Promise.resolve(Response.json({ data: { artwork: { "480x480": "https://node.example.com/content/Qm/480x480.jpg" } } }));
    if (url === "https://node.example.com/content/Qm/480x480.jpg") return Promise.resolve(new Response(PNG));
    return Promise.reject(new Error(`unexpected fetch ${url}`));
  });
  vi.stubGlobal("fetch", net);
});
afterEach(() => {
  vi.unstubAllGlobals();
  vi.unstubAllEnvs();
});

let ip = 0;
const get = (path: string, from = `198.51.100.${String(++ip % 250)}`) => og(new Request(`https://radio.example${path}`, { headers: { "x-nf-client-connection-ip": from } }));
/** drawn asks for path's image as a preview bot does: the canonical URL it is sent to, then the image. */
const drawn = async (path: string) => {
  const r = await get(path);
  expect(r.status, path).toBe(302);
  const to = r.headers.get("location") ?? "";
  expect(to, path).toMatch(/^https:\/\/radio\.example\/og\/[a-z]+\/[\w-]+\.png\?v=[0-9a-z]+$/);
  return get(to.slice("https://radio.example".length));
};
const size = (b: Uint8Array) => {
  const v = new DataView(b.buffer, b.byteOffset);
  return [v.getUint32(16), v.getUint32(20)];
};

describe("og image", () => {
  it("draws a 1200×630 PNG for every page kind, cached an hour", async () => {
    for (const path of ["/og/track/12.png", "/og/track/13.png", "/og/track/14.png", "/og/artist/3.png", "/og/album/2.png", "/og/playlist/5.png", "/og/live/3.png", `/og/listener/${WALLET}.png`, "/og/concerts/4.png"]) {
      const r = await drawn(path);
      expect(r.status, path).toBe(200);
      expect(r.headers.get("content-type")).toBe("image/png");
      expect(r.headers.get("cache-control")).toBe("public, max-age=3600");
      expect(r.headers.get("netlify-cdn-cache-control")).toBe("public, s-maxage=3600, stale-while-revalidate=86400");
      const png = new Uint8Array(await r.arrayBuffer());
      expect(String.fromCharCode(...png.subarray(1, 4)), path).toBe("PNG");
      expect(size(png), path).toEqual([1200, 630]);
    }
  }, 30_000);

  it("falls back to /og.png on bad paths, unknown ids and RPC failures", async () => {
    for (const path of ["/og/track/99.png", "/og/track/x.png", "/og/nope/1.png", "/og/listener/g1bad.png", "/og/../etc/passwd", "/og/track/12.jpg"]) {
      const r = await get(path);
      expect(r.status, path).toBe(302);
      expect(r.headers.get("location")).toBe("https://radio.example/og.png");
    }
    net.mockRejectedValue(new Error("down"));
    expect((await get("/og/track/12.png")).headers.get("location")).toBe("https://radio.example/og.png");
  });

  it("reads an id with leading zeros as its plain number (never octal), sent to its canonical URL", async () => {
    const to = (await get("/og/track/012.png")).headers.get("location") ?? "";
    expect(to).toMatch(/^https:\/\/radio\.example\/og\/track\/12\.png\?v=[0-9a-z]+$/);
    const bodies = net.mock.calls.map(([, init]) => (typeof init?.body === "string" ? atob((JSON.parse(init.body) as { params: { data: string } }).params.data) : ""));
    expect(bodies).toContain(`${REALMS.catalog}.TrackJSON(12)`);
    expect(bodies.some((b) => b.includes("(012)"))).toBe(false);
    expect((await get("/og/concerts/04.png")).headers.get("location")).toMatch(/\/og\/concerts\/4\.png\?v=/);
  });

  it("draws only the canonical URL: another slug or ?v is sent there undrawn", async () => {
    const to = (await get("/og/track/12.png?v=abc")).headers.get("location") ?? "";
    expect(to).toMatch(/\/og\/track\/12\.png\?v=(?!abc)[0-9a-z]+$/);
    expect((await get("/og/track/night-drive-12.png")).headers.get("location")).toBe(to);
    expect((await get(`${to.slice("https://radio.example".length)}&x=1`)).status).toBe(302);
    expect(net.mock.calls.some(([u]) => u.startsWith("https://ipfs.io"))).toBe(false); // no cover fetched, nothing drawn
  });

  it("limits the images drawn for one client IP", async () => {
    for (let i = 0; i < 30; i++) expect((await get("/og/track/99.png", "203.0.113.9")).headers.get("cache-control")).toBe("public, max-age=300");
    const r = await get("/og/track/12.png", "203.0.113.9");
    expect(r.headers.get("location")).toBe("https://radio.example/og.png");
    expect(r.headers.get("cache-control")).toBe("no-store");
  });

  it("keeps the image briefly when the real cover did not come", async () => {
    net.mockImplementation((url: string, init?: RequestInit) => (url === "https://rpc.test" ? rpc(url, init) : Promise.reject(new Error("timeout"))));
    const r = await drawn("/og/track/12.png");
    expect(r.status).toBe(200);
    expect(r.headers.get("cache-control")).toBe("public, max-age=600");
    expect(r.headers.get("netlify-cdn-cache-control")).toBeNull();
  });
});

describe("cover", () => {
  it("fetches covers from the media hosts only", async () => {
    expect(await cover("ipfs://bafycover")).toMatch(/^data:image\/png;base64,/);
    expect(await cover("https://evil.example/x.png")).toBe("");
    expect(await cover("https://169.254.169.254/latest")).toBe("");
    expect(await cover("javascript:alert(1)")).toBe("");
    expect(net).toHaveBeenCalledTimes(1);
  });

  it("follows redirects only to allowed hosts", async () => {
    net.mockResolvedValueOnce(new Response(null, { status: 302, headers: { location: "https://127.0.0.1/internal" } }));
    expect(await cover("https://archive.org/download/x/cover.jpg")).toBe("");
    expect(net).toHaveBeenCalledTimes(1);
  });

  it("refuses what is not an image", async () => {
    net.mockResolvedValueOnce(new Response("<svg onload=alert(1)>"));
    expect(await cover("https://archive.org/download/x/cover.svg")).toBe("");
  });

  it("refuses an image too large to decode safely, by its header", async () => {
    const huge = Uint8Array.from(PNG);
    new DataView(huge.buffer).setUint32(16, 16000);
    new DataView(huge.buffer).setUint32(20, 16000);
    net.mockResolvedValueOnce(new Response(huge));
    expect(await cover("https://archive.org/download/x/bomb.png")).toBe("");
    // A body with no length is read only up to the cap.
    const endless = new ReadableStream<Uint8Array>({ pull: (c) => { c.enqueue(new Uint8Array(1 << 20)); } });
    net.mockResolvedValueOnce(new Response(endless));
    expect(await cover("https://archive.org/download/x/endless.png")).toBe("");
  });

  it("reads image sizes from PNG, JPEG, GIF and WebP headers", () => {
    expect(dims(PNG)).toEqual([1200, 630]);
    const jpeg = Uint8Array.from([0xff, 0xd8, 0xff, 0xe0, 0, 4, 0, 0, 0xff, 0xc0, 0, 11, 8, 0x3e, 0x80, 0x1f, 0x40, 3, 0, 0, 0]);
    expect(dims(jpeg)).toEqual([8000, 16000]);
    const ascii = (s: string) => new TextEncoder().encode(s);
    expect(dims(Uint8Array.from([...ascii("GIF89a"), 0x10, 0, 0x20, 0]))).toEqual([16, 32]);
    const webp = new Uint8Array(30);
    webp.set(ascii("RIFF\0\0\0\0WEBPVP8X"));
    webp.set([0x9f, 0x0f, 0, 0x9f, 0x0f, 0], 24);
    expect(dims(webp)).toEqual([4000, 4000]);
    expect(dims(new TextEncoder().encode("<svg/>"))).toBeNull();
  });

  it("never fetches a pointer's artwork from Audius: the generated cover stands", async () => {
    expect(await cover("audius:Ab1")).toBe("");
    expect(net.mock.calls.some(([u]) => u.includes("audius.co"))).toBe(false);
  });
});

describe("drawing", () => {
  it("draws the generated cover with Cover.tsx's six compositions", () => {
    const seen = new Set(Array.from({ length: 40 }, (_, i) => composition(`${String(i)}x`)));
    expect(seen.size).toBe(6);
  });

  it("escapes hostile names and fits long ones", async () => {
    const hostile = `"><script>alert(1)</script>&${"Very long title ".repeat(12)}`;
    const { png } = await render({ path: "/track/1", kicker: "Listen", title: hostile, by: "<b>", art: "", seed: "1", page: "", description: "", alt: "" });
    expect(size(png)).toEqual([1200, 630]);
  });
});

describe("composition", () => {
  it("draws each generated cover in the colours styles.css gives it (.cover.v0…v5)", async () => {
    const { fnv } = await import("../src/lib/format");
    const css = readFileSync(new URL("../src/styles.css", import.meta.url), "utf8");
    const token = (name: string) => new RegExp(`--${name}: (#[0-9a-f]{6})`).exec(css)?.[1];
    for (let v = 0; v < 6; v++) {
      let seed = "";
      for (let i = 0; fnv(seed) % 6 !== v; i++) seed = `s${String(i)}`;
      const vars = [...css.matchAll(new RegExp(`\\.cover\\.v${String(v)}(?: [ib])? \\{[^}]*background: var\\(--(\\w+)\\)`, "g"))].map((m) => token(m[1] ?? ""));
      const fills = [...composition(seed).matchAll(/fill="(#[0-9a-f]{6})"/g)].map((m) => m[1]);
      expect(fills, `v${String(v)}`).toEqual(vars);
    }
  });
});
