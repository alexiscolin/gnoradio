import { describe, expect, it } from "vitest";
import { hashToView, viewToHash } from "./router";
import type { View } from "./types";

describe("router", () => {
  const views: View[] = [
    { k: "listen" }, { k: "stations" }, { k: "library", genre: 0 }, { k: "library", genre: 4 }, { k: "community" },
    { k: "me" }, { k: "studio" }, { k: "track", id: 12 }, { k: "artist", id: 2 }, { k: "album", id: 1 }, { k: "playlist", id: 9 },
  ];
  it.each(views)("round-trips %o", (v) => {
    expect(hashToView(viewToHash(v))).toEqual(v);
  });
  it("falls back to listen on garbage", () => {
    expect(hashToView("#/track/abc")).toEqual({ k: "listen" });
    expect(hashToView("#/nope")).toEqual({ k: "listen" });
    expect(hashToView("")).toEqual({ k: "listen" });
    expect(hashToView("#/track/-3")).toEqual({ k: "listen" });
  });
});
