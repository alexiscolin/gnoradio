import { describe, expect, it } from "vitest";
import { AUDIENCES, audiences, hrefOf, moneyRows } from "./features";
import { changesFees, type Fees, feesOf, NO_FEES } from "./fees";
import { REALMS } from "./realms";
import { COSTS, NO_FEE } from "./legal";
import { pathToView, viewToPath } from "./router";

const all = AUDIENCES.flatMap((a) => [...a.cards, ...a.more]);

describe("features", () => {
  it.each(all.map((f) => [f.title, f.go] as const))("%s leads somewhere real", (_title, go) => {
    if ("href" in go) { expect(go.href).toMatch(/^https?:\/\/.+/); return; }
    const view = "pick" in go ? { k: "stations" as const, live: 0 } : go.view;
    expect(pathToView(viewToPath(view)).k).not.toBe("notfound");
    expect(pathToView(viewToPath(view))).toEqual(view);
  });
  it("links a spot on a screen with its anchor", () => {
    expect(hrefOf({ view: { k: "me" }, hash: "me-make-music" }, (v) => viewToPath(v))).toBe("/me#me-make-music");
    expect(hrefOf({ pick: true }, (v) => viewToPath(v))).toBe("/live");
  });
  it("gives every feature a title and a line", () => {
    expect(new Set(all.map((f) => f.title)).size).toBe(all.length);
    for (const f of all) expect(f.line.length).toBeGreaterThan(20);
  });
});

describe("COSTS", () => {
  it("does not claim GnoRadio pays nothing at all: the publisher pays the deploy and the launch catalog", () => {
    expect(COSTS).toMatch(/launch catalog/);
    expect(COSTS).not.toMatch(/pays nothing to run/);
  });
});

describe("fees", () => {
  const text = (f: Fees) => JSON.stringify([moneyRows(f), audiences(f.ticketFee)]);
  const rows = (f: Fees) => moneyRows(f).map((r) => r[0]);
  const treasury: Fees = { support: true, ticketFee: false }, ticket: Fees = { support: false, ticketFee: true }, both: Fees = { support: true, ticketFee: true };
  it("are two facts: a treasury is set, tickets carry a service fee", () => {
    expect(feesOf("", 0)).toEqual(NO_FEES);
    expect(feesOf("g1treasury", 0)).toEqual(treasury);
    expect(feesOf("", 500_000)).toEqual(ticket);
    expect(feesOf("g1treasury", 500_000)).toEqual(both);
  });
  it("say no fee, and mention none, while none is set", () => {
    expect(text(NO_FEES)).not.toMatch(/service fee|treasury|\+10%|Direct support/);
    expect(moneyRows(NO_FEES).map((r) => r[2])).toContain(NO_FEE);
    expect(NO_FEE).toBe("GnoRadio takes no fee: tips and ticket prices go 100% to the artist.");
    expect(AUDIENCES).toEqual(audiences(false));
  });
  it("with a treasury only: the +10% and direct support, no service fee", () => {
    expect(rows(treasury)).toEqual(expect.arrayContaining(["Optional, on top of a tip", "Direct support"]));
    expect(text(treasury)).not.toMatch(/service fee/);
    expect(text(treasury)).not.toContain(NO_FEE);
  });
  it("with a service fee only: the service-fee copy, no support rows, no 'no fee' claim", () => {
    expect(text(ticket)).toMatch(/service fee/);
    expect(rows(ticket)).not.toEqual(expect.arrayContaining(["Optional, on top of a tip"]));
    expect(rows(ticket)).not.toContain("Direct support");
    expect(text(ticket)).not.toContain(NO_FEE);
  });
  it("with both: everything", () => {
    expect(text(both)).toMatch(/service fee/);
    expect(rows(both)).toEqual(expect.arrayContaining(["Optional, on top of a tip", "Direct support"]));
  });
  it("are re-read after the admin's own fee or treasury transaction only", () => {
    expect(changesFees({ pkg: REALMS.tickets, func: "SetServiceFee" })).toBe(true);
    expect(changesFees({ pkg: REALMS.catalog, func: "SetTreasury" })).toBe(true);
    expect(changesFees({ pkg: REALMS.catalog, func: "Like" })).toBe(false);
    expect(changesFees(undefined)).toBe(false);
  });
});
