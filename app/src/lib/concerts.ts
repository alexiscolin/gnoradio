// Concerts page helpers: city chips, filters, month groups, seats left.
import type { ConcertEvent } from "./types";

export interface ConcertFilter {
  readonly q: string;
  readonly when: "" | "week" | "month";
  readonly free: boolean;
  readonly city: string;
}

export const NO_FILTER: ConcertFilter = { q: "", when: "", free: false, city: "" };

/** cityOf reads the city from a venue written "Place, City"; "" when there is no comma. */
export function cityOf(venue: string): string {
  const i = venue.lastIndexOf(",");
  return i < 0 ? "" : venue.slice(i + 1).trim();
}

/** cities lists the listings' cities once each, in date order. */
export const cities = (events: readonly ConcertEvent[]): string[] =>
  [...new Set(events.map((e) => cityOf(e.venue)).filter(Boolean))];

/** monthKey names the UTC month a concert starts in, as the times on the page are UTC. */
const monthKey = (start: number): string =>
  new Date(start * 1000).toLocaleDateString("en", { month: "long", year: "numeric", timeZone: "UTC" });

/**
 * filterConcerts keeps the concerts matching the search (artist, city, venue, title)
 * and the chips. "This week" is the next 7 days, "This month" the current UTC month.
 */
export function filterConcerts(events: readonly ConcertEvent[], f: ConcertFilter, artistName: (id: number) => string, now: number): ConcertEvent[] {
  const q = f.q.trim().toLowerCase();
  return events.filter((e) => {
    if (f.free && e.price > 0) return false;
    if (f.city && cityOf(e.venue) !== f.city) return false;
    if (f.when === "week" && !(e.start >= now - 6 * 3600 && e.start < now + 7 * 86400)) return false;
    if (f.when === "month" && monthKey(e.start) !== monthKey(now)) return false;
    return !q || [artistName(e.artist), e.venue, e.title].some((s) => s.toLowerCase().includes(q));
  });
}

/** byMonth groups concerts under a "October 2026" heading, months in order of first appearance. */
export function byMonth(events: readonly ConcertEvent[]): { month: string; events: ConcertEvent[] }[] {
  const out = new Map<string, ConcertEvent[]>();
  for (const e of events) {
    const k = monthKey(e.start);
    out.set(k, [...(out.get(k) ?? []), e]);
  }
  return [...out].map(([month, list]) => ({ month, events: list }));
}

/** almostFull says "Almost full · N left" once 10% or 5 seats or fewer remain; "" otherwise. */
export function almostFull(e: ConcertEvent): string {
  const left = e.capacity - e.sold;
  return left > 0 && !e.cancelled && (left <= 5 || left <= e.capacity * 0.1) ? `Almost full · ${String(left)} left` : "";
}
