import { cleanup, fireEvent, render, screen } from "@testing-library/react";
import { afterEach, describe, expect, it, vi } from "vitest";
import type { Catalog, Track } from "../lib/types";
import { ListenerView } from "./Listener";

const A = "g1jg8mtutu9khhfwc4nxmuhcpftf0pajdhfvsqf5";
const now = Math.floor(Date.now() / 1000);

vi.mock("../lib/incentives", () => ({
  loadCurator: () => Promise.resolve({ address: A, picks: 7, tips: 2, earned: 1_500_000, promo: 0, week: { picks: 3, tips: 1, earned: 0, rank: 2 } }),
}));
vi.mock("../lib/community", () => ({
  loadPicks: () => Promise.resolve([{ kind: "queue", by: A, track: 4, station: 0, start: now + 600, at: now }]),
}));
vi.mock("../lib/catalog", () => ({
  loadSchedule: () => Promise.resolve({ station: 0, now, entries: [{ track: 4, title: "Air", start: now + 600, end: now + 800, offset: 0, queued: true, by: A, note: "for Lea" }] }),
}));
vi.mock("../lib/names", () => ({ useNames: () => () => "@alice" }));

afterEach(cleanup);

const air = { id: 4, title: "Air", duration: 200 } as Track;
const cat = {
  byId: new Map([[4, air]]), stations: [{ id: 0, name: "Main" }],
  playlists: [{ id: 9, owner: A, title: "Night drive", updated: 0, tracks: [4] }, { id: 10, owner: "g1other", title: "Not theirs", updated: 0, tracks: [] }],
} as unknown as Catalog;

describe("ListenerView", () => {
  it("shows the curator, their picks with dedications and playlists", async () => {
    const go = vi.fn();
    render(<ListenerView cat={cat} go={go} address={A} me={A} />);
    expect(screen.getByRole("heading", { level: 1 }).textContent).toBe("@alice");
    expect(await screen.findByText("#2")).toBeTruthy();
    expect(screen.getByText("7")).toBeTruthy();
    expect(await screen.findByText(/for Lea/)).toBeTruthy();
    expect(screen.queryByText("Not theirs")).toBeNull();
    fireEvent.click(screen.getByText("Night drive"));
    expect(go).toHaveBeenCalledWith({ k: "playlist", id: 9 });
    fireEvent.click(screen.getByRole("button", { name: "Me" }));
    expect(go).toHaveBeenCalledWith({ k: "me" });
  });
});
