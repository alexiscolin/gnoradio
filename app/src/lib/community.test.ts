import { describe, expect, it } from "vitest";
import { type RadioPick, topProgrammers } from "./community";

const NOW = 1_800_000_000;
const pick = (by: string, ago: number, kind: RadioPick["kind"] = "queue"): RadioPick => ({ kind, by, track: 1, station: 0, start: NOW - ago, at: NOW - ago });

describe("topProgrammers", () => {
  it("counts listener picks of the last 7 days, most first", () => {
    const picks = [pick("g1a", 60), pick("g1b", 120), pick("g1b", 3600), pick("g1a", 8 * 86400), pick("g1c", 60, "curator")];
    expect(topProgrammers(picks, NOW)).toEqual([{ by: "g1b", picks: 2 }, { by: "g1a", picks: 1 }]);
  });
  it("keeps the top ones only", () => {
    expect(topProgrammers([pick("g1a", 1), pick("g1b", 1), pick("g1c", 1)], NOW, 2)).toHaveLength(2);
  });
});
