import { describe, expect, it } from "vitest";
import { mediaURLs, safeHttps, safeMedia } from "./safe";

describe("safe URLs", () => {
  it("only lets https through to links", () => {
    expect(safeHttps("https://audius.co/attlas")).toBe("https://audius.co/attlas");
    expect(safeHttps("javascript:alert(1)")).toBe("");
    expect(safeHttps("http://example.org")).toBe("");
    expect(safeHttps("data:text/html,x")).toBe("");
    expect(safeHttps("https://")).toBe("");
  });
  it("accepts the media schemes the realm allows", () => {
    expect(safeMedia("ipfs://bafy")).toBe("ipfs://bafy");
    expect(safeMedia("ar://abc")).toBe("ar://abc");
    expect(safeMedia("audius:x5dg3")).toBe("audius:x5dg3");
    expect(safeMedia("JaVaScRiPt:alert(1)")).toBe("");
    expect(safeMedia("blob:https://x")).toBe("");
  });
  it("resolves nothing for an unsafe reference", () => {
    expect(mediaURLs("javascript:alert(1)")).toEqual([]);
  });
});
