import { describe, expect, it } from "vitest";
import { isClaim } from "./Verify";

// The two shapes catalog.ClaimJSON returns (verify.gno).
describe("isClaim", () => {
  it("reads a profile with and without a pending claim", () => {
    expect(isClaim(JSON.parse('{"verified":false,"proof":"","pending":false,"bot":true}'))).toBe(true);
    expect(isClaim(JSON.parse('{"verified":false,"proof":"","pending":true,"to":"g1x","pendingProof":"https://a.b/.well-known/gnoradio.txt","readyAt":1234,"bot":true}'))).toBe(true);
    expect(isClaim(JSON.parse('{"verified":false,"proof":"","pending":false,"bot":"g1x"}'))).toBe(false);
  });
});
