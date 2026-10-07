import { renderToStaticMarkup } from "react-dom/server";
import { describe, expect, it } from "vitest";
import html from "../../index.html?raw";
import { Splash } from "./Splash";

describe("Splash", () => {
  it("is in index.html exactly as App first renders it, so React takes it over without a restart", () => {
    const f = () => undefined;
    expect(html).toContain(`<div id="root">${renderToStaticMarkup(<Splash ready={false} error="" onLeave={f} onDone={f} onRetry={f} />)}</div>`);
  });
});
