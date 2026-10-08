// @vitest-environment node
import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";
import verify from "./functions/verify.mjs";
import { RealmError } from "./cards";
import { WELL_KNOWN, proofLine } from "../src/lib/proof";
import { WALLET, keyPair, post, str, verifies } from "./testing";
import { serverChainId } from "../src/lib/network";
import { REALMS } from "../src/lib/realms";

const chain = vi.hoisted(() => ({ calls: [] as string[], artist: {}, track: { audio: "audius:T1" }, fail: "" }));
// The chain, through netlify/'s one read client (cards.qevalRaw). ClaimMessage answers as the realm does.
vi.mock("./cards", async (orig) => {
  // The realm's text, built from the same chain id and data path as the robot (not through ./bot: it imports this module).
  const { serverChainId } = await import("../src/lib/network");
  const { REALMS } = await import("../src/lib/realms");
  const certificate = (kind: string, ...f: (string | number)[]) => [`gnoradio-${kind}`, serverChainId(), REALMS.data, ...f.map(String)].join("|");
  const answer = (expr: string): string => {
    chain.calls.push(expr);
    // The node's panic for a hidden artist, or an outage (the 3 s timeout, a 5xx).
    if (chain.fail && expr.startsWith("ArtistJSON(")) throw chain.fail === "realm" ? new RealmError("no answer") : new Error("The operation timed out");
    if (expr.startsWith("ArtistJSON(")) return str(JSON.stringify(chain.artist));
    if (expr.startsWith("TrackJSON(")) return str(JSON.stringify(chain.track));
    if (expr.startsWith("ClaimMessage(")) return str(certificate("claim", ...(JSON.parse(`[${expr.slice(13, -1)}]`) as (string | number)[])));
    return "";
  };
  const { unquote } = await import("../src/lib/proof");
  return { ...(await orig<object>()), qevalRaw: (_rpc: string, _pkg: string, expr: string) => Promise.resolve(answer(expr)), qeval: (_rpc: string, _pkg: string, expr: string) => Promise.resolve(unquote(answer(expr))) };
});

const LINE = proofLine(7, WALLET);
const artist = (a: object = {}) => ({ id: 7, kind: "", owner: "", source: "", verified: false, tracks: [1], ...a });
const json = async (r: Response) => (await r.json()) as { error?: string; found?: boolean; page?: string; line?: string; expires?: number; sig?: string; note?: string };

/** web answers outbound fetches by URL; dns maps a host to its A records (public by default). */
let web: Record<string, () => Response>;
let dns: Record<string, string[]>;
let fetched: string[];
function fakeFetch(input: string | URL | Request): Promise<Response> {
  const url = new URL(input instanceof Request ? input.url : input);
  fetched.push(url.href);
  if (url.hostname === "cloudflare-dns.com") {
    const host = url.searchParams.get("name") ?? "";
    const ips = url.searchParams.get("type") === "A" ? (dns[host] ?? ["93.184.216.34"]) : [];
    return Promise.resolve(Response.json({ Answer: ips.map((data) => ({ type: 1, data })) }));
  }
  const page = web[url.href];
  return page ? Promise.resolve(page()) : Promise.reject(new Error(`unexpected fetch ${url.href}`));
}

let publicKey: CryptoKey;
beforeEach(async () => {
  const k = await keyPair();
  publicKey = k.publicKey;
  vi.stubEnv("URL", "https://radio.example");
  vi.stubEnv("VITE_GNORADIO_NS", "gnoradio");
  vi.stubEnv("BOT_SIGNING_KEY", k.seed);
  chain.calls = [];
  chain.artist = artist();
  chain.track = { audio: "audius:T1" };
  chain.fail = "";
  web = { [`https://artist.example${WELL_KNOWN}`]: () => new Response(`hello\n${LINE}\n`) };
  dns = {};
  fetched = [];
  vi.stubGlobal("fetch", fakeFetch);
});

afterEach(() => {
  vi.unstubAllEnvs();
  vi.unstubAllGlobals();
});

const ask = (body: object = {}) => verify(post({ artist: 7, wallet: WALLET, page: "https://artist.example", ...body }));

describe("verify input", () => {
  it.each([
    ["bad JSON", "{"],
    ["artist 0", { artist: 0, wallet: WALLET }],
    ["artist 1.5", { artist: 1.5, wallet: WALLET }],
    ["artist missing", { wallet: WALLET }],
    ["bad wallet", { artist: 7, wallet: "g1nope" }],
  ])("refuses %s with 400", async (_name, body) => {
    expect((await verify(post(body))).status).toBe(400);
    expect(chain.calls).toEqual([]);
  });

  it("refuses a profile already verified", async () => {
    chain.artist = artist({ verified: true });
    expect((await ask()).status).toBe(409);
  });

  it("refuses a profile owned by another wallet", async () => {
    chain.artist = artist({ owner: `g1${"z".repeat(38)}` });
    expect((await ask()).status).toBe(403);
    chain.artist = artist({ owner: WALLET });
    expect((await ask()).status).toBe(200);
  });
});

describe("verify well-known file", () => {
  it("signs a certificate when the file holds the line", async () => {
    const before = Math.floor(Date.now() / 1000);
    const r = await ask();
    expect(r.status).toBe(200);
    const b = await json(r);
    expect(b).toMatchObject({ found: true, page: `https://artist.example${WELL_KNOWN}` });
    expect((b.expires ?? 0) - before).toBeLessThanOrEqual(7200);
    expect(await verifies(publicKey, b.sig ?? "", ["gnoradio-claim", serverChainId(), REALMS.data, 7, WALLET, `https://artist.example${WELL_KNOWN}`, b.expires].join("|"))).toBe(true);
    expect(chain.calls).toContain(`ClaimMessage(7, ${JSON.stringify(WALLET)}, ${JSON.stringify(`https://artist.example${WELL_KNOWN}`)}, ${String(b.expires)})`);
  });

  it("reads the well-known path whatever page is given", async () => {
    expect((await ask({ page: "https://artist.example/about?x=1" })).status).toBe(200);
  });

  it("reports the proof found without a signing key", async () => {
    vi.stubEnv("BOT_SIGNING_KEY", "");
    const b = await json(await ask());
    expect(b.found).toBe(true);
    expect(b.sig).toBeUndefined();
  });

  it.each(["https://artist.example", "https://archive.example/lea", "https://www.archive.example/lea"])("never verifies an imported profile, whatever page (%s): the moderator does", async (page) => {
    chain.artist = artist({ kind: "curated", source: "https://archive.example/details/lea" });
    const r = await ask({ page });
    expect(r.status).toBe(400);
    expect((await json(r)).error).toMatch(/Imported profiles are verified by the GnoRadio moderator/);
    expect(fetched).toEqual([]);
    expect(chain.calls.some((e) => e.startsWith("ClaimMessage("))).toBe(false);
  });

  it("answers notFound with the line to publish", async () => {
    web[`https://artist.example${WELL_KNOWN}`] = () => new Response("nothing here");
    const r = await ask();
    expect(r.status).toBe(422);
    expect(await json(r)).toEqual({ error: "notFound", page: `https://artist.example${WELL_KNOWN}`, line: LINE });
  });

  it("refuses a page several wallets claim", async () => {
    web[`https://artist.example${WELL_KNOWN}`] = () => new Response(`${LINE} ${proofLine(7, `g1${"z".repeat(38)}`)}`);
    expect((await ask()).status).toBe(422);
  });

  it.each(["http://artist.example", "https://artist.example:8443", "https://10.0.0.1", "https://printer.local", "not a url", ""])("refuses page %j", async (page) => {
    expect((await ask({ page })).status).toBe(400);
    expect(fetched).toEqual([]);
  });

  it.each(["github.com", "user.github.com", "archive.org"])("refuses shared host %s", async (host) => {
    const r = await ask({ page: `https://${host}/me` });
    expect(r.status).toBe(400);
    expect((await json(r)).error).toContain(host);
    expect(fetched).toEqual([]);
  });

  it.each([["10.0.0.5"], ["127.0.0.1"], ["169.254.169.254"], ["93.184.216.34", "192.168.1.1"]])("refuses a name pointing inside a network (%s)", async (...ips) => {
    dns["artist.example"] = ips;
    const r = await ask();
    expect(r.status).toBe(502);
    expect((await json(r)).error).toBe("We could not read that file. Check the address and that it is public.");
    expect(fetched.some((u) => u.includes(WELL_KNOWN))).toBe(false);
  });

  it("refuses a name that does not resolve", async () => {
    dns["artist.example"] = [];
    expect((await ask()).status).toBe(502);
  });

  it("follows a redirect on the same host only", async () => {
    web[`https://artist.example${WELL_KNOWN}`] = () => new Response(null, { status: 301, headers: { location: "/proof.txt" } });
    web["https://artist.example/proof.txt"] = () => new Response(LINE);
    expect((await ask()).status).toBe(200);

    web["https://artist.example/proof.txt"] = () => new Response(null, { status: 302, headers: { location: "https://evil.example/x" } });
    web["https://evil.example/x"] = () => new Response(LINE);
    expect((await ask()).status).toBe(502);
    expect(fetched).not.toContain("https://evil.example/x");

    web["https://artist.example/proof.txt"] = () => new Response(null, { status: 302, headers: { location: "http://artist.example/x" } });
    expect((await ask()).status).toBe(502);
  });

  it("gives up after a few redirects", async () => {
    web[`https://artist.example${WELL_KNOWN}`] = () => new Response(null, { status: 302, headers: { location: WELL_KNOWN } });
    expect((await ask()).status).toBe(502);
  });

  it("refuses an error page", async () => {
    web[`https://artist.example${WELL_KNOWN}`] = () => new Response(LINE, { status: 404 });
    expect((await ask()).status).toBe(502);
  });

  it("reads at most 1 MB and hangs up on an endless file", async () => {
    let cancelled = false;
    const endless = (first: string) => () => {
      let sent = 0;
      return new Response(
        new ReadableStream<Uint8Array>({
          pull(c) {
            c.enqueue(new TextEncoder().encode(sent++ === 0 ? first : "x".repeat(65_536)));
          },
          cancel() {
            cancelled = true;
          },
        }),
      );
    };
    web[`https://artist.example${WELL_KNOWN}`] = endless(`${LINE}\n`);
    expect((await ask()).status).toBe(200);
    expect(cancelled).toBe(true);

    // A line past the cap is never read.
    let sent = 0;
    web[`https://artist.example${WELL_KNOWN}`] = () =>
      new Response(
        new ReadableStream<Uint8Array>({
          pull(c) {
            if (sent > 1_100_000) {
              c.enqueue(new TextEncoder().encode(LINE));
              c.close();
              return;
            }
            sent += 65_536;
            c.enqueue(new TextEncoder().encode("x".repeat(65_536)));
          },
        }),
      );
    expect((await ask()).status).toBe(422);
  });
});

describe("verify Audius", () => {
  const audius = (user: object | null) => () => Response.json({ data: user ? { user } : {} });
  beforeEach(() => {
    chain.artist = artist({ kind: "audius", tracks: [4, 5] });
  });

  it("reads the bio of the profile owning the first track", async () => {
    web["https://api.audius.co/v1/tracks/T1?app_name=GnoRadio"] = audius({ handle: "dj", bio: `hi ${LINE}` });
    const r = await ask({ page: "https://ignored.example" });
    expect(r.status).toBe(200);
    expect((await json(r)).page).toBe("https://audius.co/dj");
    expect(chain.calls).toContain("TrackJSON(4)");
    expect(fetched.some((u) => u.includes("ignored.example") || u.includes("cloudflare-dns"))).toBe(false);
  });

  it("answers notFound when the bio lacks the line", async () => {
    web["https://api.audius.co/v1/tracks/T1?app_name=GnoRadio"] = audius({ handle: "dj" });
    const r = await ask();
    expect(r.status).toBe(422);
    expect((await json(r)).page).toBe("https://audius.co/dj");
  });

  it("fails without leaking details when Audius or the track is unusable", async () => {
    web["https://api.audius.co/v1/tracks/T1?app_name=GnoRadio"] = audius(null);
    expect(await json(await ask())).toEqual({ error: "The check failed, try again in a minute." });
    chain.track = { audio: "ipfs:abc" };
    expect((await ask()).status).toBe(502);
    chain.artist = artist({ kind: "audius", tracks: [] });
    expect((await ask()).status).toBe(502);
  });
});

describe("verify chain reads", () => {
  it("says a hidden artist is unknown, but an outage is retryable, not a missing profile", async () => {
    chain.fail = "realm";
    expect((await ask()).status).toBe(404);
    chain.fail = "net";
    const r = await ask();
    expect(r.status).toBe(502);
    expect((await json(r)).error).toMatch(/try again/);
  });
});
