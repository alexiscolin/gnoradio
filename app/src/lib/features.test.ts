import { describe, expect, it } from "vitest";
import { AUDIENCES, audiences, hrefOf, moneyRows } from "./features";
import { feesOn } from "./fees";
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
  const text = (fees: boolean) => JSON.stringify([moneyRows(fees), audiences(fees)]);
  it("are on only with a treasury or a ticket service fee", () => {
    expect(feesOn("", 0)).toBe(false);
    expect(feesOn("g1treasury", 0)).toBe(true);
    expect(feesOn("", 500_000)).toBe(true);
  });
  it("say no fee, and mention none, while none is set", () => {
    expect(text(false)).not.toMatch(/service fee|treasury|\+10%|Direct support/);
    expect(moneyRows(false).map((r) => r[2])).toContain(NO_FEE);
    expect(NO_FEE).toBe("GnoRadio takes no fee: tips and ticket prices go 100% to the artist.");
    expect(AUDIENCES).toEqual(audiences(false));
  });
  it("describe the fees once they are on", () => {
    expect(text(true)).toMatch(/service fee/);
    expect(moneyRows(true).map((r) => r[0])).toEqual(expect.arrayContaining(["Optional, on top of a tip", "Direct support"]));
    expect(text(true)).not.toContain(NO_FEE);
  });
});
