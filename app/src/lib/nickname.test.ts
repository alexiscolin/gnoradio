import { describe, expect, it } from "vitest";
import { nickname } from "./nickname";

const A = "g1jg8mtutu9khhfwc4nxmuhcpftf0pajdhfvsqf5";
const B = "g1hplnue27uazg4pa7vfhzga64na9skvglqatedj";

describe("nickname", () => {
  it("is readable, short and stable for an address", () => {
    expect(nickname(A)).toMatch(/^[A-Z][a-z]+ [A-Z][a-z]+ [0-9A-F]{2}$/);
    expect(nickname(A)).toBe(nickname(A));
    expect(nickname(A).length).toBeLessThanOrEqual(20);
  });
  it("tells addresses apart", () => {
    expect(nickname(A)).not.toBe(nickname(B));
    const many = new Set(Array.from({ length: 200 }, (_, i) => nickname(`g1${String(i).padStart(38, "q")}`)));
    expect(many.size).toBeGreaterThan(195);
  });
});
