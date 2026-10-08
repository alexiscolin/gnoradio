import { cleanup, fireEvent, render, screen } from "@testing-library/react";
import { afterEach, describe, expect, it, vi } from "vitest";
import type { Catalog } from "../lib/types";
import type { Actions } from "../player/useActions";
import type { Player } from "../player/usePlayer";
import { NowPlaying } from "./NowPlaying";

vi.mock("../lib/names", () => ({ useNames: () => (a: string) => a }));

afterEach(cleanup);
vi.stubGlobal("matchMedia", (q: string) => ({ matches: false, media: q, addEventListener: () => undefined, removeEventListener: () => undefined }));

const NOW = 1_800_000_000;
const track = { id: 1, title: "Song", artist: 1, artistName: "A", genre: 1, duration: 300, audio: "https://media.example/1.mp3", cover: "" };
const cat = {
  tracks: [track], byId: new Map([[1, track]]), artists: new Map([[1, { id: 1, owner: "g1owner" }]]),
  stations: [{ id: 0, name: "Main", genre: 0 }], genres: [{ id: 1, name: "Pop" }], admin: "g1admin",
} as unknown as Catalog;
const player = {
  audio: new Audio(), mode: "live", station: 0, current: 1, playing: true, buffering: false, error: "", synced: true,
  chainNow: () => NOW, entries: [{ track: 1, title: "Song", start: NOW - 10, end: NOW + 100, offset: 0, queued: true, by: "g1someone", note: "for you" }],
} as unknown as Player;
const actions = { wallet: { state: { status: "disconnected" } }, pending: "", say: () => undefined, liked: new Set() } as unknown as Actions;

describe("NowPlaying dedication", () => {
  it("can be held still by a tap or key, not only while a finger is down", () => {
    render(<NowPlaying cat={cat} player={player} actions={actions} saved={{ has: () => false, toggle: () => undefined }} open={false} onClose={() => undefined} go={() => undefined} openPick={() => undefined} openSupport={() => undefined} />);
    const hold = screen.getByRole("button", { name: "Hold the dedication still" });
    expect(hold.getAttribute("aria-pressed")).toBe("false");
    fireEvent.click(hold);
    expect(hold.getAttribute("aria-pressed")).toBe("true");
    expect(document.querySelector(".dedic.still")).not.toBeNull();
    fireEvent.click(hold);
    expect(document.querySelector(".dedic.still")).toBeNull();
  });
});
