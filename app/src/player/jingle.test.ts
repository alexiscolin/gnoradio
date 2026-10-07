import { describe, expect, it } from "vitest";
import { jingleURL, topOfHour } from "./jingle";

describe("jingleURL", () => {
  it("names a station's file", () => {
    expect(jingleURL("Main")).toBe("/jingles/main.mp3");
    expect(jingleURL("R&B & Soul")).toBe("/jingles/rnb-and-soul.mp3");
    expect(jingleURL("Lo-fi Beats")).toBe("/jingles/lofi-beats.mp3");
    expect(jingleURL("Listeners' choice")).toBe("/jingles/listeners-choice.mp3");
    expect(jingleURL("Hip-hop & Rap")).toBe("/jingles/hip-hop-and-rap.mp3");
  });
  it("matches Main's jingle to the genre on air", () => {
    expect(jingleURL("Main", "House")).toBe("/jingles/main-3.mp3");
    expect(jingleURL("Main", "Ambient")).toBe("/jingles/main-1.mp3");
    expect(jingleURL("Main", "Rock & Indie")).toBe("/jingles/main.mp3");
    expect(jingleURL("Main")).toBe("/jingles/main.mp3");
  });
});

describe("topOfHour", () => {
  const H = 1_800_000_000 - (1_800_000_000 % 3600); // a whole hour
  const entries = [{ start: H - 200 }, { start: H + 40 }, { start: H + 250 }];
  it("finds the first track change after the hour, in its first seconds only", () => {
    expect(topOfHour(entries, H + 41)?.start).toBe(H + 40);
    expect(topOfHour(entries, H + 30)).toBeUndefined(); // not yet
    expect(topOfHour(entries, H + 60)).toBeUndefined(); // too late, missed
    expect(topOfHour(entries, H + 251)).toBeUndefined(); // the second change of the hour is not it
  });
});
