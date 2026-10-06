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
  it("never runs more than 6 queries at once", async () => {
    let live = 0;
    let peak = 0;
    const good = { result: { response: { ResponseBase: { Error: null, Data: b64(`(${JSON.stringify('"ok"')} string)`), Log: "" } } } };
    vi.stubGlobal("fetch", vi.fn(async () => {
      live++;
      peak = Math.max(peak, live);
      await new Promise((r) => setTimeout(r, 5));
      live--;
      return { ok: true, status: 200, json: () => Promise.resolve(good) };
    }));
    await Promise.all(Array.from({ length: 20 }, () => qjson(REALMS.catalog, "Info()", str)));
    expect(peak).toBe(6);
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
