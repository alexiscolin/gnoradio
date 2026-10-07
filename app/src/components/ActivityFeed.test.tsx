import { cleanup, render, screen } from "@testing-library/react";
import { afterEach, describe, expect, it, vi } from "vitest";
import type { Activity, Catalog } from "../lib/types";
import { ActivityFeed, activityLine } from "./ActivityFeed";

afterEach(cleanup);

const BY = "g1jg8mtutu9khhfwc4nxmuhcpftf0pajdhfvsqf5";
const cat = {
  byId: new Map([[8, { id: 8, artist: 3, title: "A very long track title that must stay whole" }]]),
  artists: new Map([[3, { id: 3, name: "Lea Kosmos" }]]),
  stations: [{ id: 2, name: "Ambient" }],
  albums: [],
  playlists: [],
} as unknown as Catalog;
const act = (a: Partial<Activity>): Activity => ({ kind: "like", by: BY, track: 8, artist: undefined, station: undefined, amount: undefined, at: 100, ...a });

describe("activityLine", () => {
  it("puts the title first, then what happened and where", () => {
    expect(activityLine(act({ kind: "queue", station: 2 }), cat)).toMatchObject({ title: "A very long track title that must stay whole", verb: "Picked", station: "Ambient", target: { k: "track", id: 8 } });
    expect(activityLine(act({ kind: "like", station: 2 }), cat)).toMatchObject({ verb: "Liked", station: "" });
    expect(activityLine(act({ kind: "follow", track: 0, artist: 3 }), cat)).toMatchObject({ title: "Lea Kosmos", verb: "Followed" });
  });
  it("leaves out a line whose title is unknown", () => {
    expect(activityLine(act({ track: 99 }), cat)).toBeNull();
    expect(activityLine(act({ kind: "playlist", track: 4 }), cat)).toBeNull();
  });
  it("renders the bold title, then 'by' a readable name, never the raw address", () => {
    vi.stubGlobal("fetch", vi.fn(() => Promise.reject(new Error("offline"))));
    render(<ActivityFeed items={[act({ kind: "queue", station: 2 }), act({ track: 99 })]} cat={cat} go={() => undefined} now={160} />);
    expect(screen.getAllByRole("listitem")).toHaveLength(1);
    const li = screen.getByRole("listitem");
    expect(li.querySelector(".feed-title")?.textContent).toBe("A very long track title that must stay whole");
    expect(li.querySelector(".feed-by")?.textContent).toMatch(/^Picked by [A-Z][a-z]+ [A-Z][a-z]+ [0-9A-F]{2} · Ambient · 1m$/);
    vi.unstubAllGlobals();
  });
});
