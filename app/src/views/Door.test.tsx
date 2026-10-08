import { act, cleanup, render, screen } from "@testing-library/react";
import { afterEach, describe, expect, it, vi } from "vitest";
import type { Catalog } from "../lib/types";
import type { Actions } from "../player/useActions";
import { DoorView } from "./Door";

const HOLDER = "g1jg8mtutu9khhfwc4nxmuhcpftf0pajdhfvsqf5";
const now = Math.floor(Date.now() / 1000);
let presentedAt = 0;
let start = now + 3600;

vi.mock("../lib/community", async (orig) => ({
  ...(await orig<object>()),
  loadTicketOwner: () => Promise.resolve(HOLDER),
  loadTicket: (id: number) => Promise.resolve({ id, event: 2, serial: 1, attended: false }),
  loadTicketsOf: () => Promise.resolve([]), // the holder's newest 50 only: the door must not depend on it
  doorCode: () => "4821",
  loadPresentedAt: (_t: number, code: string) => Promise.resolve(code === "4821" ? presentedAt : 0),
  // A concert missing from the upcoming list: read on its own (none on chain here, null).
  useEvents: (cat: Catalog, ids: readonly number[]) => new Map(ids.map((id) => [id, cat.events.find((e) => e.id === id) ?? null])),
}));
vi.mock("../lib/names", () => ({ useNames: () => () => "@alice" }));

afterEach(() => { cleanup(); presentedAt = 0; start = now + 3600; });

const actions = { pending: "", checkIn: vi.fn() } as unknown as Actions;
const door = () => {
  const cat = { events: [{ id: 2, title: "Release Party", venue: "La Station", start, cancelled: false }] } as unknown as Catalog;
  render(<DoorView cat={cat} go={() => undefined} ticket={7} holder={HOLDER} actions={actions} />);
};

describe("DoorView", () => {
  it("never says valid for a ticket whose concert is not in the list: reads it, and refuses when there is none", async () => {
    presentedAt = now - 60;
    render(<DoorView cat={{ events: [] } as unknown as Catalog} go={() => undefined} ticket={7} holder={HOLDER} actions={actions} />);
    expect(await screen.findByText("Not valid: this concert can't be found.")).toBeTruthy();
    expect(screen.queryByRole("button", { name: "Check in" })).toBeNull();
  });

  it("asks for the holder's Present before Check in", async () => {
    door();
    expect(await screen.findByText("Not presented: ask the holder to tap Show at the door and enter the code 4821.")).toBeTruthy();
    expect(screen.getByLabelText("Door code 4821")).toBeTruthy();
    expect(screen.queryByRole("button", { name: "Check in" })).toBeNull();
    expect(screen.getByRole("button", { name: "Check again" })).toBeTruthy();
  });

  it("names who presented it and when, then offers Check in", async () => {
    presentedAt = now - 180;
    door();
    expect(await screen.findByText("Valid ticket. Presented 3 min ago by @alice.")).toBeTruthy();
    expect(screen.getByRole("button", { name: "Check in" })).toBeTruthy();
    screen.getByRole("button", { name: "Check in" }).click();
    expect(actions.checkIn).toHaveBeenCalledWith(7, "4821", expect.any(Function)); // the code it showed
  });

  it("treats a Present older than 10 minutes as none", async () => {
    presentedAt = now - 11 * 60;
    door();
    expect(await screen.findByText(/^Not presented/)).toBeTruthy();
  });

  it("asks for no Present before check-in opens", async () => {
    start = now + 13 * 3600;
    door();
    expect(await screen.findByText("Not yet: check-in opens 12 hours before the concert.")).toBeTruthy();
    expect(screen.queryByLabelText("Door code 4821")).toBeNull();
  });

  it("refuses a ticket to a concert that is over", async () => {
    presentedAt = now - 60;
    start = now - 13 * 3600;
    door();
    expect(await screen.findByText("Not valid: this concert is over.")).toBeTruthy();
    expect(screen.queryByRole("button", { name: "Check in" })).toBeNull();
  });

  it("withdraws the valid verdict when the 10 minutes run out", async () => {
    vi.useFakeTimers({ toFake: ["setTimeout", "clearTimeout", "Date"] });
    try {
      presentedAt = Math.floor(Date.now() / 1000) - 180;
      door();
      await act(() => vi.advanceTimersByTimeAsync(0));
      expect(screen.getByText("Valid ticket. Presented 3 min ago by @alice.")).toBeTruthy();
      await act(() => vi.advanceTimersByTimeAsync(60_000));
      expect(screen.getByText("Valid ticket. Presented 4 min ago by @alice.")).toBeTruthy();
      await act(() => vi.advanceTimersByTimeAsync(6 * 60_000 + 2000));
      expect(screen.getByText(/^Not presented/)).toBeTruthy();
      expect(screen.queryByRole("button", { name: "Check in" })).toBeNull();
    } finally {
      vi.useRealTimers();
    }
  });
});
