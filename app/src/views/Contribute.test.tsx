import { describe, expect, it } from "vitest";
import { sameName } from "./Contribute";

describe("ArtistForm rename", () => {
  it("asks before a new name drops the verification, not for case or spacing", () => {
    expect(sameName("Lea Kosmos", "lea  kosmos")).toBe(true);
    expect(sameName("Lea Kosmos", "Lea-Kosmos")).toBe(true);
    expect(sameName("Lea Kosmos", "Lea Cosmos")).toBe(false);
  });
});
