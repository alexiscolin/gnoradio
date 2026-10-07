import { describe, expect, it } from "vitest";
import { pathToView, sectionOf, sectionView, slug, viewToPath } from "./router";
import type { View } from "./types";

const A = "g1jg8mtutu9khhfwc4nxmuhcpftf0pajdhfvsqf5";

describe("router", () => {
  const views: View[] = [
    { k: "listen" }, { k: "stations" }, { k: "stations", live: 0 }, { k: "stations", live: 3 }, { k: "library", genre: 0 }, { k: "library", genre: 4 }, { k: "community" },
    { k: "me" }, { k: "studio" }, { k: "about" }, { k: "track", id: 12 }, { k: "artist", id: 2 }, { k: "album", id: 1 }, { k: "playlist", id: 9 },
    { k: "listener", address: A }, { k: "door", ticket: 7, holder: A }, { k: "collection", list: "saved" }, { k: "collection", list: "liked" },
  ];
  it.each(views)("round-trips %o, with or without a name", (v) => {
    expect(pathToView(viewToPath(v))).toEqual(v);
    expect(pathToView(viewToPath(v, "Scott Buckley"))).toEqual(v);
  });
  it("writes readable paths", () => {
    expect(viewToPath({ k: "artist", id: 1 }, "Scott Buckley")).toBe("/artist/scott-buckley-1");
    expect(viewToPath({ k: "track", id: 7 }, "Café del Mar (Remix)")).toBe("/track/cafe-del-mar-remix-7");
    expect(viewToPath({ k: "stations", live: 0 })).toBe("/live");
    expect(viewToPath({ k: "stations", live: 3 }, "Ambient")).toBe("/live/ambient-3");
    expect(slug("!!!")).toBe("");
    expect(viewToPath({ k: "track", id: 5 }, "!!!")).toBe("/track/5");
  });
  it("reads legacy hash links and falls back to listen on garbage", () => {
    expect(pathToView("#/artist/2")).toEqual({ k: "artist", id: 2 });
    expect(pathToView("#/station/3")).toEqual({ k: "stations", live: 3 });
    expect(pathToView("/track/abc")).toEqual({ k: "listen" });
    expect(pathToView("/nope")).toEqual({ k: "listen" });
    expect(pathToView("/door/7-nope")).toEqual({ k: "concerts" });
    expect(pathToView("/")).toEqual({ k: "listen" });
    expect(pathToView("/track/scott-buckley-x")).toEqual({ k: "listen" });
  });
});

describe("listener paths", () => {
  it("carries the name, keys on the address", () => {
    expect(viewToPath({ k: "listener", address: A }, "alice")).toBe(`/listener/alice-${A}`);
    expect(viewToPath({ k: "listener", address: A })).toBe(`/listener/${A}`);
    expect(pathToView(`/listener/bob-${A}`)).toEqual({ k: "listener", address: A });
    expect(pathToView(`#/listener/${A}`)).toEqual({ k: "listener", address: A });
    expect(pathToView("/listener/alice")).toEqual({ k: "listen" });
    expect(pathToView(`/listener/x${A}`)).toEqual({ k: "listen" });
    expect(sectionOf({ k: "listener", address: A })).toBe("community");
  });
});

describe("sections", () => {
  it("files detail pages under Library", () => {
    expect(sectionOf({ k: "album", id: 1 })).toBe("library");
    expect(sectionOf({ k: "stations", live: 2 })).toBe("stations");
    expect(sectionView("library")).toEqual({ k: "library", genre: 0 });
  });
});

describe("contribute paths", () => {
  it("round-trips the chosen path and ignores unknown ones", () => {
    expect(viewToPath({ k: "contribute", path: "artist" })).toBe("/contribute/artist");
    expect(pathToView("/contribute/claim")).toEqual({ k: "contribute", path: "claim" });
    expect(pathToView("/contribute/nope")).toEqual({ k: "contribute" });
    expect(pathToView("#/search")).toEqual({ k: "library", genre: 0 });
    expect(pathToView("#/saved")).toEqual({ k: "me" });
  });
});
