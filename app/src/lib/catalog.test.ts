import { describe, expect, it, vi } from "vitest";
import { audioURLs, batched, settle } from "./catalog";
import { DataError, RealmError } from "./gno";

describe("audioURLs", () => {
  it("resolves every supported scheme", () => {
    expect(audioURLs({ audio: "ipfs://bafy123" })).toEqual(["https://ipfs.io/ipfs/bafy123", "https://dweb.link/ipfs/bafy123", "https://cloudflare-ipfs.com/ipfs/bafy123"]);
    expect(audioURLs({ audio: "ar://abc" })).toEqual(["https://arweave.net/abc"]);
    expect(audioURLs({ audio: "audius:x5dg3" })).toEqual(["https://api.audius.co/v1/tracks/x5dg3/stream?app_name=GnoRadio"]);
    expect(audioURLs({ audio: "https://archive.org/download/a/b.mp3" })).toEqual(["https://archive.org/download/a/b.mp3"]);
  });
});

describe("settle", () => {
  it("skips realm refusals and bad records but fails on network errors", async () => {
    const warn = vi.spyOn(console, "warn").mockImplementation(() => undefined);
    await expect(settle([Promise.resolve(1), Promise.reject(new RealmError("hidden")), Promise.reject(new DataError("bad")), Promise.resolve(4)])).resolves.toEqual([1, 4]);
    expect(warn).toHaveBeenCalledTimes(1);
    await expect(settle([Promise.resolve(1), Promise.reject(new Error("RPC returned 502"))])).rejects.toThrow("RPC returned 502");
    warn.mockRestore();
  });
});

describe("batched", () => {
  it("re-reads a batch item by item when one record is bad, losing only that record", async () => {
    const warn = vi.spyOn(console, "warn").mockImplementation(() => undefined);
    const many = (o: number) => (o === 0 ? Promise.reject(new DataError("bad record")) : Promise.resolve([o + 1]));
    const one = (id: number) => (id === 2 ? Promise.reject(new DataError("bad")) : Promise.resolve(id));
    const out = await batched(103, many, one);
    expect(out).toHaveLength(100); // 99 of ids 1..100 (id 2 is bad), plus [101] from the second batch
    expect(out).not.toContain(2);
    expect(out).toContain(101);
    warn.mockRestore();
  });
});
