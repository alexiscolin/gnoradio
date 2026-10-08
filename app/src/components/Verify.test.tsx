import { cleanup, render, screen } from "@testing-library/react";
import { afterEach, describe, expect, it } from "vitest";
import { CONTACT } from "../lib/legal";
import type { Artist } from "../lib/types";
import type { Actions } from "../player/useActions";
import { MODERATOR_MARK, ProofMark, VerifyPanel, isClaim } from "./Verify";

afterEach(cleanup);

const actions = { wallet: { state: { status: "connected", address: "g1jg8mtutu9khhfwc4nxmuhcpftf0pajdhfvsqf5" } } } as unknown as Actions;
const panel = (kind: Artist["kind"]) => {
  const a = { id: 7, name: "Lea", kind, owner: "", source: "https://archive.example/lea", verified: false } as Artist;
  render(<VerifyPanel a={a} claim={null} actions={actions} onClose={() => undefined} onChange={() => undefined} />);
};

describe("VerifyPanel", () => {
  it("never offers the claim form for an imported profile: it sends to the moderator", () => {
    panel("curated");
    expect(screen.getByRole("link", { name: "contact the moderator to claim it" }).getAttribute("href")).toBe(CONTACT);
    expect(screen.queryByLabelText("Your website")).toBeNull();
    expect(screen.queryByRole("button", { name: "Check my page" })).toBeNull();
  });

  it("asks an artist profile for its website", () => {
    panel("artist");
    expect(screen.getByLabelText("Your website")).toBeTruthy();
    expect(screen.queryByText(/contact the moderator/)).toBeNull();
  });
});

describe("ProofMark", () => {
  it("shows the proof host, or says the moderator verified it", () => {
    render(<><ProofMark a={{ verified: true, proofHost: "lea.example" }} /><ProofMark a={{ verified: true, proofHost: "" }} /><ProofMark a={{ verified: false, proofHost: "" }} /></>);
    expect(screen.getByText("✓ lea.example")).toBeTruthy();
    expect(screen.getAllByText(MODERATOR_MARK)).toHaveLength(1);
  });
});

// The two shapes catalog.ClaimJSON returns (verify.gno).
describe("isClaim", () => {
  it("reads a profile with and without a pending claim", () => {
    expect(isClaim(JSON.parse('{"verified":false,"proof":"","pending":false,"bot":true}'))).toBe(true);
    expect(isClaim(JSON.parse('{"verified":false,"proof":"","pending":true,"to":"g1x","pendingProof":"https://a.b/.well-known/gnoradio.txt","readyAt":1234,"bot":true}'))).toBe(true);
    expect(isClaim(JSON.parse('{"verified":false,"proof":"","pending":false,"bot":"g1x"}'))).toBe(false);
  });
});
