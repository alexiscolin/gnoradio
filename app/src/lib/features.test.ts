import { describe, expect, it } from "vitest";
import { AUDIENCES, hrefOf } from "./features";
import { COSTS } from "./legal";
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
