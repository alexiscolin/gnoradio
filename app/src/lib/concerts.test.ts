import { describe, expect, it } from "vitest";
import { NO_FILTER, almostFull, byMonth, cities, cityOf, filterConcerts } from "./concerts";
import type { ConcertEvent } from "./types";

const at = (iso: string) => Date.parse(iso) / 1000;
const ev = (id: number, venue: string, start: string, price = 0, capacity = 100, sold = 0): ConcertEvent =>
  ({ id, artist: id, title: `Show ${String(id)}`, venue, link: "", start: at(start), price, capacity, sold, cancelled: false, fee: undefined });

const list = [
  ev(1, "Le Sucre, Lyon", "2026-10-10T20:00:00Z"),
  ev(2, "Paloma, Nîmes", "2026-10-24T21:00:00Z", 5_000_000),
  ev(3, "La Station, Paris", "2026-11-20T21:00:00Z", 2_000_000),
  ev(4, "Somewhere", "2026-11-21T21:00:00Z"),
];
const name = (id: number) => (id === 3 ? "Lea Kosmos" : "Other");
const now = at("2026-10-07T12:00:00Z");

describe("concerts", () => {
  it("reads the city after the last comma", () => {
    expect(cityOf("Le Sucre, Lyon")).toBe("Lyon");
    expect(cityOf("Somewhere")).toBe("");
    expect(cities(list)).toEqual(["Lyon", "Nîmes", "Paris"]);
  });

  it("filters by search, chips and city", () => {
    const ids = (f: Partial<typeof NO_FILTER>) => filterConcerts(list, { ...NO_FILTER, ...f }, name, now).map((e) => e.id);
    expect(ids({})).toEqual([1, 2, 3, 4]);
    expect(ids({ q: "kosmos" })).toEqual([3]);
    expect(ids({ q: "lyon" })).toEqual([1]);
    expect(ids({ when: "week" })).toEqual([1]);
    expect(ids({ when: "month" })).toEqual([1, 2]);
    expect(ids({ free: true })).toEqual([1, 4]);
    expect(ids({ city: "Paris" })).toEqual([3]);
    expect(ids({ city: "Paris", free: true })).toEqual([]);
  });

  it("groups by month", () => {
    expect(byMonth(list).map((g) => [g.month, g.events.map((e) => e.id)])).toEqual([["October 2026", [1, 2]], ["November 2026", [3, 4]]]);
  });

  it("flags almost full concerts", () => {
    expect(almostFull(ev(1, "", "2026-10-10T20:00:00Z", 0, 2, 1))).toBe("Almost full · 1 left");
    expect(almostFull(ev(1, "", "2026-10-10T20:00:00Z", 0, 400, 362))).toBe("Almost full · 38 left");
    expect(almostFull(ev(1, "", "2026-10-10T20:00:00Z", 0, 100, 50))).toBe("");
    expect(almostFull(ev(1, "", "2026-10-10T20:00:00Z", 0, 1, 1))).toBe("");
  });
});
