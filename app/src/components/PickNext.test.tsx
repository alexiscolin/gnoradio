import { cleanup, fireEvent, render, screen } from "@testing-library/react";
import { useState } from "react";
import { afterEach, describe, expect, it, vi } from "vitest";
import type { Catalog, Schedule, Track } from "../lib/types";
import { PickNext } from "./PickNext";

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
const noteProblem = vi.fn<(n: string) => Promise<string>>(() => Promise.resolve(""));
vi.mock("../lib/gno", async (orig) => ({ ...(await orig<object>()), noteProblem: (n: string) => noteProblem(n) }));
const ME = "g1u7y667z64x2h7vc6fmpcprgey4ck233jaww9zq";

afterEach(cleanup);

const t = (id: number, title: string, genre: number) => ({ id, title, genre, artistName: "A", duration: 180, audio: "", cover: "" }) as unknown as Track;
const tracks = [t(1, "On Air", 11), t(2, "Their Pick", 11), t(3, "Fresh Ambient", 11), t(4, "Loud Rock", 2)];
const cat = {
  stations: [{ id: 1, name: "Ambient", genre: 11 }],
  tracks,
  byId: new Map(tracks.map((x) => [x.id, x])),
} as unknown as Catalog;

describe("PickNext", () => {
  it("lists only tracks this station can play, minus what is already on", async () => {
    render(<PickNext cat={cat} station={1} onPick={() => undefined} onClose={() => undefined} />);
    expect(await screen.findByText("Fresh Ambient")).toBeTruthy();
    expect(screen.queryByText("Loud Rock")).toBeNull();
    expect(screen.getByText("after 1 pick")).toBeTruthy();
  });
  it("picks the track for that station", async () => {
    const onPick = vi.fn();
    render(<PickNext cat={cat} station={1} onPick={onPick} onClose={() => undefined} />);
    fireEvent.click(await screen.findByText("Fresh Ambient"));
    expect(onPick).toHaveBeenCalledWith(cat.tracks[2], 1, "");
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
    expect(screen.getByText("Signing…")).toBeTruthy();
    schedule = { ...before, entries: [...before.entries, { track: 3, title: "Fresh Ambient", start: NOW + 300, end: NOW + 480, offset: 0, queued: true, by: ME, note: "" }] };
    fireEvent.click(screen.getByText("settle"));
    expect(await screen.findByText(/^On air at .* on Ambient$/)).toBeTruthy();
    expect(screen.getByText("Share")).toBeTruthy();
    schedule = before;
  });
  it("takes the typographic apostrophe of iOS and macOS as typed", async () => {
    const onPick = vi.fn();
    render(<PickNext cat={cat} station={1} onPick={onPick} onClose={() => undefined} />);
    fireEvent.change(screen.getByPlaceholderText("for Marie, happy birthday!"), { target: { value: "Je t’aime Léa" } });
    await vi.waitFor(() => { expect(noteProblem).toHaveBeenCalledWith("Je t’aime Léa"); });
    expect(screen.getByText(/^Shown on air with your pick/)).toBeTruthy();
    fireEvent.click(await screen.findByText("Fresh Ambient"));
    expect(onPick).toHaveBeenCalledWith(cat.tracks[2], 1, "Je t’aime Léa");
  });
});
