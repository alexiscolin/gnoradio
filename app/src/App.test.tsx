import { render } from "@testing-library/react";
import { describe, expect, it, vi } from "vitest";
import App from "./App";

// A first visit whose full catalog load never finishes in this test.
const loadCatalog = vi.fn(() => new Promise<never>(() => undefined));
const loadFees = vi.hoisted(() => vi.fn<() => Promise<{ support: boolean; ticketFee: boolean }>>(() => Promise.reject(new Error("rpc down"))));
let onMissing: ((id: number) => void) | undefined;
vi.mock("./lib/catalog", async (orig) => ({ ...(await orig<object>()), loadCatalog: () => loadCatalog() }));
vi.mock("./lib/community", async (orig) => ({ ...(await orig<object>()), loadActivity: () => Promise.resolve([]), loadSupport: () => new Promise(() => undefined), loadFees: () => loadFees() }));
vi.mock("./player/usePlayer", () => ({
  usePlayer: (_cat: unknown, m: (id: number) => void) => {
    onMissing = m;
    return { toggle: () => undefined, toggleMute: () => undefined, nudge: () => undefined, resync: () => undefined, audio: new Audio(), mode: "live", station: 0, current: 0, entries: [], queue: [], playing: false, error: "", synced: false };
  },
}));

describe("App", () => {
  it("a track the radio names does not restart the first catalog load", () => {
    render(<App />);
    expect(loadCatalog).toHaveBeenCalledTimes(1);
    onMissing?.(7);
    expect(loadCatalog).toHaveBeenCalledTimes(1);
  });

  it("reads the fees on mount, not on every pulse", () => {
    vi.useFakeTimers();
    loadFees.mockReset();
    loadFees.mockImplementation(() => Promise.resolve({ support: false, ticketFee: false }));
    render(<App />);
    expect(loadFees).toHaveBeenCalledTimes(1);
    vi.advanceTimersByTime(130_000);
    expect(loadFees).toHaveBeenCalledTimes(1);
    vi.useRealTimers();
  });

  it("retries a failed fees read after a pause, doubling, and stops once it answers", async () => {
    vi.useFakeTimers();
    loadFees.mockReset();
    loadFees.mockImplementation(() => Promise.reject(new Error("rpc down")));
    render(<App />);
    expect(loadFees).toHaveBeenCalledTimes(1);
    await vi.advanceTimersByTimeAsync(5_100);
    expect(loadFees).toHaveBeenCalledTimes(2);
    await vi.advanceTimersByTimeAsync(5_100);
    expect(loadFees).toHaveBeenCalledTimes(2); // the pause doubled: 10 s
    loadFees.mockImplementation(() => Promise.resolve({ support: true, ticketFee: false }));
    await vi.advanceTimersByTimeAsync(5_100);
    expect(loadFees).toHaveBeenCalledTimes(3);
    await vi.advanceTimersByTimeAsync(120_000);
    expect(loadFees).toHaveBeenCalledTimes(3);
    vi.useRealTimers();
  });
});
