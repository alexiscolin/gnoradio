// @vitest-environment node
import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";
import meta from "./edge-functions/meta";
import { nickname } from "../src/lib/nickname";
import { REALMS, runtimeEnv } from "../src/lib/realms";
import { WALLET, chain } from "./testing";
import { FEATURES_META } from "../src/lib/seo";

const HTML = `<html><head><title>GnoRadio</title>
<meta name="description" content="Community radio" />
<meta property="og:title" content="GnoRadio" />
<meta property="og:description" content="Community radio" />
<meta property="og:url" content="https://radio.example/" />
<meta property="og:image" content="https://radio.example/og.png" />
<meta property="og:image:alt" content="GnoRadio" />
<meta name="twitter:title" content="GnoRadio" />
<meta name="twitter:image" content="https://radio.example/og.png" />
<meta name="twitter:image:alt" content="GnoRadio" />
</head></html>`;

const BOT = "WhatsApp/2.23";
const TRACK = { id: 12, title: "Night Drive", artistName: "Ana", cover: "", audio: "ipfs://bafy" };
/** WORLD answers the reads by the start of their expression ("realm.Fn("). */
const WORLD: Record<string, unknown> = {
  [`${REALMS.catalog}.TrackJSON(`]: TRACK,
  [`${REALMS.catalog}.ArtistJSON(3)`]: { name: "Ana", bio: "", tracks: [7, 12], verified: true, proofHost: "ana.example" },
  [`${REALMS.catalog}.ArtistJSON(6)`]: { name: "Daft Punk", bio: "The real one, tip me", tracks: [], verified: false },
  [`${REALMS.catalog}.AlbumJSON(2)`]: { title: "Roads", cover: "", tracks: [12] },
  [`${REALMS.catalog}.PlaylistJSON(5)`]: { title: "Late", tracks: [12, 7] },
  [`${REALMS.radio}.StationsJSON()`]: { stations: [{ id: 0, name: "Main", now: { track: 12 } }, { id: 3, name: "Ambient", now: { track: 0 } }] },
  [`${REALMS.radio}.CuratorJSON(`]: { picks: 7 },
  "gno.land/r/sys/users.": "",
  [`${REALMS.tickets}.func() string { e, ok := EventInfo(4)`]: { id: 4, artistName: "Ana", title: "Release Party", venue: "La Station, Paris", start: 1795208400, cancelled: false },
  [`${REALMS.tickets}.func() string { t, ok := TicketInfo(9)`]: { id: 4, artistName: "Ana", title: "Release Party", venue: "La Station, Paris", start: 1795208400, cancelled: true },
};
const world = (q: string) => Object.entries(WORLD).find(([k]) => q.startsWith(k))?.[1];

let rpc: ReturnType<typeof vi.fn<(url: string, init?: RequestInit) => Promise<Response>>>;
let page: Response;
const run = (path: string, ua = BOT) => {
  page = new Response(HTML, { headers: { "content-type": "text/html", "content-length": "999", etag: "x" } });
  return meta(new Request(`https://radio.example${path}`, { headers: { "user-agent": ua } }), { next: () => Promise.resolve(page) });
};
const tags = async (path: string) => {
  const html = await (await run(path)).text();
  const tag = (n: string) => new RegExp(`(?:name|property)="${n}" content="([^"]*)"`).exec(html)?.[1];
  return { html, title: /<title>([^<]*)</.exec(html)?.[1], og: tag("og:title"), desc: tag("og:description"), image: tag("og:image"), alt: tag("og:image:alt"), x: tag("twitter:image") };
};

beforeEach(() => {
  rpc = vi.fn(chain(world));
  vi.stubGlobal("fetch", rpc);
  vi.stubGlobal("Netlify", { env: { get: () => "https://rpc.test" } });
});
afterEach(() => {
  vi.unstubAllGlobals();
});

describe("meta", () => {
  it("leaves the page untouched for people", async () => {
    expect(await run("/track/12", "Mozilla/5.0 (Macintosh) Firefox/130.0")).toBe(page);
    expect(await run("/live/3", "Mozilla/5.0 (iPhone) Safari/604.1")).toBe(page);
    expect(rpc).not.toHaveBeenCalled();
  });

  it("writes a track into the tags, with its own image", async () => {
    const r = await run("/track/night-drive-12");
    const t = await tags("/track/night-drive-12");
    expect(t.title).toBe("Night Drive · Ana · GnoRadio");
    expect(t.og).toBe("Night Drive · Ana · GnoRadio");
    expect(t.desc).toMatch(/^Listen to Night Drive by Ana on GnoRadio/);
    expect(t.image).toMatch(/^https:\/\/radio\.example\/og\/track\/12\.png\?v=[0-9a-z]+$/);
    expect(t.x).toBe(t.image);
    expect(t.alt).toBe("Cover of Night Drive by Ana, on GnoRadio");
    expect(t.html).toContain('og:url" content="https://radio.example/track/night-drive-12"');
    expect(r.headers.get("content-length")).toBeNull();
    expect(r.headers.get("etag")).toBeNull();
    expect(rpc.mock.calls[0]?.[0]).toBe("https://rpc.test");
  });

  it("writes the features page's tags without reading the chain", async () => {
    const t = await tags("/features");
    expect(t.title).toBe(FEATURES_META.title);
    expect(t.desc).toBe(FEATURES_META.description);
    expect(t.image).toMatch(/^https:\/\/radio\.example\/og\/features\.png\?v=[0-9a-z]+$/);
    expect(rpc).not.toHaveBeenCalled();
  });

  it("covers every page kind", async () => {
    const cases: [string, string, RegExp, string][] = [
      ["/artist/ana-3", "Ana · GnoRadio", /^Verified via ana\.example\. Listen to Ana on GnoRadio/, "/og/artist/3.png"],
      ["/album/roads-2", "Roads · Ana · GnoRadio", /^Listen to Roads by Ana/, "/og/album/2.png"],
      ["/playlist/late-5", "Late · GnoRadio", /^Listen to Late on GnoRadio/, "/og/playlist/5.png"],
      ["/live", "On air now on Main: Night Drive · Ana", /^Tune in to Main/, "/og/live/0.png"],
      ["/live/ambient-3", "Ambient live · GnoRadio", /^Tune in to Ambient/, "/og/live/3.png"],
      [`/listener/ana-${WALLET}`, `${nickname(WALLET)} · GnoRadio`, /7 picks on air/, `/og/listener/${WALLET}.png`],
      ["/concerts/4", "Release Party · Ana · GnoRadio", /^Ana live at La Station, Paris, 20 Nov 2026\. Tickets/, "/og/concerts/4.png"],
      [`/door/9-${WALLET}`, "Release Party · Ana · GnoRadio", /\(cancelled\)/, "/og/concerts/4.png"],
    ];
    for (const [path, title, desc, image] of cases) {
      const t = await tags(path);
      expect(t.title, path).toBe(title);
      expect(t.desc, path).toMatch(desc);
      expect(t.image, path).toMatch(new RegExp(`^https://radio\\.example${image.replaceAll(".", "\\.")}\\?v=`));
    }
  });

  it("says an unverified profile is one, without its own bio or a tip line", async () => {
    const t = await tags("/artist/daft-punk-6");
    expect(t.desc).toMatch(/^Unverified profile: anyone can register a name/);
    expect(t.html).not.toContain("tip me");
    expect(t.html).not.toMatch(/Tips go straight/);
  });

  it("changes the image URL when what it shows changes", async () => {
    const before = (await tags("/live")).image;
    WORLD[`${REALMS.radio}.StationsJSON()`] = { stations: [{ id: 0, name: "Main", now: { track: 7 } }] };
    WORLD[`${REALMS.catalog}.TrackJSON(`] = { ...TRACK, id: 7, title: "Dawn" };
    try {
      expect((await tags("/live")).image).not.toBe(before);
    } finally {
      WORLD[`${REALMS.catalog}.TrackJSON(`] = TRACK;
    }
  });

  it("escapes hostile names and keeps $-patterns as text", async () => {
    WORLD[`${REALMS.catalog}.ArtistJSON(3)`] = { name: `"><script>alert(1)</script> $& $1 $\``, bio: "a & b <i>", tracks: [], verified: true, proofHost: "ana.example" };
    const t = await tags("/artist/3");
    expect(t.html).not.toContain("<script>");
    expect(t.title).toBe("&#34;&#62;&#60;script&#62;alert(1)&#60;/script&#62; $&#38; $1 $` · GnoRadio");
    expect(t.html).toContain('<meta name="description" content="Verified via ana.example. a &#38; b &#60;i&#62;"');
    expect(t.alt).toBe("&#34;&#62;&#60;script&#62;alert(1)&#60;/script&#62; $&#38; $1 $` on GnoRadio, with the cover of their latest track");
  });

  it("keeps the artist's and album's cards when their track is hidden", async () => {
    rpc.mockImplementation(chain((q) => (q.includes("TrackJSON(12)") ? undefined : world(q))));
    for (const path of ["/artist/3", "/album/2", "/playlist/5"]) expect((await tags(path)).og, path).not.toBe("GnoRadio"); // a card, not the untouched page
  });

  it("returns the page as is for unknown pages, bad ids and RPC failures", async () => {
    for (const path of ["/stations", "/track/none", "/listener/g1nope", `/door/x-${WALLET}`, "/concerts"]) expect(await run(path), path).toBe(page);
    expect(rpc).not.toHaveBeenCalled();
    expect(await run("/track/99")).not.toBe(page); // the fake answers every TrackJSON
    expect(await run("/album/77")).toBe(page); // a realm error
    rpc.mockResolvedValue(Response.json({ result: {} }));
    expect(await run("/track/3")).toBe(page);
    rpc.mockRejectedValue(new Error("down"));
    expect(await run("/track/3")).toBe(page);
  });
});

describe("runtimeEnv", () => {
  afterEach(() => { vi.unstubAllGlobals(); vi.unstubAllEnvs(); });
  it("reads Netlify.env on the edge, process.env elsewhere", () => {
    vi.unstubAllGlobals();
    vi.stubEnv("VITE_GNORADIO_NS", "from-process");
    expect(runtimeEnv("VITE_GNORADIO_NS")).toBe("from-process");
    vi.stubGlobal("Netlify", { env: { get: (k: string) => (k === "VITE_GNORADIO_NS" ? "from-edge" : undefined) } });
    expect(runtimeEnv("VITE_GNORADIO_NS")).toBe("from-edge");
  });
});

describe("utf8Base64", () => {
  it("encodes non-Latin text as UTF-8, so the node can read a dedication like 'días'", async () => {
    const { utf8Base64 } = await import("../src/lib/format");
    expect(new TextDecoder().decode(Uint8Array.from(atob(utf8Base64("días ☀")), (c) => c.charCodeAt(0)))).toBe("días ☀");
  });
});
