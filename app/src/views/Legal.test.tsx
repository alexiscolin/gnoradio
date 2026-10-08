import { cleanup, render, screen } from "@testing-library/react";
import { afterEach, expect, it } from "vitest";
import { FeesContext } from "../lib/fees";
import { Legal } from "./Legal";

afterEach(cleanup);

it("tells what the browser keeps, the sharer's address and how long included", () => {
  render(<Legal />);
  expect(screen.getByText(/for 7 days, the address of whoever shared the link that brought you/)).toBeTruthy();
  expect(screen.getByText(/signs for you until it expires \(7 days\)/)).toBeTruthy();
  expect(screen.queryByText(/small actions/)).toBeNull();
});

it("says no fee, or names the treasury once fees are on", () => {
  render(<Legal />);
  expect(screen.getByText(/GnoRadio takes no fee: tips and ticket prices go 100% to the artist\./)).toBeTruthy();
  expect(document.body.textContent).not.toMatch(/service fees/);
  cleanup();
  render(<FeesContext.Provider value><Legal /></FeesContext.Provider>);
  expect(screen.getByText(/Support and service fees go to the treasury/)).toBeTruthy();
});
