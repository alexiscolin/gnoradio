import { afterEach, describe, expect, it, vi } from "vitest";
import { REALMS, gnoAddress, qjson } from "./gno";
import { num, obj, str } from "./guard";

const b64 = (s: string) => btoa(String.fromCharCode(...new TextEncoder().encode(s)));

function mockRPC(body: unknown, ok = true) {
  vi.stubGlobal("fetch", vi.fn(() => Promise.resolve({ ok, status: ok ? 200 : 500, json: () => Promise.resolve(body) })));
}

afterEach(() => { vi.unstubAllGlobals(); });

describe("qjson", () => {
  it("parses a realm JSON export, including unicode", async () => {
    const inner = JSON.stringify({ title: "Minuit sur le Rhône", n: 3 });
    mockRPC({ result: { response: { ResponseBase: { Error: null, Data: b64(`(${JSON.stringify(inner)} string)`), Log: "" } } } });
    await expect(qjson(REALMS.catalog, "Info()", obj({ title: str, n: num }))).resolves.toEqual({ title: "Minuit sur le Rhône", n: 3 });
  });
  it("surfaces realm errors", async () => {
    mockRPC({ result: { response: { ResponseBase: { Error: { msg: "x" }, Data: null, Log: "catalog: unknown track" } } } });
    await expect(qjson(REALMS.catalog, "TrackJSON(99)", str)).rejects.toThrow("catalog: unknown track");
  });
  it("rejects non-string results", async () => {
    mockRPC({ result: { response: { ResponseBase: { Error: null, Data: b64("(42 int)"), Log: "" } } } });
    await expect(qjson(REALMS.catalog, "TrackCount()", str)).rejects.toThrow("Unexpected result");
  });
  it("fails clearly when the RPC is down, after retrying", async () => {
    vi.useFakeTimers();
    mockRPC({}, false);
    const p = qjson(REALMS.catalog, "Info()", str);
    const done = expect(p).rejects.toThrow("RPC returned 500");
    await vi.runAllTimersAsync();
    await done;
    expect(fetch).toHaveBeenCalledTimes(4);
    vi.useRealTimers();
  });
  it("retries a rate limit and then succeeds", async () => {
    vi.useFakeTimers();
    const good = { result: { response: { ResponseBase: { Error: null, Data: b64(`(${JSON.stringify('"ok"')} string)`), Log: "" } } } };
    const f = vi.fn()
      .mockResolvedValueOnce({ ok: false, status: 429, json: () => Promise.resolve({}) })
      .mockResolvedValue({ ok: true, status: 200, json: () => Promise.resolve(good) });
    vi.stubGlobal("fetch", f);
    const p = qjson(REALMS.catalog, "Info()", str);
    await vi.runAllTimersAsync();
    await expect(p).resolves.toBe("ok");
    expect(f).toHaveBeenCalledTimes(2);
    vi.useRealTimers();
  });
  it("retries a timed-out query", async () => {
    vi.useFakeTimers();
    const good = { result: { response: { ResponseBase: { Error: null, Data: b64(`(${JSON.stringify('"ok"')} string)`), Log: "" } } } };
    const f = vi.fn()
      .mockRejectedValueOnce(new DOMException("The operation timed out.", "TimeoutError"))
      .mockResolvedValue({ ok: true, status: 200, json: () => Promise.resolve(good) });
    vi.stubGlobal("fetch", f);
    const p = qjson(REALMS.catalog, "Info()", str);
    await vi.runAllTimersAsync();
    await expect(p).resolves.toBe("ok");
    expect(f).toHaveBeenCalledTimes(2);
    const init = f.mock.calls[0]?.[1] as RequestInit | undefined;
    expect(init?.signal).toBeInstanceOf(AbortSignal);
    vi.useRealTimers();
  });
  it("never sends more than 6 requests at once", async () => {
    let live = 0;
    let peak = 0;
    const good = { result: { response: { ResponseBase: { Error: null, Data: b64(`(${JSON.stringify('"ok"')} string)`), Log: "" } } } };
    vi.stubGlobal("fetch", vi.fn(async (_: string, init: RequestInit) => {
      live++;
      peak = Math.max(peak, live);
      await new Promise((r) => setTimeout(r, 5));
      live--;
      const body = JSON.parse(init.body as string) as { id: number } | { id: number }[];
      return { ok: true, status: 200, json: () => Promise.resolve(Array.isArray(body) ? body.map((b) => ({ ...good, id: b.id })) : good) };
    }));
    await Promise.all(Array.from({ length: 200 }, () => qjson(REALMS.catalog, "Info()", str)));
    expect(peak).toBe(6);
    expect(fetch).toHaveBeenCalledTimes(50); // batches of 4
  });
  it("settles each query of a batch on its own reply", async () => {
    const ok = (s: string) => ({ result: { response: { ResponseBase: { Error: null, Data: b64(`(${JSON.stringify(JSON.stringify(s))} string)`), Log: "" } } } });
    const refused = { result: { response: { ResponseBase: { Error: { msg: "x" }, Data: null, Log: "catalog: unknown track" } } } };
    const answer = (init: RequestInit): unknown => {
      const body = JSON.parse(init.body as string) as { id: number } | { id: number }[];
      return Array.isArray(body) ? body.map((q) => ({ ...ok("b"), id: q.id })) : ok("b");
    };
    // 13 queries go out 4 per request; the first request's replies come out of order, one refused, two missing.
    const f = vi.fn((_: string, init: RequestInit) => Promise.resolve({ ok: true, status: 200, json: () => Promise.resolve(answer(init)) }))
      .mockResolvedValueOnce({ ok: true, status: 200, json: () => Promise.resolve([{ ...refused, id: 1 }, { ...ok("a"), id: 0 }]) });
    vi.stubGlobal("fetch", f);
    const out = await Promise.allSettled(Array.from({ length: 13 }, (_, i) => qjson(REALMS.catalog, `Q${String(i)}()`, str)));
    expect(out.map((r) => (r.status === "fulfilled" ? r.value : (r.reason as Error).name))).toEqual(["a", "RealmError", ...Array<string>(11).fill("b")]);
    expect(f).toHaveBeenCalledTimes(6); // 4 requests, and the two missing replies asked again
  });
  it("falls back to one query per request when the RPC does not batch", async () => {
    const good = { result: { response: { ResponseBase: { Error: null, Data: b64(`(${JSON.stringify('"ok"')} string)`), Log: "" } } } };
    const f = vi.fn((_: string, init: RequestInit) => Promise.resolve({
      ok: true, status: 200,
      json: () => Promise.resolve((init.body as string).startsWith("[") ? { error: { code: -32600, message: "batch not supported" } } : good),
    }));
    vi.stubGlobal("fetch", f);
    const all = () => Promise.all(Array.from({ length: 12 }, () => qjson(REALMS.catalog, "Info()", str)));
    await expect(all()).resolves.toHaveLength(12);
    expect(f).toHaveBeenCalledTimes(3 + 12); // three refused batches of 4, then each query alone
    await all();
    expect(f).toHaveBeenCalledTimes(15 + 12); // and from then on, no more batches
  });
  it("falls back to one query per request when the RPC refuses a batch with an HTTP error", async () => {
    const good = { result: { response: { ResponseBase: { Error: null, Data: b64(`(${JSON.stringify('"ok"')} string)`), Log: "" } } } };
    const f = vi.fn((_: string, init: RequestInit) => Promise.resolve((init.body as string).startsWith("[")
      ? { ok: false, status: 400, json: () => Promise.resolve({}) }
      : { ok: true, status: 200, json: () => Promise.resolve(good) }));
    vi.stubGlobal("fetch", f);
    vi.resetModules(); // a fresh client, batching still on
    const fresh = await import("./gno");
    await expect(Promise.all(Array.from({ length: 12 }, () => fresh.qjson(REALMS.catalog, "Info()", str)))).resolves.toHaveLength(12);
    expect(f).toHaveBeenCalledTimes(3 + 12);
  });
});

describe("guards", () => {
  it("rejects data that does not match the schema", async () => {
    const inner = JSON.stringify({ title: 42 });
    mockRPC({ result: { response: { ResponseBase: { Error: null, Data: b64(`(${JSON.stringify(inner)} string)`), Log: "" } } } });
    await expect(qjson(REALMS.catalog, "Info()", obj({ title: str }))).rejects.toThrow("Unexpected data from the chain");
  });
  it("only quotes valid addresses into expressions", () => {
    expect(gnoAddress("g1jg8mtutu9khhfwc4nxmuhcpftf0pajdhfvsqf5")).toBe('"g1jg8mtutu9khhfwc4nxmuhcpftf0pajdhfvsqf5"');
    expect(() => gnoAddress('g1"); Freeze(true); ("')).toThrow("Invalid");
  });
});

describe("networkLabel", () => {
  it("names devnets and testnets, says nothing on mainnet", async () => {
    const { networkLabel } = await import("./gno");
    expect(networkLabel("dev")).toBe("Local devnet");
    expect(networkLabel("onyx-1")).toBe("Testnet · onyx-1");
    expect(networkLabel("test11")).toBe("Testnet · test11");
    expect(networkLabel("gnoland-1")).toBe("");
  });
});
