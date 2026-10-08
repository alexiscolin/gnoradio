import { cleanup, render, screen } from "@testing-library/react";
import { afterEach, expect, it } from "vitest";
import { Legal } from "./Legal";

afterEach(cleanup);

it("tells what the browser keeps, the sharer's address and how long included", () => {
  render(<Legal />);
  expect(screen.getByText(/for 7 days, the address of whoever shared the link that brought you/)).toBeTruthy();
  expect(screen.getByText(/signs for you until it expires \(7 days\)/)).toBeTruthy();
  expect(screen.queryByText(/small actions/)).toBeNull();
});
