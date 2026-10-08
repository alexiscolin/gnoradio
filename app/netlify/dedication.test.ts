// @vitest-environment node
import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";
import dedication from "./functions/dedication.mjs";
import { DOWN } from "../src/lib/moderation";
import { REALMS, SAFE } from "../src/lib/realms";
import { WALLET, keyPair, post, str, verifies } from "./testing";
import { certificate } from "./bot";

// The chain: every evaluateExpression goes through chain.eval, set per test.
type Eval = (pkg: string, expr: string) => string;
const chain = vi.hoisted((): { calls: [string, string][]; eval: Eval } => ({ calls: [], eval: () => "" }));
vi.mock("./cards", async (orig) => {
  const { unquote } = await import("../src/lib/proof");
  const answer = (pkg: string, expr: string) => { chain.calls.push([pkg, expr]); return chain.eval(pkg, expr); };
  return { ...(await orig<object>()), qevalRaw: (_rpc: string, pkg: string, expr: string) => Promise.resolve(answer(pkg, expr)), qeval: (_rpc: string, pkg: string, expr: string) => Promise.resolve(unquote(answer(pkg, expr))) };
});

// NoteMessage answers as the realm does: the robot signs only that exact text.
const okChain = (pkg: string, expr: string) =>
  pkg === SAFE ? str("") : expr.startsWith("NoteMessage(") ? str(certificate("note", ...(JSON.parse(`[${expr.slice(12, -1)}]`) as (string | number)[]))) : expr.startsWith("MutedUntil(") ? "(0 int64)" : "";
const scores = (s: Record<string, number>) => Response.json({ results: [{ category_scores: s }] });
const json = async (r: Response) => (await r.json()) as { error?: string; expires?: number; sig?: string };
const valid = { note: "Happy birthday Ana!", author: WALLET, station: 3 };

let publicKey: CryptoKey;
let openai: ReturnType<typeof vi.fn<(url: string, init?: RequestInit) => Promise<Response>>>;

beforeEach(async () => {
  const k = await keyPair();
  publicKey = k.publicKey;
  vi.stubEnv("URL", "https://radio.example");
  vi.stubEnv("VITE_GNORADIO_NS", "gnoradio");
  vi.stubEnv("NETLIFY_DEV", "");
  vi.stubEnv("OPENAI_API_KEY", "sk-test");
  vi.stubEnv("BOT_SIGNING_KEY", k.seed);
  chain.calls = [];
  chain.eval = okChain;
  openai = vi.fn(() => Promise.resolve(scores({ harassment: 0.1 })));
  vi.stubGlobal("fetch", openai);
});

afterEach(() => {
  vi.unstubAllEnvs();
  vi.unstubAllGlobals();
});

describe("dedication input", () => {
  it.each([
    ["bad JSON", "{"],
    ["no note", { ...valid, note: "" }],
    ["note not a string", { ...valid, note: 5 }],
    ["note too long", { ...valid, note: "a".repeat(161) }],
    ["bad author", { ...valid, author: "g1short" }],
    ["no station", { note: valid.note, author: WALLET }],
    ["fractional station", { ...valid, station: 1.5 }],
    ["negative station", { ...valid, station: -1 }],
    ["station over 1000", { ...valid, station: 1001 }],
  ])("refuses %s with 400", async (_name, body) => {
    const r = await dedication(post(body));
    expect(r.status).toBe(400);
    expect(chain.calls).toEqual([]);
    expect(openai).not.toHaveBeenCalled();
  });

  it("refuses emoji and lone surrogates with 422 before the chain", async () => {
    for (const note of ["hi 🎵", "hi \uD800"]) {
      const r = await dedication(post({ ...valid, note }));
      expect(r.status).toBe(422);
      expect((await json(r)).error).toMatch(/^Dedication: /);
    }
    expect(chain.calls).toEqual([]);
  });
});

describe("dedication judgment", () => {
  it("returns safe.Note's reason as a 422 without asking OpenAI", async () => {
    chain.eval = (pkg) => (pkg === SAFE ? str("no links") : "");
    const r = await dedication(post(valid));
    expect(r.status).toBe(422);
    expect((await json(r)).error).toBe("Dedication: no links.");
    expect(openai).not.toHaveBeenCalled();
    expect(chain.calls[0]).toEqual([SAFE, `Note(${JSON.stringify(valid.note)}, 40)`]);
  });

  it("refuses a muted author with 422 and when the pause ends, without asking OpenAI", async () => {
    chain.eval = (pkg, expr) => (expr.startsWith("MutedUntil(") ? "(1893456000 int64)" : okChain(pkg, expr));
    const r = await dedication(post(valid));
    expect(r.status).toBe(422);
    expect((await json(r)).error).toBe("Your dedications are paused after reports until Tue, 01 Jan 2030 00:00:00 GMT. Pick without one.");
    expect(openai).not.toHaveBeenCalled();
    expect(chain.calls.some(([, e]) => e.startsWith("NoteMessage("))).toBe(false);
  });

  it("asks rephrasing when OpenAI flags the note", async () => {
    openai.mockResolvedValue(scores({ "harassment/threatening": 0.9 }));
    const r = await dedication(post(valid));
    expect(r.status).toBe(422);
    expect((await json(r)).error).toBe("Please rephrase your dedication.");
    expect(chain.calls.some(([, e]) => e.startsWith("NoteMessage("))).toBe(false);
  });

  it("signs nothing when the realm's text is not this exact certificate", async () => {
    chain.eval = (pkg, expr) => (expr.startsWith("NoteMessage(") ? str("gnoradio-note|other-chain|x") : okChain(pkg, expr));
    expect((await dedication(post(valid))).status).toBe(503);
  });

  it("signs a short-lived certificate bound to author and station", async () => {
    const before = Math.floor(Date.now() / 1000);
    const r = await dedication(post(valid));
    expect(r.status).toBe(200);
    const { expires = 0, sig = "" } = await json(r);
    expect(expires).toBeGreaterThan(before);
    expect(expires - before).toBeLessThanOrEqual(900); // the realm refuses longer
    expect(await verifies(publicKey, sig, certificate("note", WALLET, 3, valid.note, expires))).toBe(true);
    expect(chain.calls[1]).toEqual([REALMS.radio, `MutedUntil(${JSON.stringify(WALLET)})`]);
    expect(chain.calls[2]).toEqual([REALMS.radio, `NoteMessage(${JSON.stringify(WALLET)}, 3, ${JSON.stringify(valid.note)}, ${String(expires)})`]);

    const [url, init] = openai.mock.calls[0] ?? [];
    expect(url).toBe("https://api.openai.com/v1/moderations");
    expect(new Headers(init?.headers).get("authorization")).toBe("Bearer sk-test");
    expect(JSON.parse(init?.body as string)).toMatchObject({ input: valid.note });
  });

  it.each([
    ["answers 500", () => Promise.resolve(new Response("", { status: 500 }))],
    ["answers no results", () => Promise.resolve(Response.json({}))],
    ["cannot be reached", () => Promise.reject(new Error("network"))],
  ])("pauses dedications (503) when OpenAI %s", async (_name, impl) => {
    openai.mockImplementation(impl);
    const r = await dedication(post(valid));
    expect(r.status).toBe(503);
    expect((await json(r)).error).toBe(DOWN);
  });

  it("pauses dedications when the chain or the signing key is missing", async () => {
    chain.eval = () => {
      throw new Error("rpc down");
    };
    expect((await dedication(post(valid))).status).toBe(503);
    chain.eval = okChain;
    vi.stubEnv("BOT_SIGNING_KEY", "");
    expect((await dedication(post(valid))).status).toBe(503);
  });

  it("pauses dedications without an OpenAI key in production", async () => {
    vi.stubEnv("OPENAI_API_KEY", "");
    const r = await dedication(post(valid));
    expect(r.status).toBe(503);
    expect(chain.calls).toEqual([]);
  });

  it("judges with the word filter only under netlify dev without a key", async () => {
    vi.stubEnv("OPENAI_API_KEY", "");
    vi.stubEnv("URL", "");
    vi.stubEnv("NETLIFY_DEV", "true");
    const r = await dedication(post(valid));
    expect(r.status).toBe(200);
    expect(openai).not.toHaveBeenCalled();
  });
});
