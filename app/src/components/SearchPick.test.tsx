import { cleanup, fireEvent, render, screen } from "@testing-library/react";
import { afterEach, describe, expect, it, vi } from "vitest";
import { SearchPick, matches } from "./SearchPick";

afterEach(cleanup);

const items = [
  { id: 1, label: "Minuit sur le Rhône", sub: "Lea Kosmos" },
  { id: 2, label: "Air", sub: "Scott Buckley" },
  { id: 3, label: "Begotten", sub: "ATTLAS" },
];

describe("SearchPick", () => {
  it("filters by label or secondary line, ignoring case and accents", () => {
    expect(matches(items, "rhone").map((i) => i.id)).toEqual([1]);
    expect(matches(items, "scott air").map((i) => i.id)).toEqual([2]);
    expect(matches(items, "")).toEqual([]);
  });
  it("moves with the arrows and chooses with Enter", () => {
    const onChange = vi.fn();
    render(<SearchPick label="Track" items={items} value={0} onChange={onChange} />);
    const input = screen.getByRole("combobox");
    fireEvent.change(input, { target: { value: "t" } }); // matches all three ("Rhône", "Scott", "ATTLAS")
    fireEvent.keyDown(input, { key: "ArrowDown" });
    fireEvent.keyDown(input, { key: "Enter" });
    expect(onChange).toHaveBeenCalledWith(2);
  });
  it("says when nothing matches", () => {
    render(<SearchPick label="Track" items={items} value={0} onChange={() => undefined} />);
    fireEvent.change(screen.getByRole("combobox"), { target: { value: "zzz" } });
    expect(screen.getByText("No match")).toBeTruthy();
  });
});
