import { cleanup, fireEvent, render, screen } from "@testing-library/react";
import { useState } from "react";
import { afterEach, describe, expect, it, vi } from "vitest";
import type { Catalog, Schedule, Track } from "../lib/types";
import { PickNext, hhmm } from "./PickNext";

const NOW = 1_800_000_000;
let schedule: Schedule = {
  station: 1,
  now: NOW,
  entries: [
    { track: 1, title: "On Air", start: NOW - 60, end: NOW + 120, offset: 0, queued: false, by: "", note: "" },
    { track: 2, title: "Their Pick", start: NOW + 120, end: NOW + 300, offset: 0, queued: true, by: "g1jg8mtutu9khhfwc4nxmuhcpftf0pajdhfvsqf5", note: "" },
  ],
};
vi.mock("../lib/catalog", () => ({ loadSchedule: () => Promise.resolve(schedule) }));
let picks: { kind: "queue"; by: string; track: number; station: number; start: number; at: number }[] = [];
vi.mock("../lib/community", () => ({ loadPicks: () => Promise.resolve(picks) }));
const noteProblem = vi.fn<(n: string) => Promise<string>>(() => Promise.resolve(""));
vi.mock("../lib/gno", async (orig) => ({ ...(await orig<object>()), noteProblem: (n: string) => noteProblem(n) }));
const ME = "g1u7y667z64x2h7vc6fmpcprgey4ck233jaww9zq";

afterEach(cleanup);

const t = (id: number, title: string, genre: number, artist = 1) => ({ id, title, genre, artist, artistName: "A", duration: 180, audio: "", cover: "" }) as unknown as Track;
const tracks = [t(1, "On Air", 11), t(2, "Their Pick", 11), t(3, "Fresh Ambient", 11, 7), t(4, "Loud Rock", 2), t(5, "Old Ambient", 11)];
const cat = {
  stations: [{ id: 1, name: "Ambient", genre: 11 }],
  tracks,
  byId: new Map(tracks.map((x) => [x.id, x])),
  artists: new Map([[7, { id: 7, owner: "g1owner", verified: true, promo: 10 }]]),
} as unknown as Catalog;

describe("PickNext", () => {
  it("lists only tracks this station can play, minus what is already on", async () => {
    render(<PickNext cat={cat} station={1} onPick={() => undefined} onClose={() => undefined} />);
    expect(await screen.findByText("Fresh Ambient")).toBeTruthy();
    expect(screen.queryByText("Loud Rock")).toBeNull();
    fireEvent.click(screen.getByText("Fresh Ambient"));
    fireEvent.click(screen.getByText("Next · Fresh Ambient"));
    expect(screen.getByText(/after 1 pick/)).toBeTruthy();
  });
  it("selects a track, then says what it earns and pushes it on air in step 2", async () => {
    const onPick = vi.fn();
    render(<PickNext cat={cat} station={1} onPick={onPick} onClose={() => undefined} />);
    expect(screen.getByRole<HTMLButtonElement>("button", { name: "Choose a track" }).disabled).toBe(true);
    fireEvent.click(await screen.findByText("Fresh Ambient"));
    expect(onPick).not.toHaveBeenCalled();
    fireEvent.click(screen.getByText("Old Ambient")); // another row moves the selection
    fireEvent.click(screen.getByText("Old Ambient")); // the same row again unselects
    expect(screen.getByText("Choose a track")).toBeTruthy();
    fireEvent.click(screen.getByText("Fresh Ambient"));
    fireEvent.click(screen.getByText("Next · Fresh Ambient"));
    expect(screen.getByText("You earn up to 10% of the tips A gets on the radio while it plays.")).toBeTruthy();
    fireEvent.click(screen.getByText("Push on air"));
    expect(onPick).toHaveBeenCalledWith(cat.tracks[2], 1, "", false, 0);
  });
  it("offers the artist's free pick, without dedication, and can be turned off", async () => {
    const onPick = vi.fn();
    const sponsoring = { ...cat, artists: new Map([[7, { id: 7, owner: "g1owner", verified: true, promo: 10, sponsor: 30_000 }]]) } as unknown as Catalog;
    render(<PickNext cat={sponsoring} station={1} onPick={onPick} onClose={() => undefined} />);
    fireEvent.click(await screen.findByText("Fresh Ambient"));
    expect(screen.getByText("A · free pick")).toBeTruthy();
    fireEvent.click(screen.getByText("Next · Fresh Ambient"));
    expect(screen.getByText(/^Free pick: A refunds it \(0\.03 GNOT\)/)).toBeTruthy();
    expect(screen.queryByPlaceholderText("to the night shift")).toBeNull();
    fireEvent.click(screen.getByText("Push on air"));
    expect(onPick).toHaveBeenCalledWith(sponsoring.tracks[2], 1, "", true, 0);
  });
  it("goes to step 2 with Enter on the selected row", async () => {
    const onPick = vi.fn();
    render(<PickNext cat={cat} station={1} onPick={onPick} onClose={() => undefined} />);
    const row = (await screen.findByText("Fresh Ambient")).closest("button");
    if (!row) throw new Error("no row");
    fireEvent.keyDown(row, { key: "Enter" });
    expect(onPick).not.toHaveBeenCalled();
    fireEvent.click(row);
    fireEvent.keyDown(row, { key: "Enter" });
    fireEvent.click(screen.getByText("Push on air"));
    expect(onPick).toHaveBeenCalledWith(cat.tracks[2], 1, "", false, 0);
  });
  it("greys out a track picked here less than 3 hours ago", async () => {
    picks = [{ kind: "queue", by: ME, track: 5, station: 1, start: NOW - 3000, at: NOW - 3000 }];
    render(<PickNext cat={cat} station={1} onPick={() => undefined} onClose={() => undefined} />);
    const row = (await screen.findByText(/^Picked here at/)).closest("button");
    expect(row?.disabled).toBe(true);
    picks = [];
  });
  it("waits for Adena, then reads the schedule back and offers to share the pick", async () => {
    // Like useActions: picking marks the action pending in the same click; the test settles it.
    function Harness() {
      const [pending, setPending] = useState("");
      return (
        <>
          <button onClick={() => { setPending(""); }}>settle</button>
          <PickNext cat={cat} station={1} me={ME} pending={pending} onPick={() => { setPending("Queue"); }} onClose={() => undefined} />
        </>
      );
    }
    const before = schedule;
    render(<Harness />);
    fireEvent.click(await screen.findByText("Fresh Ambient"));
    fireEvent.click(screen.getByText("Next · Fresh Ambient"));
    fireEvent.click(screen.getByText("Push on air"));
    expect(screen.getByText("Signing…")).toBeTruthy();
    schedule = { ...before, entries: [...before.entries, { track: 3, title: "Fresh Ambient", start: NOW + 300, end: NOW + 480, offset: 0, queued: true, by: ME, note: "" }] };
    fireEvent.click(screen.getByText("settle"));
    expect(await screen.findByText(/^Airs at .* on Ambient$/)).toBeTruthy();
    expect(screen.getByText("Share")).toBeTruthy();
    schedule = before;
  });
  it("disables an artist's tracks once 2 of them are waiting", async () => {
    const before = schedule;
    schedule = { ...before, entries: [...before.entries, { track: 4, title: "Loud Rock", start: NOW + 300, end: NOW + 480, offset: 0, queued: true, by: "g1other", note: "" }] };
    render(<PickNext cat={cat} station={1} onPick={() => undefined} onClose={() => undefined} />);
    const row = (await screen.findByText("A · 2 tracks already waiting")).closest("button");
    expect(row?.disabled).toBe(true);
    schedule = before;
  });
  it("books a pick for a time and says when it airs", async () => {
    const onPick = vi.fn();
    render(<PickNext cat={cat} station={1} me={ME} onPick={onPick} onClose={() => undefined} />);
    fireEvent.click(await screen.findByText("Fresh Ambient"));
    fireEvent.click(screen.getByText("Next · Fresh Ambient"));
    fireEvent.click(screen.getByText("At a time"));
    const at = NOW + 2 * 3600; // a quarter hour (NOW is one)
    fireEvent.change(screen.getByLabelText("Time, in your time zone"), { target: { value: hhmm(at) } });
    expect(screen.getByText("Would air at", { exact: false }).textContent).toBe(`Would air at ${hhmm(at)}`);
    expect(screen.queryByText(/booked/i)).toBeNull(); // only once the transaction went through
    fireEvent.click(screen.getByText("Push on air"));
    expect(onPick).toHaveBeenCalledWith(cat.tracks[2], 1, "", false, at);
  });
  it("shows a booked pick as on air at its time, in the listener's time", async () => {
    const before = schedule;
    schedule = { ...before, booked: [{ track: 3, start: NOW + 7300, end: NOW + 7480, at: NOW + 7200, by: ME }] };
    render(<PickNext cat={cat} station={1} me={ME} onPick={() => undefined} onClose={() => undefined} />);
    expect(await screen.findByText(/^Booked · airs at .* your time on Ambient$/)).toBeTruthy();
    schedule = before;
  });
  it("opens on step 2 with the suggested track, its station changeable", async () => {
    const onPick = vi.fn();
    const two = { ...cat, stations: [{ id: 0, name: "Main", genre: 0, tracks: 5 }, { id: 1, name: "Ambient", genre: 11, tracks: 3 }, { id: 2, name: "Rock", genre: 2, tracks: 1 }] } as unknown as Catalog;
    render(<PickNext cat={two} station={0} suggest={3} onPick={onPick} onClose={() => undefined} />);
    expect(await screen.findByText("Would air at", { exact: false })).toBeTruthy();
    const on = screen.getByLabelText<HTMLSelectElement>("On:");
    expect([...on.options].map((o) => o.text)).toEqual(["Main", "Ambient"]); // not Rock: it cannot play this track
    fireEvent.change(on, { target: { value: "1" } });
    fireEvent.click(screen.getByText("Push on air"));
    expect(onPick).toHaveBeenCalledWith(cat.tracks[2], 1, "", false, 0);
  });
  it("offers only new tracks on New this week", async () => {
    const withNew = { ...cat, stations: [{ id: 21, name: "New this week", genre: 0 }], newFloor: 3 } as unknown as Catalog;
    render(<PickNext cat={withNew} station={21} onPick={() => undefined} onClose={() => undefined} />);
    expect(await screen.findByText("Loud Rock")).toBeTruthy();
    expect(screen.queryByText("Fresh Ambient")).toBeNull();
  });
  it("takes the typographic apostrophe of iOS and macOS as typed", async () => {
    const onPick = vi.fn();
    render(<PickNext cat={cat} station={1} onPick={onPick} onClose={() => undefined} />);
    fireEvent.click(await screen.findByText("Fresh Ambient"));
    fireEvent.click(screen.getByText("Next · Fresh Ambient"));
    fireEvent.change(screen.getByPlaceholderText("to the night shift"), { target: { value: "Je t’aime Léa" } });
    await vi.waitFor(() => { expect(noteProblem).toHaveBeenCalledWith("Je t’aime Léa"); });
    expect(screen.getByText(/^Public and permanent/)).toBeTruthy();
    fireEvent.click(screen.getByText("Push on air"));
    expect(onPick).toHaveBeenCalledWith(cat.tracks[2], 1, "Je t’aime Léa", false, 0);
  });
});
