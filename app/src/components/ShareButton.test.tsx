import { cleanup, fireEvent, render, screen } from "@testing-library/react";
import { afterEach, describe, expect, it } from "vitest";
import { ShareButton } from "./common";

afterEach(cleanup);

describe("ShareButton", () => {
  it("opens the share sheet with each network's link to this page", () => {
    render(<ShareButton title="Space MTV" />);
    fireEvent.click(screen.getByText("Share"));
    const x = screen.getByText("X").getAttribute("href") ?? "";
    expect(x).toContain("https://x.com/intent/post?");
    expect(x).toContain(encodeURIComponent(location.href));
    expect(screen.getByText("WhatsApp").getAttribute("href")).toContain(encodeURIComponent("Space MTV on GnoRadio"));
    fireEvent.click(screen.getByLabelText("Close"));
    expect(screen.queryByText("Bluesky")).toBeNull();
  });
});
