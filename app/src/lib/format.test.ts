import { describe, expect, it } from "vitest";
import { clock, errorMessage, firstNonEmpty, fnv, gnot, hostOf, licenseLabel, licenseURL, shortAddr } from "./format";

describe("format", () => {
  it("formats clocks", () => {
    expect(clock(0)).toBe("0:00");
    expect(clock(65.9)).toBe("1:05");
    expect(clock(-3)).toBe("0:00");
  });
  it("formats GNOT", () => {
    expect(gnot(1_000_000)).toBe("1 GNOT");
    expect(gnot(2_500_000)).toBe("2.5 GNOT");
  });
  it("shortens addresses", () => {
    expect(shortAddr("g1jg8mtutu9khhfwc4nxmuhcpftf0pajdhfvsqf5")).toBe("g1jg8mt…sqf5");
    expect(shortAddr("short")).toBe("short");
  });
  it("links licenses to their text", () => {
    expect(licenseURL("CC-BY-SA-4.0")).toBe("https://creativecommons.org/licenses/by-sa/4.0/");
    expect(licenseURL("CC-BY-3.0-DE")).toBe("https://creativecommons.org/licenses/by/3.0/de/");
    expect(licenseURL("CC0-1.0")).toBe("https://creativecommons.org/publicdomain/zero/1.0/");
    expect(licenseURL("Audius-OML")).toBe("https://openaudiofoundation.org/open-music-license.pdf");
    expect(licenseURL("ALL-RIGHTS-RESERVED")).toBe("");
  });
  it("labels licenses", () => {
    expect(licenseLabel("CC-BY-SA-4.0")).toBe("CC BY SA 4.0");
    expect(licenseLabel("Audius-OML")).toBe("Audius Open Music License");
  });
  it("extracts hosts safely", () => {
    expect(hostOf("https://www.archive.org/details/x")).toBe("archive.org");
    expect(hostOf("not a url")).toBe("source");
  });
  it("matches the realm FNV-1a hash", () => {
    expect(fnv("")).toBe(2166136261);
    expect(fnv("a")).toBe(0xe40c292c);
  });
  it("picks the first non-empty string", () => {
    expect(firstNonEmpty(undefined, "", "b", "c")).toBe("b");
    expect(firstNonEmpty()).toBe("");
  });
  it("turns unknown errors into messages", () => {
    expect(errorMessage(new Error("boom"))).toBe("boom");
    expect(errorMessage("x")).toBe("x");
  });
});
