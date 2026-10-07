import { afterEach, describe, expect, it, vi } from "vitest";
import { loadNames, nameOf, nameShape } from "./names";

const b64 = (s: string) => btoa(String.fromCharCode(...new TextEncoder().encode(s)));
const A = "g1jg8mtutu9khhfwc4nxmuhcpftf0pajdhfvsqf5";
const B = "g1hplnue27uazg4pa7vfhzga64na9skvglqatedj";
const C = "g1u7y667z64x2h7vc6fmpcprgey4ck233jaww9zq";
const D = "g1manfred47kzduec920z88wfr64ylksmdcedlf5";

// rpc answers r/sys/users with `users` and p/gnoradio/safe with `bits`, and records each query.
const rpc = (users: string, bits: string) => {
  const seen: string[] = [];
  const f = vi.fn((_: string, init: { body: string }) => {
    const { params } = JSON.parse(init.body) as { params: { data: string } };
    const q = new TextDecoder().decode(Uint8Array.from(atob(params.data), (c) => c.charCodeAt(0)));
    seen.push(q);
    const out = q.startsWith("gno.land/p/gnoradio/safe") ? bits : users;
    return Promise.resolve({ ok: true, status: 200, json: () => Promise.resolve({ result: { response: { ResponseBase: { Error: null, Data: b64(`(${JSON.stringify(out)} string)`), Log: "" } } } }) });
  });
  vi.stubGlobal("fetch", f);
  return { f, seen };
};

afterEach(() => { vi.unstubAllGlobals(); });

describe("names", () => {
  it("reads many names in one query and caches them", async () => {
    const { f, seen } = rpc("alice,,", "0");
    await loadNames([A, B, "not-an-address"]);
    expect(nameOf(A)).toBe("alice");
    expect(nameOf(B)).toBe("");
    expect(seen[1]).toContain(`[]string{"alice"}`); // only real names are screened
    await loadNames([A, B]);
    expect(f).toHaveBeenCalledTimes(2);
  });
  it("shows the address instead of an offensive name, and caches that too", async () => {
    const { f } = rpc("slur,bob,", "10");
    await loadNames([C, D]);
    expect(nameOf(C)).toBe("");
    expect(nameOf(D)).toBe("bob");
    await loadNames([C, D]);
    expect(f).toHaveBeenCalledTimes(2);
  });
  it("checks a new name's shape", () => {
    expect(nameShape("lea_kosmos")).toBe(true);
    expect(nameShape("Lea")).toBe(false);
    expect(nameShape("")).toBe(false);
  });
});
