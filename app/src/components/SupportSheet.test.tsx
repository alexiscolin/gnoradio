import { cleanup, fireEvent, render, screen } from "@testing-library/react";
import { afterEach, describe, expect, it, vi } from "vitest";
import type { Artist, Track } from "../lib/types";
import { SupportSheet } from "./SupportSheet";

afterEach(cleanup);

const track = {
  id: 8, artist: 3, artistName: "Lea Kosmos", title: "Jenifer The Game",
  splits: [{ to: "g1collabxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx", pct: 30 }],
} as unknown as Track;
const artist = { id: 3, name: "Lea Kosmos", owner: "g1lea", tips: 0 } as unknown as Artist;

describe("SupportSheet", () => {
  it("adds the optional 10% on top and keeps 100% for the artist", () => {
    const onTip = vi.fn();
    render(<SupportSheet target={{ kind: "tip", track, artist }} codeURL="#" onClose={() => undefined} onTip={onTip} onSupport={() => undefined} />);
    fireEvent.click(screen.getByRole("radio", { name: /20/ }));
    expect(screen.getByText("Send 22 GNOT with Adena")).toBeTruthy();
    fireEvent.click(screen.getByText("Send 22 GNOT with Adena"));
    expect(onTip).toHaveBeenCalledWith(track, 22_000_000, 10);
  });
  it("sends exactly the amount when the contribution is unticked", () => {
    const onTip = vi.fn();
    render(<SupportSheet target={{ kind: "tip", track, artist }} codeURL="#" onClose={() => undefined} onTip={onTip} onSupport={() => undefined} />);
    fireEvent.click(screen.getByRole("checkbox"));
    fireEvent.click(screen.getByText("Send 5 GNOT with Adena"));
    expect(onTip).toHaveBeenCalledWith(track, 5_000_000, 0);
  });
  it("refuses amounts under 0.1 GNOT", () => {
    render(<SupportSheet target={{ kind: "platform" }} codeURL="#" onClose={() => undefined} onTip={() => undefined} onSupport={() => undefined} />);
    fireEvent.change(screen.getByPlaceholderText("Other"), { target: { value: "0.05" } });
    expect(screen.getByRole<HTMLButtonElement>("button", { name: /Enter between 0.1/ }).disabled).toBe(true);
  });
});
