import { act } from "@testing-library/react";
import { hydrateRoot } from "react-dom/client";
import { renderToString } from "react-dom/server";
import { afterEach, describe, expect, it, vi } from "vitest";
import { useNames } from "./names";
import { usePlayable } from "./playable";
import { useNamedRefs } from "./refs";

// index.html ships the app's first render, which React takes over (main.tsx hydrateRoot): every external
// store a component reads needs its getServerSnapshot, or the server render throws and hydration warns.
function Stores() {
  const cat = useNamedRefs(null);
  const name = useNames([]);
  const { allDead } = usePlayable();
  return <p>{cat === null ? "none" : "cat"} {name("g1x")} {String(allDead)}</p>;
}

afterEach(() => { vi.restoreAllMocks(); });

describe("hydration", () => {
  it("renders on the server and hydrates the three external stores without a console error", async () => {
    const err = vi.spyOn(console, "error").mockImplementation(() => undefined);
    const html = renderToString(<Stores />);
    const root = document.createElement("div");
    root.innerHTML = html;
    document.body.append(root);
    await act(async () => { hydrateRoot(root, <Stores />); await Promise.resolve(); });
    expect(err).not.toHaveBeenCalled();
    root.remove();
  });
});
