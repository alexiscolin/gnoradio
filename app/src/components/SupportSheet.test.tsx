import { cleanup, fireEvent, render, screen } from "@testing-library/react";
import type { ReactNode } from "react";
import { afterEach, describe, expect, it, vi } from "vitest";
import type { Artist, Track } from "../lib/types";
import { FeesContext } from "../lib/fees";
import { SupportSheet } from "./SupportSheet";

const withFees = (ui: ReactNode) => <FeesContext.Provider value>{ui}</FeesContext.Provider>;

afterEach(cleanup);

const track = {
  id: 8, artist: 3, artistName: "Lea Kosmos", title: "Jenifer The Game",
  splits: [{ to: "g1collabxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx", pct: 30 }],
} as unknown as Track;
const artist = { id: 3, name: "Lea Kosmos", owner: "g1lea", tips: 0 } as unknown as Artist;
const PICKER = "g1jg8mtutu9khhfwc4nxmuhcpftf0pajdhfvsqf5";
const REF = "g1u7y667z64x2h7vc6fmpcprgey4ck233jaww9zq";
const ME = "g1tipperxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx";

describe("SupportSheet", () => {
  it("offers no +10% while GnoRadio takes no fee", () => {
    render(<SupportSheet target={{ kind: "tip", track, artist }} codeURL="#" onClose={() => undefined} onTip={() => undefined} onSupport={() => undefined} />);
    expect(screen.queryByRole("checkbox")).toBeNull();
    expect(document.body.textContent).not.toMatch(/treasury|10%/);
  });
  it("sends exactly the amount: the GnoRadio extra is off by default", () => {
    const onTip = vi.fn();
    render(withFees(<SupportSheet target={{ kind: "tip", track, artist }} codeURL="#" onClose={() => undefined} onTip={onTip} onSupport={() => undefined} />));
    expect(screen.getByRole<HTMLInputElement>("checkbox").checked).toBe(false);
    expect(screen.getByText(/A gift, not a purchase: final once sent, GnoRadio cannot refund it\./)).toBeTruthy();
    fireEvent.click(screen.getByText("Send 5 GNOT with Adena"));
    expect(onTip).toHaveBeenCalledWith(track, 5_000_000, 0, undefined, undefined);
  });
  it("adds the optional 10% on top when ticked", () => {
    const onTip = vi.fn();
    render(withFees(<SupportSheet target={{ kind: "tip", track, artist }} codeURL="#" onClose={() => undefined} onTip={onTip} onSupport={() => undefined} />));
    fireEvent.click(screen.getByRole("radio", { name: /20/ }));
    fireEvent.click(screen.getByRole("checkbox"));
    fireEvent.click(screen.getByText("Send 22 GNOT with Adena"));
    expect(onTip).toHaveBeenCalledWith(track, 22_000_000, 10, undefined, undefined);
  });
  it("shows the promo share for the picker and the referrer, and sends through the radio", () => {
    const onTip = vi.fn();
    const promo = { ...artist, promo: 10 } as Artist;
    render(<SupportSheet target={{ kind: "tip", track, artist: promo, station: 4, picker: PICKER }} me={ME} referrer={REF} codeURL="#" onClose={() => undefined} onTip={onTip} onSupport={() => undefined} />);
    fireEvent.click(screen.getByRole("radio", { name: /20/ }));
    // 20 GNOT: 10% promo = 2 GNOT, 1 each; the 18 left split 70/30.
    expect(screen.getByText("picked it on air").closest("div")?.textContent).toContain("1 GNOT");
    expect(screen.getByText("shared the link").closest("div")?.textContent).toContain("1 GNOT");
    expect(screen.getByText("artist").closest("div")?.textContent).toContain("12.6 GNOT");
    expect(screen.getByText(/^10% is split between/)).toBeTruthy();
    fireEvent.click(screen.getByText("Send 20 GNOT with Adena"));
    expect(onTip).toHaveBeenCalledWith(track, 20_000_000, 0, 4, REF);
  });
  it("gives no share to a tipper who picked the track", () => {
    render(<SupportSheet target={{ kind: "tip", track, artist, station: 4, picker: ME }} me={ME} codeURL="#" onClose={() => undefined} onTip={() => undefined} onSupport={() => undefined} />);
    expect(screen.queryByText("picked it on air")).toBeNull();
  });
  it("refuses amounts under 0.1 GNOT", () => {
    render(<SupportSheet target={{ kind: "platform" }} codeURL="#" onClose={() => undefined} onTip={() => undefined} onSupport={() => undefined} />);
    fireEvent.change(screen.getByPlaceholderText("Other"), { target: { value: "0.05" } });
    expect(screen.getByRole<HTMLButtonElement>("button", { name: /Enter between 0.1/ }).disabled).toBe(true);
  });
});
