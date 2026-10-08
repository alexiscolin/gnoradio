import { cleanup, fireEvent, render, screen } from "@testing-library/react";
import { afterEach, describe, expect, it } from "vitest";
import { Help } from "./Help";

afterEach(cleanup);

describe("Help", () => {
  it("is read with its button and closes on Escape without closing what holds it", () => {
    let outer = 0;
    window.addEventListener("keydown", () => { outer++; });
    render(<Help text="One short sentence." more="/about" />);
    const q = screen.getByRole("button", { name: "Help" });
    fireEvent.focus(q);
    const pop = screen.getByRole("tooltip");
    expect(q.getAttribute("aria-describedby")).toBe(pop.id);
    fireEvent.click(q);
    expect(document.activeElement?.textContent).toBe("Learn more"); // reachable from the keyboard
    fireEvent.keyDown(document.activeElement ?? document.body, { key: "Escape" });
    expect(screen.queryByRole("tooltip")).toBeNull();
    expect(outer).toBe(0); // the sheet's own Escape handler never saw it
  });
});
