import { describe, expect, it } from "vitest";
import { clean, scrub } from "./analytics";

describe("analytics scrubbing", () => {
  it("never lets an address, a name, a key or a ref link out", () => {
    expect(scrub("https://gnoradio.app/listener/indigo-g1jg8mtutu9khhfwc4nxmuhcpftf0pajdhfvsqf5?ref=g1jg8mtutu9khhfwc4nxmuhcpftf0pajdhfvsqf5"))
      .toBe("https://gnoradio.app/listener/indigo-g1…");
    expect(scrub("picked by nym-alexiscolin000")).toBe("picked by nym-…");
    expect(scrub(`key ${"ab".repeat(32)}`)).toBe("key hex…");
  });
  it("scrubs every string of an event, nested", () => {
    const e = clean({ uuid: "1", event: "x", properties: { $current_url: "https://a.b/door/3-g1jg8mtutu9khhfwc4nxmuhcpftf0pajdhfvsqf5", list: ["g1jg8mtutu9khhfwc4nxmuhcpftf0pajdhfvsqf5"] } });
    expect(JSON.stringify(e)).not.toMatch(/g1[0-9a-z]{38}/);
    expect(e?.properties["app"]).toBe("gnoradio"); // the project is shared with gnogolf
  });
});
