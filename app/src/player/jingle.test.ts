import { afterEach, describe, expect, it, vi } from "vitest";
import { jingleURL, STALL_MS, tail, topOfHour } from "./jingle";

describe("jingleURL", () => {
  it("names a station's file", () => {
    expect(jingleURL("Main")).toBe("https://archive.org/download/gnoradio-jingles/main.mp3");
    expect(jingleURL("R&B & Soul")).toBe("https://archive.org/download/gnoradio-jingles/rnb-and-soul.mp3");
    expect(jingleURL("Lo-fi Beats")).toBe("https://archive.org/download/gnoradio-jingles/lofi-beats.mp3");
    expect(jingleURL("Listeners' choice")).toBe("https://archive.org/download/gnoradio-jingles/listeners-choice.mp3");
    expect(jingleURL("Hip-hop & Rap")).toBe("https://archive.org/download/gnoradio-jingles/hip-hop-and-rap.mp3");
  });
  it("matches Main's jingle to the genre on air", () => {
    expect(jingleURL("Main", "House")).toBe("https://archive.org/download/gnoradio-jingles/main-3.mp3");
    expect(jingleURL("Main", "Ambient")).toBe("https://archive.org/download/gnoradio-jingles/main-1.mp3");
    expect(jingleURL("Main", "Rock & Indie")).toBe("https://archive.org/download/gnoradio-jingles/main.mp3");
    expect(jingleURL("Main")).toBe("https://archive.org/download/gnoradio-jingles/main.mp3");
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

describe("tail", () => {
  afterEach(() => { vi.useRealTimers(); });
  const jingle = (props: Partial<HTMLAudioElement>) => Object.assign(new EventTarget(), { ended: false, error: null, duration: NaN, currentTime: 0 }, props) as unknown as HTMLAudioElement;

  it("gives up on a jingle that stalls, so the station is not held at volume 0", async () => {
    vi.useFakeTimers();
    const done = vi.fn();
    void tail(jingle({}), 1).then(done);
    await vi.advanceTimersByTimeAsync(STALL_MS - 100);
    expect(done).not.toHaveBeenCalled();
    await vi.advanceTimersByTimeAsync(200);
    expect(done).toHaveBeenCalledTimes(1);
  });

  it("keeps waiting while the jingle makes progress, and ends near its end", async () => {
    vi.useFakeTimers();
    const j = jingle({ duration: 10 });
    const done = vi.fn();
    void tail(j, 1).then(done);
    for (let t = 1; t <= 8; t++) { await vi.advanceTimersByTimeAsync(2_000); (j as { currentTime: number }).currentTime = t; j.dispatchEvent(new Event("timeupdate")); }
    expect(done).not.toHaveBeenCalled(); // 16 s passed, and it kept moving
    (j as { currentTime: number }).currentTime = 9;
    j.dispatchEvent(new Event("timeupdate"));
    await vi.advanceTimersByTimeAsync(0);
    expect(done).toHaveBeenCalledTimes(1);
  });
});
