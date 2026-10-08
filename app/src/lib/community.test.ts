import { describe, expect, it, vi } from "vitest";
import { loadTicket } from "./community";

const out = vi.hoisted(() => ({ text: "" }));
vi.mock("./gno", async (orig) => ({ ...(await orig<object>()), qeval: () => Promise.resolve(out.text) }));

describe("loadTicket", () => {
  it("reads one ticket from TicketInfo's (Ticket, bool) answer, null when there is none", async () => {
    out.text = "(struct{(7 int),(2 int),(3 int),(true bool)} gno.land/r/gnoradio/tickets/v1.Ticket)\n(true bool)";
    expect(await loadTicket(7)).toEqual({ id: 7, event: 2, serial: 3, attended: true });
    out.text = "(struct{(0 int),(0 int),(0 int),(false bool)} gno.land/r/gnoradio/tickets/v1.Ticket)\n(false bool)";
    expect(await loadTicket(9)).toBeNull();
  });
});
