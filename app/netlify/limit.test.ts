import { describe, expect, it } from "vitest";
import { clientKey } from "./limit";

describe("clientKey", () => {
  it("keeps an IPv4 address whole", () => {
    expect(clientKey("203.0.113.9")).toBe("203.0.113.9");
    expect(clientKey("::ffff:203.0.113.9")).toBe("203.0.113.9");
  });
  it("gives every address of an IPv6 /64 one key, compressed or not", () => {
    const k = clientKey("2001:db8:1:2:aaaa:bbbb:cccc:dddd");
    expect(k).toBe("2001:db8:1:2");
    expect(clientKey("2001:0DB8:1:2::1")).toBe(k);
    expect(clientKey("2001:db8:1:2::2")).toBe(k);
    expect(clientKey("2001:db8::1")).toBe(clientKey("2001:db8::2")); // "::" holds the /64's zero groups
    expect(clientKey("2001:db8::1")).not.toBe(clientKey("2001:db9::1"));
  });
});
