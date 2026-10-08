import { act, renderHook } from "@testing-library/react";
import { afterEach, describe, expect, it, vi } from "vitest";
import type { Catalog, Schedule } from "../lib/types";
import { nextSkew, usePlayer } from "./usePlayer";
import { isDead, markDead, resetPlayable } from "../lib/playable";

// The chain's schedule, read at each sync: a pick (track 2) cut the track on air (track 1) at T0 + 5.
const T0 = Math.floor(Date.now() / 1000);
const schedule = (): Schedule => ({
  station: 0,
  now: Math.floor(Date.now() / 1000),
  entries: [
    { track: 1, title: "On air", start: T0 - 100, end: T0 + 5, offset: 0, queued: false, by: "", note: "" },
    { track: 2, title: "The pick", start: T0 + 5, end: T0 + 200, offset: 0, queued: true, by: "g1someone", note: "" },
  ],
});
// A slot nothing can play leaves a gap: the next entry starts at T0 + 3.
const gapped = (): Schedule => ({
  station: 0,
  now: Math.floor(Date.now() / 1000),
  entries: [{ track: 2, title: "After the gap", start: T0 + 3, end: T0 + 200, offset: 0, queued: false, by: "", note: "" }],
});
let next = schedule;
const loadSchedule = vi.fn(() => Promise.resolve(next()));
vi.mock("../lib/catalog", () => ({
  loadSchedule: () => loadSchedule(),
  audioURLs: (t: { audio: string; alt?: string }) => (t.alt ? [t.audio, t.alt] : [t.audio]),
}));

afterEach(() => {
  vi.useRealTimers();
  loadSchedule.mockClear();
  next = schedule;
});

const cat = {
  byId: new Map([1, 2].map((id) => [id, { id, audio: `https://media.example/${String(id)}.mp3`, duration: 300 }])),
  tracks: [], stations: [{ id: 0, name: "Main", now: { track: 1, offset: 0 } }], genres: [],
} as unknown as Catalog;

describe("usePlayer live", () => {
  it("switches every listener at the end of the entry on air, not only the picker", async () => {
    vi.useFakeTimers({ toFake: ["setTimeout", "clearTimeout", "setInterval", "clearInterval", "Date"] });
    vi.spyOn(HTMLMediaElement.prototype, "play").mockResolvedValue(undefined);
    vi.spyOn(HTMLMediaElement.prototype, "pause").mockImplementation(() => undefined);
    vi.spyOn(HTMLMediaElement.prototype, "load").mockImplementation(() => undefined);
    const { result } = renderHook(() => usePlayer(cat));
    await act(() => vi.advanceTimersByTimeAsync(100));
    expect(result.current.current).toBe(1);
    expect(loadSchedule).toHaveBeenCalledTimes(1);
    // The old file is far from its end (no "ended" event): only the entry's end can switch it.
    await act(() => vi.advanceTimersByTimeAsync(6000));
    expect(loadSchedule).toHaveBeenCalledTimes(2);
    expect(result.current.current).toBe(2);
  });

  it("waits for the first entry's start instead of playing it early", async () => {
    vi.useFakeTimers({ toFake: ["setTimeout", "clearTimeout", "setInterval", "clearInterval", "Date"] });
    vi.spyOn(HTMLMediaElement.prototype, "play").mockResolvedValue(undefined);
    vi.spyOn(HTMLMediaElement.prototype, "pause").mockImplementation(() => undefined);
    vi.spyOn(HTMLMediaElement.prototype, "load").mockImplementation(() => undefined);
    next = gapped;
    const { result } = renderHook(() => usePlayer(cat));
    await act(() => vi.advanceTimersByTimeAsync(100));
    expect(result.current.current).toBe(0);
    await act(() => vi.advanceTimersByTimeAsync(4000));
    expect(result.current.current).toBe(2);
  });
});

describe("usePlayer live, review fixes", () => {
  const fake = () => {
    vi.useFakeTimers({ toFake: ["setTimeout", "clearTimeout", "setInterval", "clearInterval", "Date"] });
    vi.spyOn(HTMLMediaElement.prototype, "play").mockResolvedValue(undefined);
    vi.spyOn(HTMLMediaElement.prototype, "pause").mockImplementation(() => undefined);
    vi.spyOn(HTMLMediaElement.prototype, "load").mockImplementation(() => undefined);
  };
  it("a paused tab shows what is on air without downloading it", async () => {
    fake();
    const { result } = renderHook(() => usePlayer(cat));
    await act(() => vi.advanceTimersByTimeAsync(100));
    expect(result.current.current).toBe(1);
    expect(result.current.audio.getAttribute("src")).toBeNull();
    expect(result.current.synced).toBe(true);
  });
  it("asks for a scheduled track the catalog does not hold, then plays it once it arrives", async () => {
    fake();
    const onMissing = vi.fn();
    const only1 = { ...cat, byId: new Map([[1, cat.byId.get(1)]]) } as unknown as Catalog;
    const { result, rerender } = renderHook(({ c }) => usePlayer(c, onMissing), { initialProps: { c: only1 } });
    await act(() => vi.advanceTimersByTimeAsync(6000));
    expect(result.current.current).toBe(2);
    expect(onMissing).toHaveBeenCalledWith(2);
    rerender({ c: cat });
    await act(() => vi.advanceTimersByTimeAsync(100));
    expect(loadSchedule.mock.calls.length).toBeGreaterThanOrEqual(3); // re-synced once the track is known
  });
});

describe("usePlayer live, player fixes", () => {
  const fake = (now?: number) => {
    vi.useFakeTimers({ toFake: ["setTimeout", "clearTimeout", "setInterval", "clearInterval", "Date"], ...(now ? { now } : {}) });
    vi.spyOn(HTMLMediaElement.prototype, "play").mockResolvedValue(undefined);
    vi.spyOn(HTMLMediaElement.prototype, "pause").mockImplementation(() => undefined);
    vi.spyOn(HTMLMediaElement.prototype, "load").mockImplementation(() => undefined);
  };
  it("a file that ended before its slot does not silence the radio at the next entry", async () => {
    fake();
    const { result } = renderHook(() => usePlayer(cat));
    await act(() => vi.advanceTimersByTimeAsync(100));
    act(() => { result.current.toggle(); });
    expect(result.current.audio.src).toContain("/1.mp3");
    // An ended element is paused too: the end timer must still load the next entry.
    Object.defineProperty(result.current.audio, "ended", { value: true, configurable: true });
    await act(() => vi.advanceTimersByTimeAsync(6000));
    expect(result.current.audio.src).toContain("/2.mp3");
  });
  it("Listen loads the track on air, not the old file a paused tab only named", async () => {
    fake();
    const { result } = renderHook(() => usePlayer(cat));
    await act(() => vi.advanceTimersByTimeAsync(100));
    act(() => { result.current.toggle(); });
    expect(result.current.audio.src).toContain("/1.mp3");
    await act(() => vi.advanceTimersByTimeAsync(6000)); // paused: current moves to 2, the file stays 1
    expect(result.current.current).toBe(2);
    expect(result.current.audio.src).toContain("/1.mp3");
    act(() => { result.current.goLive(0); });
    expect(result.current.audio.src).toContain("/2.mp3");
  });
  it("resuming the track on air after a pause seeks to the live place first", async () => {
    fake();
    const { result } = renderHook(() => usePlayer(cat));
    await act(() => vi.advanceTimersByTimeAsync(100));
    act(() => { result.current.toggle(); });
    expect(result.current.audio.src).toContain("/1.mp3");
    act(() => { result.current.toggle(); }); // paused, at the place it stopped
    result.current.audio.currentTime = 1;
    await act(() => vi.advanceTimersByTimeAsync(2000));
    act(() => { result.current.goLive(0); });
    expect(result.current.audio.src).toContain("/1.mp3");
    expect(result.current.audio.currentTime).toBeGreaterThan(95); // T0 - 100 start, about 102 s in
  });
  it("a tune-in jingle replaced without a new one gives the volume back", async () => {
    fake();
    const { result } = renderHook(() => usePlayer(cat));
    await act(() => vi.advanceTimersByTimeAsync(100));
    act(() => { result.current.goLive(0); });
    expect(result.current.audio.volume).toBe(0); // under the jingle
    act(() => { result.current.toggleMute(); }); // no jingle for a muted tune-in
    act(() => { result.current.goLive(0); });
    expect(result.current.audio.volume).toBe(1);
  });
  it("the next gateway starts at the chain's place, not the failed element's", async () => {
    fake();
    const alt = { ...cat, byId: new Map([[1, { id: 1, audio: "https://media.example/1.mp3", alt: "https://alt.example/1.mp3", duration: 300 }], [2, cat.byId.get(2)]] as never) } as unknown as Catalog;
    const { result } = renderHook(() => usePlayer(alt));
    await act(() => vi.advanceTimersByTimeAsync(100));
    act(() => { result.current.toggle(); });
    await act(() => vi.advanceTimersByTimeAsync(10)); // entries read: track 1 started 100 s ago
    const a = result.current.audio;
    act(() => { a.dispatchEvent(new Event("error")); }); // first gateway, no metadata: currentTime 0
    expect(a.src).toContain("alt.example");
    act(() => { a.dispatchEvent(new Event("loadedmetadata")); });
    expect(a.currentTime).toBeGreaterThan(90);
  });
  it("leaving the radio stops the hourly jingle", async () => {
    const H = Math.floor(Date.now() / 3600_000) * 3600;
    fake((H + 1) * 1000);
    next = () => ({
      station: 0,
      now: Date.now() / 1000,
      entries: [
        { track: 1, title: "A", start: H - 100, end: H, offset: 0, queued: false, by: "", note: "" },
        { track: 2, title: "B", start: H, end: H + 200, offset: 0, queued: false, by: "", note: "" },
      ],
    });
    const paused: HTMLMediaElement[] = [];
    vi.spyOn(HTMLMediaElement.prototype, "pause").mockImplementation(function (this: HTMLMediaElement) { paused.push(this); });
    const { result } = renderHook(() => usePlayer(cat));
    await act(() => vi.advanceTimersByTimeAsync(100));
    act(() => { result.current.setVolume(0); }); // no tune-in jingle, so none to mask the hourly one
    act(() => { result.current.toggle(); });
    await act(() => vi.advanceTimersByTimeAsync(300));
    await act(() => vi.advanceTimersByTimeAsync(1100)); // the hourly tick (every second) starts its jingle
    paused.length = 0;
    act(() => { result.current.playList([1], 0); });
    expect(paused.some((a) => a.src.includes("/gnoradio-jingles/"))).toBe(true);
  });
});

describe("usePlayer review fixes", () => {
  const fake = () => {
    vi.useFakeTimers({ toFake: ["setTimeout", "clearTimeout", "setInterval", "clearInterval", "Date"] });
    vi.spyOn(HTMLMediaElement.prototype, "play").mockResolvedValue(undefined);
    vi.spyOn(HTMLMediaElement.prototype, "pause").mockImplementation(() => undefined);
    vi.spyOn(HTMLMediaElement.prototype, "load").mockImplementation(() => undefined);
  };
  it("marks the file that failed dead, not the track a paused tab only named", async () => {
    fake();
    resetPlayable();
    const { result } = renderHook(() => usePlayer(cat));
    await act(() => vi.advanceTimersByTimeAsync(100));
    act(() => { result.current.toggle(); });
    await act(() => vi.advanceTimersByTimeAsync(6000)); // current moves to 2, the element still holds 1
    expect(result.current.current).toBe(2);
    expect(result.current.audio.src).toContain("/1.mp3");
    act(() => { result.current.audio.dispatchEvent(new Event("error")); }); // the radio's silent retry
    act(() => { result.current.audio.dispatchEvent(new Event("error")); });
    expect(isDead(cat.byId.get(1))).toBe(true);
    expect(isDead(cat.byId.get(2))).toBe(false);
  });
  it("tuning in from the library loads the station's track, never resumes the library file", async () => {
    fake();
    resetPlayable();
    const two = { ...cat, stations: [{ id: 0, name: "Main", now: { track: 2, offset: 0 } }] } as unknown as Catalog;
    const { result } = renderHook(() => usePlayer(two));
    await act(() => vi.advanceTimersByTimeAsync(100));
    act(() => { result.current.playList([1], 0); });
    expect(result.current.audio.src).toContain("/1.mp3");
    act(() => { result.current.goLive(0); });
    expect(result.current.audio.src).toContain("/2.mp3");
  });
});

describe("usePlayer dead tracks", () => {
  it("marks a track dead only when no source ever answered for it", () => {
    vi.spyOn(HTMLMediaElement.prototype, "play").mockResolvedValue(undefined);
    vi.spyOn(HTMLMediaElement.prototype, "pause").mockImplementation(() => undefined);
    resetPlayable();
    const one = { ...cat, byId: new Map([[7, { id: 7, audio: "https://media.example/7.mp3", duration: 300 }], [8, { id: 8, audio: "https://media.example/8.mp3", duration: 300 }]]) } as unknown as Catalog;
    const { result } = renderHook(() => usePlayer(one));
    act(() => { result.current.playList([7], 0); });
    act(() => { result.current.audio.dispatchEvent(new Event("loadedmetadata")); result.current.audio.dispatchEvent(new Event("error")); });
    expect(isDead(one.byId.get(7))).toBe(false); // it answered, then the network dropped
    act(() => { result.current.playList([8], 0); });
    act(() => { result.current.audio.dispatchEvent(new Event("error")); });
    expect(isDead(one.byId.get(8))).toBe(true);
  });
  it("keeps what a source answered when the same file is loaded again", () => {
    vi.spyOn(HTMLMediaElement.prototype, "play").mockResolvedValue(undefined);
    vi.spyOn(HTMLMediaElement.prototype, "pause").mockImplementation(() => undefined);
    resetPlayable();
    const one = { ...cat, byId: new Map([[7, { id: 7, audio: "https://media.example/7.mp3", duration: 300 }]]) } as unknown as Catalog;
    const { result } = renderHook(() => usePlayer(one));
    act(() => { result.current.playList([7], 0); });
    act(() => { result.current.audio.dispatchEvent(new Event("loadedmetadata")); });
    act(() => { result.current.playList([7], 0); }); // same src: no new loadedmetadata
    act(() => { result.current.audio.dispatchEvent(new Event("error")); });
    expect(isDead(one.byId.get(7))).toBe(false);
  });
});

describe("nextSkew", () => {
  it("keeps the max of the recent samples, so the skew can come down", () => {
    let w: number[] = [];
    for (const x of [2, 1.5, 1]) w = nextSkew(w, x);
    expect(Math.max(...w)).toBe(2); // a block's lag: the largest is the closest
    for (let i = 0; i < 6; i++) w = nextSkew(w, 1);
    expect(Math.max(...w)).toBe(1); // the old high sample left the window
  });
  it("restarts on a jump of the local clock", () => {
    expect(nextSkew([120, 121], 1)).toEqual([1]);
  });
});

describe("usePlayer library", () => {
  it("plays a list without its dead tracks, from the first live one", () => {
    vi.spyOn(HTMLMediaElement.prototype, "play").mockResolvedValue(undefined);
    resetPlayable();
    const lib = { ...cat, byId: new Map([1, 2, 3].map((id) => [id, { id, audio: `https://media.example/${String(id)}.mp3`, duration: 300 }])) } as unknown as Catalog;
    markDead(1);
    markDead(3);
    const { result } = renderHook(() => usePlayer(lib));
    act(() => { result.current.playList([1, 2, 3], 0); });
    expect(result.current.current).toBe(2);
    expect(result.current.queue).toEqual([2]);
    markDead(2);
    act(() => { result.current.playList([2], 0); });
    expect(result.current.queue).toEqual([2]); // nothing live: the call plays nothing new
  });
});
