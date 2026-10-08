import { describe, expect, it } from "vitest";
import { coverHost, mediaURLs, safeHttps, safeMedia, setStream } from "./safe";

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
    expect(mediaURLs("jamendo:42")).toEqual([]); // no stream from the live meta yet: no source yet
    setStream("jamendo:42", "https://evil.example/x.mp3");
    expect(mediaURLs("jamendo:42")).toEqual([]); // jamendo.com only
    setStream("jamendo:42", "https://prod-1.storage.jamendo.com/?trackid=42&from=tok");
    expect(mediaURLs("jamendo:42")).toEqual(["https://prod-1.storage.jamendo.com/?trackid=42&from=tok"]);
    setStream("jamendo:42");
    expect(mediaURLs("jamendo:42")).toEqual([]);
  });
});

describe("coverHost", () => {
  it("only lets a server fetch covers from the media hosts", () => {
    expect(coverHost("https://ipfs.io/ipfs/bafy")).toBe(true);
    expect(coverHost("https://ia800.us.archive.org/x.jpg")).toBe(true);
    expect(coverHost("https://arweave.net/abc")).toBe(true);
    expect(coverHost("http://ipfs.io/ipfs/bafy")).toBe(false);
    expect(coverHost("https://ipfs.io:8443/ipfs/bafy")).toBe(false);
    expect(coverHost("https://user@ipfs.io/ipfs/bafy")).toBe(false);
    expect(coverHost("https://evilipfs.io/x")).toBe(false);
    expect(coverHost("https://ipfs.io.evil.com/x")).toBe(false);
    expect(coverHost("https://169.254.169.254/latest/meta-data")).toBe(false);
    expect(coverHost("https://localhost/x")).toBe(false);
    expect(coverHost("file:///etc/passwd")).toBe(false);
  });
});
