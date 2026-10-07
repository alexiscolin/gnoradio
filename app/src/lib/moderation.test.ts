import { describe, expect, it } from "vitest";
import { verdict } from "./moderation";

describe("verdict", () => {
  it("hides severe harm at low scores and tolerates mild language", () => {
    expect(verdict({ "harassment/threatening": 0.45 })).toBe("harassment/threatening");
    expect(verdict({ "sexual/minors": 0.2, harassment: 0.9 })).toBe("sexual/minors");
    expect(verdict({ harassment: 0.6, sexual: 0.7, violence: 0.5 })).toBe("");
    expect(verdict({})).toBe("");
  });
});
