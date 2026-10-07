import { describe, expect, it } from "vitest";
import { captureRef, pickResult, promoSplit, sessionRef, withRef } from "./incentives";

const P = "g1jg8mtutu9khhfwc4nxmuhcpftf0pajdhfvsqf5";
const R = "g1u7y667z64x2h7vc6fmpcprgey4ck233jaww9zq";
const T = "g1tipperxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx";
const A = "g1artistxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx";

describe("promoSplit", () => {
  it("splits like catalog.tip: half each, the odd ugnot to the picker", () => {
    expect(promoSplit(10_000_000, 10, { picker: P, ref: R, tipper: T, owner: A })).toEqual({ toPicker: 500_000, toRef: 500_000 });
    expect(promoSplit(1_000_020, 5, { picker: P, ref: R, tipper: T, owner: A })).toEqual({ toPicker: 25_001, toRef: 25_000 });
  });
  it("gives the whole share to one alone, and none to the tipper or the artist", () => {
    expect(promoSplit(2_000_000, 5, { picker: P, ref: "", tipper: T, owner: A })).toEqual({ toPicker: 100_000, toRef: 0 });
    expect(promoSplit(1_000_000, 5, { picker: T, ref: R, tipper: T, owner: A })).toEqual({ toPicker: 0, toRef: 50_000 });
    expect(promoSplit(1_000_000, 5, { picker: A, ref: A, tipper: T, owner: A })).toEqual({ toPicker: 0, toRef: 0 });
    expect(promoSplit(1_000_000, 5, { picker: P, ref: P, tipper: T, owner: A })).toEqual({ toPicker: 50_000, toRef: 0 });
    expect(promoSplit(1_000_000, 0, { picker: P, ref: R, tipper: T, owner: A })).toEqual({ toPicker: 0, toRef: 0 });
  });
});

describe("share links", () => {
  it("carry the sharer and keep it for the session", () => {
    expect(withRef("https://gnoradio.app/live", R)).toBe(`https://gnoradio.app/live?ref=${R}`);
    expect(withRef("https://gnoradio.app/live", "")).toBe("https://gnoradio.app/live");
    captureRef("?ref=not-an-address");
    expect(sessionRef()).toBe("");
    captureRef(`?ref=${R}`);
    expect(sessionRef()).toBe(R);
  });
});

it("tells what a pick earned, with no invented listener count", () => {
  expect(pickResult("Air", { likes: 3, tips: 0, earned: 0 }, { likes: 5, tips: 2_000_000, earned: 100_000 }))
    .toBe("Your pick “Air” played: +2 likes · 2 GNOT in tips to the artist · you earned 0.1 GNOT.");
  expect(pickResult("Air", { likes: 3, tips: 0, earned: 0 }, { likes: 3, tips: 0, earned: 0 })).toBe("Your pick “Air” played: 0 likes · no tip.");
});
