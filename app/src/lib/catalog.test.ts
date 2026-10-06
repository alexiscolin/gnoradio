import { describe, expect, it } from "vitest";
import { audioURL } from "./catalog";

describe("audioURL", () => {
  it("resolves every supported scheme", () => {
    expect(audioURL({ audio: "ipfs://bafy123" })).toBe("https://ipfs.io/ipfs/bafy123");
    expect(audioURL({ audio: "ar://abc" })).toBe("https://arweave.net/abc");
    expect(audioURL({ audio: "audius:x5dg3" })).toBe("https://api.audius.co/v1/tracks/x5dg3/stream?app_name=GnoRadio");
    expect(audioURL({ audio: "https://archive.org/download/a/b.mp3" })).toBe("https://archive.org/download/a/b.mp3");
  });
});
