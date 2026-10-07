import { describe, expect, it } from "vitest";
import { pickBlock } from "../components/PickNext";
import {
  type TrackDraft, artistProblems, formatSplits, mediaProblem, parseClock, playlistProblems, reportProblems,
  sha256Hex, splitsProblem, trackProblems, validName, validText,
} from "./rules";

const ME = "g1jg8mtutu9khhfwc4nxmuhcpftf0pajdhfvsqf5";
const OTHER = "g1y2tswmrtlany2ffmpyc0uyunk4gt4gv8gtf736";
const SHA = "9dcf7f71d758161a78e786fb13f316657bd748cb747d97c94c30fa561f012533";

const draft: TrackDraft = {
  title: "Neon Rivers", genre: 2, duration: "4:02", license: "CC-BY-4.0", cmo: "none", credits: "",
  audio: `ipfs://${"b".repeat(59)}`, audioSha: "", cover: "", coverSha: "", splits: [], rights: true,
};

describe("text rules mirror the realm", () => {
  it("validText accepts letters in any script and the allowed punctuation", () => {
    expect(validText("Minuit sur le Rhône, vol. 2 - live!", 1, 64)).toBe(true);
    expect(validText("東京 Night", 1, 64)).toBe(true);
    expect(validText('"Quoted"', 1, 64)).toBe(false);
    expect(validText("(2022 Remaster)", 1, 64)).toBe(false);
    expect(validText("", 1, 64)).toBe(false);
    expect(validText("x".repeat(65), 1, 64)).toBe(false);
  });
  it("validName keeps artist names Latin, without double or edge spaces", () => {
    expect(validName("Léa Kosmos")).toBe(true);
    expect(validName("Simon & Garfunkel")).toBe(true);
    expect(validName("Daft  Punk")).toBe(false);
    expect(validName(" Daft Punk")).toBe(false);
    expect(validName("東京")).toBe(false);
    expect(validName("A")).toBe(false);
  });
  it("parseClock reads m:ss and plain seconds", () => {
    expect(parseClock("3:42")).toBe(222);
    expect(parseClock("125")).toBe(125);
    expect(parseClock("3:7")).toBeUndefined();
    expect(parseClock("3:60")).toBeUndefined();
    expect(parseClock("1:02:03")).toBeUndefined();
  });
});

describe("media", () => {
  it("accepts ipfs, ar and audius, and wants a sha256 over https", () => {
    expect(mediaProblem("Audio", `ipfs://${"b".repeat(59)}`, "", true)).toBe("");
    expect(mediaProblem("Audio", `ar://${"a".repeat(43)}`, "", true)).toBe("");
    expect(mediaProblem("Audio", "audius:x5dg3", "", true)).toBe("");
    expect(mediaProblem("Cover", "audius:x5dg3", "", false)).toMatch(/only valid for audio/);
    expect(mediaProblem("Audio", "https://archive.org/a.mp3", "", true)).toMatch(/needs the file's sha256/);
    expect(mediaProblem("Audio", "https://archive.org/a.mp3", SHA, true, true)).toBe("");
    expect(mediaProblem("Audio", "https://evil.example/a.mp3", SHA, true, false)).toMatch(/not allowed/);
    expect(mediaProblem("Audio", "http://archive.org/a.mp3", SHA, true)).toMatch(/must be ipfs/);
    expect(mediaProblem("Audio", `ipfs://${"b".repeat(59)}`, "XYZ", true)).toMatch(/64 hex/);
  });
});

describe("splits", () => {
  it("allows up to 4 collaborators and 90% in total, never yourself", () => {
    expect(splitsProblem([{ to: OTHER, pct: "30" }], ME)).toBe("");
    expect(splitsProblem([{ to: ME, pct: "30" }], ME)).toMatch(/already receive/);
    expect(splitsProblem([{ to: OTHER, pct: "95" }], ME)).toMatch(/between 1 and 90/);
    expect(splitsProblem([{ to: OTHER, pct: "50" }, { to: "g1abc", pct: "10" }], ME)).toMatch(/g1/);
    expect(splitsProblem([{ to: OTHER, pct: "30" }, { to: OTHER, pct: "10" }], ME)).toMatch(/once/);
    expect(formatSplits([{ to: OTHER, pct: "30%" }, { to: "", pct: "" }])).toBe(`${OTHER}:30`);
  });
});

describe("forms", () => {
  it("a complete track draft is ready to sign", () => {
    expect(trackProblems(draft, ME)).toEqual([]);
  });
  it("lists every problem of a bad draft", () => {
    const bad = trackProblems({ ...draft, title: "", genre: 0, duration: "0:05", license: "MIT", cmo: "sacem-nc", audio: "", rights: false }, ME);
    expect(bad.length).toBeGreaterThanOrEqual(6);
    expect(bad.join(" ")).toMatch(/rights/);
  });
  it("checks artist, playlist and report inputs", () => {
    expect(artistProblems("Lea Kosmos", "Night synthwave.")).toEqual([]);
    expect(artistProblems("Daft  Punk", "")).toHaveLength(1);
    expect(playlistProblems("Late Night", [1, 2])).toEqual([]);
    expect(playlistProblems("Late Night", [1, 1])).toContain("Each track once");
    expect(reportProblems("claim: https://audius.co/attlas")).toEqual([]);
    expect(reportProblems("claim: https://example.org/?a=1")).toHaveLength(1);
  });
});

describe("sha256Hex", () => {
  it("hashes bytes like sha256sum", async () => {
    const bytes = new TextEncoder().encode("abc");
    await expect(sha256Hex(bytes.buffer)).resolves.toBe("ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad");
  });
});

describe("pickBlock", () => {
  const now = 1_800_000_000;
  it("lets a wallet pick when nothing blocks it", () => {
    expect(pickBlock([{ start: now - 60, end: now + 120, queued: false, by: "" }], now, ME)).toBe("");
  });
  it("says when the wallet can pick again", () => {
    const e = [{ start: now - 600, end: now - 400, queued: true, by: ME }];
    expect(pickBlock(e, now, ME)).toMatch(/pick again at/);
  });
  it("sees a pick already waiting", () => {
    expect(pickBlock([{ start: now + 60, end: now + 200, queued: true, by: ME }], now, ME)).toMatch(/already waiting/);
  });
  it("reports the 2 hour cap", () => {
    const e = Array.from({ length: 10 }, (_, i) => ({ start: now + i * 800, end: now + (i + 1) * 800, queued: true, by: OTHER }));
    expect(pickBlock(e, now, ME)).toMatch(/Queue full until/);
  });
});
