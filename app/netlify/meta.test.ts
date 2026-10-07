// @vitest-environment node
import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";
import meta from "./edge-functions/meta";
import { REALMS } from "../src/lib/realms";

const HTML = `<html><head><title>GnoRadio</title>
<meta name="description" content="Community radio" />
<meta property="og:title" content="GnoRadio" />
<meta property="og:description" content="Community radio" />
<meta property="og:url" content="https://radio.example/" />
<meta name="twitter:title" content="GnoRadio" />
</head></html>`;

const BOT = "WhatsApp/2.23";
const qeval = (v: object) => Response.json({ result: { response: { ResponseBase: { Data: btoa(`(${JSON.stringify(JSON.stringify(v))} string)`) } } } });

let rpc: ReturnType<typeof vi.fn<(url: string, init?: RequestInit) => Promise<Response>>>;
let page: Response;
const run = (path: string, ua: string) => {
  page = new Response(HTML, { headers: { "content-type": "text/html", "content-length": "999", etag: "x" } });
  return meta(new Request(`https://radio.example${path}`, { headers: { "user-agent": ua } }), { next: () => Promise.resolve(page) });
};

beforeEach(() => {
  rpc = vi.fn(() => Promise.resolve(qeval({ title: "Night Drive", artistName: "Ana" })));
  vi.stubGlobal("fetch", rpc);
  vi.stubGlobal("Netlify", { env: { get: () => "https://rpc.test" } });
});
afterEach(() => {
  vi.unstubAllGlobals();
});

describe("meta", () => {
  it("leaves the page untouched for people", async () => {
    expect(await run("/track/12", "Mozilla/5.0 Firefox")).toBe(page);
    expect(rpc).not.toHaveBeenCalled();
  });

  it("writes the on-chain name into the tags for preview bots", async () => {
    const r = await run("/track/night-drive-12", BOT);
    const html = await r.text();
    expect(html).toContain("<title>Night Drive · Ana · GnoRadio</title>");
    expect(html).toContain('<meta property="og:title" content="Night Drive · Ana · GnoRadio"');
    expect(html).toContain('<meta name="twitter:title" content="Night Drive · Ana · GnoRadio"');
    expect(html).toContain('<meta property="og:url" content="https://radio.example/track/night-drive-12"');
    expect(html).toMatch(/og:description" content="Listen to Night Drive · Ana on GnoRadio/);
    expect(r.headers.get("content-length")).toBeNull();
    expect(r.headers.get("etag")).toBeNull();
    const [url, init] = rpc.mock.calls[0] ?? [];
    expect(url).toBe("https://rpc.test");
    expect(JSON.parse(init?.body as string)).toMatchObject({ params: { path: "vm/qeval", data: btoa(`${REALMS.catalog}.TrackJSON(12)`) } });
  });

  it("keeps $-patterns in names as text", async () => {
    rpc.mockResolvedValue(qeval({ name: "$& $1 $` $' $$" }));
    const html = await (await run("/artist/3", BOT)).text();
    expect(html).toContain("<title>$&#38; $1 $` $' $$ · GnoRadio</title>");
    expect(html).toContain('<meta property="og:title" content="$&#38; $1 $` $\' $$ · GnoRadio"');
  });

  it("escapes HTML in names and bios", async () => {
    rpc.mockResolvedValue(qeval({ name: '"><script>alert(1)</script>', bio: "a & b <i>" }));
    const html = await (await run("/artist/3", BOT)).text();
    expect(html).not.toContain("<script>");
    expect(html).toContain("<title>&#34;&#62;&#60;script&#62;alert(1)&#60;/script&#62; · GnoRadio</title>");
    expect(html).toContain('<meta name="description" content="a &#38; b &#60;i&#62;"');
  });

  it("returns the page as is for unknown kinds, missing ids, empty answers and errors", async () => {
    expect(await run("/station/3", BOT)).toBe(page);
    expect(await run("/track/none", BOT)).toBe(page);
    expect(rpc).not.toHaveBeenCalled();
    rpc.mockResolvedValue(Response.json({ result: {} }));
    expect(await run("/track/3", BOT)).toBe(page);
    rpc.mockRejectedValue(new Error("down"));
    expect(await run("/track/3", BOT)).toBe(page);
  });
});
