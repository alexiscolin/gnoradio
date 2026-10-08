import { describe, expect, it } from "vitest";
import { daypart, favouriteMin, inMinutes, nextSet, pickNote, pickerOf, setName, shortBio, stationLine, why } from "./onair";
import type { ScheduleEntry } from "./types";

const H = 3600;
const e = (track: number, start: number, queued = false, by = ""): ScheduleEntry => ({ track, title: "", start, end: start + 200, offset: 0, queued, by, note: undefined });

describe("onair", () => {
  it("names sets by UTC daypart and genre", () => {
    expect(daypart(0)).toBe("Night");
    expect(daypart(4 * H)).toBe("Early morning");
    expect(daypart(16 * H)).toBe("Drive time");
    expect(daypart(23 * H + 59)).toBe("Late night");
    expect(setName("Ambient", 22 * H)).toBe("Late-night Ambient set");
    expect(setName("Techno", 86400 + 19 * H)).toBe("Evening Techno set");
    expect(setName("", 10 * H)).toBe("Midday set");
  });

  it("gives one reason, the most meaningful", () => {
    const who = (a: string) => `@${a}`;
    const now = 100 * 86400;
    const fresh = { created: now - 86400, likes: 50 };
    expect(why(fresh, { queued: true, by: "bob" }, now, 10, who)?.text).toBe("picked by @bob");
    expect(why(fresh, { queued: true, by: "" }, now, 10, who)?.kind).toBe("curator");
    expect(why(fresh, { queued: false, by: "" }, now, 10, who)?.kind).toBe("new");
    expect(why({ created: now - 30 * 86400, likes: 50 }, undefined, now, 10, who)?.kind).toBe("favourite");
    expect(why({ created: now - 30 * 86400, likes: 2 }, undefined, now, 10, who)).toBeNull();
    expect(favouriteMin([{ likes: 1 }])).toBe(3);
    expect(favouriteMin(Array.from({ length: 20 }, (_, i) => ({ likes: i })))).toBe(10);
  });

  it("detects the next set, ignoring picks", () => {
    const genre = (t: number) => Math.floor(t / 10);
    const entries = [e(11, 0), e(12, 200), e(51, 400, true, "g1x"), e(13, 600), e(21, 800), e(22, 1000)];
    expect(nextSet(entries, 450, genre)).toEqual({ genre: 2, at: 800 });
    expect(nextSet(entries, 900, genre)).toBeNull();
    expect(inMinutes(30)).toBe("in 1 min");
    expect(inMinutes(720)).toBe("in 12 min");
  });

  it("shows one line at a time", () => {
    const pick = { kind: "pick" as const, text: "picked by @a" };
    const fav = { kind: "favourite" as const, text: "listener favourite" };
    const next = { kind: "next" as const, text: "Next" };
    const intro = { kind: "intro" as const, text: "Evening Techno set" };
    const artist = { kind: "artist" as const, text: "bio" };
    const base = { why: fav, next, nextIn: 900, intro, artist };
    expect(pickNote(3, base)).toBe(intro);
    expect(pickNote(20, base)).toBe(artist);
    expect(pickNote(60, base)).toBe(fav);
    expect(pickNote(3, { ...base, nextIn: 120 })).toBe(next);
    expect(pickNote(3, { ...base, why: pick, nextIn: 120 })).toBe(pick);
    expect(pickNote(60, { ...base, why: null })).toBeNull();
  });

  it("trims bios and describes stations", () => {
    expect(shortBio("Short. Second sentence.")).toBe("Short.");
    const long = shortBio("A producer from Lyon who makes long evolving pieces with modular synths, field recordings and old tape machines");
    expect(long.length).toBeLessThanOrEqual(91);
    expect(long.endsWith("…")).toBe(true);
    expect(stationLine("Ambient")).toContain("Ambient");
    expect(stationLine("Polka", 30)).toBe("Polka, all day and all night");
  });
  it("shares a tip on air with the listener who picked, not on a sponsored pick or the admin's", () => {
    expect(pickerOf(e(1, 0, true, "g1lea"), "g1admin")).toBe("g1lea");
    expect(pickerOf({ ...e(1, 0, true, "g1lea"), sponsored: 30_000 }, "g1admin")).toBeUndefined();
    expect(pickerOf(e(1, 0, true, "g1admin"), "g1admin")).toBeUndefined();
    expect(pickerOf(e(1, 0, false, ""), "g1admin")).toBeUndefined();
  });
});
