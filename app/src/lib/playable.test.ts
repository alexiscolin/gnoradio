import { act, cleanup, render, renderHook, screen } from "@testing-library/react";
import { createElement } from "react";
import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";
import { PlayButton } from "../components/PlayButton";
import { PROBE_MS, UNAVAILABLE, check, isDead, markDead, probe, resetPlayable, status, usePlayable } from "./playable";

// A fake <audio>: each URL answers as the test says, after a tick.
let answer: (url: string) => "meta" | "error" | "hang" = () => "meta";
class FakeAudio {
  preload = "";
  onloadedmetadata: (() => void) | null = null;
  onerror: (() => void) | null = null;
  set src(url: string) {
    const a = answer(url);
    if (a === "hang") return;
    setTimeout(() => { (a === "meta" ? this.onloadedmetadata : this.onerror)?.(); }, 1);
  }
  static loads = 0;
  removeAttribute() { /* nothing loaded */ }
  load() { FakeAudio.loads++; }
}

const ipfs = (id: number) => ({ id, audio: "ipfs://bafyexample" });
const https = (id: number) => ({ id, audio: `https://media.example/${String(id)}.mp3` });

beforeEach(() => {
  vi.stubGlobal("Audio", FakeAudio);
  resetPlayable();
  FakeAudio.loads = 0;
});
afterEach(() => {
  cleanup();
  vi.useRealTimers();
  vi.unstubAllGlobals();
  answer = () => "meta";
});

describe("probe", () => {
  it("is true once one source loads its metadata, trying the gateways in order", async () => {
    const tried: string[] = [];
    answer = (u) => { tried.push(u); return tried.length < 3 ? "error" : "meta"; };
    expect(await probe(ipfs(1))).toBe(true);
    expect(tried).toHaveLength(3);
  });
  it("is false when every source errors", async () => {
    answer = () => "error";
    expect(await probe(ipfs(1))).toBe(false);
  });
  it("gives up on a source that never answers", async () => {
    vi.useFakeTimers();
    answer = () => "hang";
    const p = probe(https(1));
    await vi.advanceTimersByTimeAsync(PROBE_MS);
    expect(await p).toBeUndefined();
    expect(FakeAudio.loads).toBe(1);
  });
  it("is dead only when every source errors, not when one just times out", async () => {
    vi.useFakeTimers();
    answer = (u) => (u.includes("ipfs.io") ? "hang" : "error");
    const p = probe(ipfs(1));
    await vi.advanceTimersByTimeAsync(PROBE_MS + 10);
    expect(await p).toBeUndefined();
    answer = () => "hang";
    check(https(8));
    await vi.advanceTimersByTimeAsync(PROBE_MS + 10);
    expect(status(https(8))).toBeUndefined();
  });
});

describe("status", () => {
  it("is dead with no source at all, unknown until probed", () => {
    expect(status({ id: 1, audio: "" })).toBe("dead");
    expect(status(https(2))).toBeUndefined();
  });
  it("keeps a dead track 6 hours and a working one a week", async () => {
    vi.useFakeTimers();
    markDead(1);
    answer = () => "meta";
    check(https(2));
    await vi.advanceTimersByTimeAsync(10);
    expect(status(https(1))).toBe("dead");
    expect(status(https(2))).toBe("ok");
    await vi.advanceTimersByTimeAsync(6 * 3600_000 + 1);
    expect(status(https(1))).toBeUndefined();
    expect(status(https(2))).toBe("ok");
    await vi.advanceTimersByTimeAsync(7 * 86400_000);
    expect(status(https(2))).toBeUndefined();
  });
  it("tells every subscriber when the player reports a dead track", () => {
    const { result } = renderHook(() => usePlayable([https(3)]));
    expect(result.current.allDead).toBe(false);
    act(() => { markDead(3); });
    expect(result.current.allDead).toBe(true);
    expect(isDead(https(3))).toBe(true);
  });
});

describe("PlayButton", () => {
  it("greys out when none of its tracks plays, after its own probe", async () => {
    answer = () => "error";
    render(createElement(PlayButton, { tracks: [https(4)], onClick: () => undefined }));
    const b = await screen.findByRole<HTMLButtonElement>("button", { name: UNAVAILABLE });
    expect(b.disabled).toBe(true);
  });
  it("stays on while one track still plays", () => {
    markDead(5);
    render(createElement(PlayButton, { tracks: [https(5), https(6)], onClick: () => undefined }));
    expect(screen.getByRole<HTMLButtonElement>("button", { name: "Play" }).disabled).toBe(false);
  });
});
