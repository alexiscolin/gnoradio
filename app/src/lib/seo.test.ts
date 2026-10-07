import { describe, expect, it } from "vitest";
import { pageTitle } from "./seo";

describe("pageTitle", () => {
  it("names screens", () => {
    expect(pageTitle({ k: "listen" }, "")).toBe("Community radio, open music · GnoRadio");
    expect(pageTitle({ k: "artist", id: 1 }, "Scott Buckley")).toBe("Scott Buckley · GnoRadio");
    expect(pageTitle({ k: "stations", live: 0 }, "")).toBe("Main live · GnoRadio");
    expect(pageTitle({ k: "library", genre: 3 }, "Ambient")).toBe("Ambient · GnoRadio");
    expect(pageTitle({ k: "track", id: 9 }, "")).toBe("GnoRadio"); // before the catalog loads
  });
});
