import { afterEach, describe, expect, it, vi } from "vitest";

// links.ts reads the network and namespace when it loads: load it fresh per network.
async function linksOn(network: string, ns = "") {
  vi.resetModules();
  vi.stubEnv("VITE_NETWORK", network);
  vi.stubEnv("VITE_GNOWEB", undefined);
  vi.stubEnv("VITE_GNORADIO_NS", ns || undefined);
  return import("./links");
}

afterEach(() => { vi.unstubAllEnvs(); });

describe("gnoweb links", () => {
  it("point at the home render of each screen, on each network", async () => {
    for (const [network, host] of [["onyx", "https://onyx.testnets.gno.land"], ["mainnet", "https://gno.land"]] as const) {
      const l = await linksOn(network, "nym-alexiscolin000/gnoradio");
      const home = `${host}/r/nym-alexiscolin000/gnoradio/home/v1`;
      expect(l.gnowebOf({ k: "track", id: 8 })).toBe(`${home}:track/8`);
      expect(l.gnowebOf({ k: "artist", id: 3 })).toBe(`${home}:artist/3`);
      expect(l.gnowebOf({ k: "stations", live: 2 })).toBe(`${home}:station/2`);
      expect(l.gnowebOf({ k: "stations" })).toBe(`${home}:stations`);
      expect(l.gnowebOf({ k: "door", ticket: 4, holder: "g1x" })).toBe(`${home}:ticket/4`);
      expect(l.eventPage(1)).toBe(`${home}:event/1`);
      expect(l.ticketPage(7)).toBe(`${home}:ticket/7`);
    }
  });

  it("use the local gnoweb and the plain namespace on the devnet", async () => {
    const l = await linksOn("dev");
    expect(l.eventPage(1)).toMatch(/^http:\/\/[^/]+:8911\/r\/gnoradio\/home\/v1:event\/1$/);
  });
});
