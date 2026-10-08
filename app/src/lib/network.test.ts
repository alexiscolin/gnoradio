import { describe, expect, it } from "vitest";
import { endpoints } from "./network";

describe("endpoints", () => {
  it("presets each network", () => {
    expect(endpoints({ VITE_NETWORK: "mainnet" }, "dev")).toEqual({
      network: "mainnet", chainId: "gnoland-1", rpc: "https://rpc.gno.land:443", walletRpc: "https://rpc.gno.land:443", gnoweb: "https://gno.land",
    });
    expect(endpoints({ VITE_NETWORK: "onyx" }, "dev")).toMatchObject({ chainId: "onyx-1", rpc: "https://rpc.onyx.testnets.gno.land:443", gnoweb: "https://onyx.testnets.gno.land" });
    expect(endpoints({}, "dev", "10.0.0.2")).toEqual({
      network: "dev", chainId: "dev", rpc: "/rpc", walletRpc: "http://10.0.0.2:27157", gnoweb: "http://10.0.0.2:8911",
    });
  });

  it("falls back when VITE_NETWORK is unset or unknown", () => {
    expect(endpoints({}, "onyx").chainId).toBe("onyx-1");
    expect(endpoints({ VITE_NETWORK: "gnoland1" }, "onyx").network).toBe("onyx");
  });

  it("lets each variable override its preset value", () => {
    const e = endpoints({ VITE_NETWORK: "mainnet", VITE_RPC: "/rpc", VITE_GNOWEB: "https://example.org" }, "dev");
    expect(e).toMatchObject({ chainId: "gnoland-1", rpc: "/rpc", walletRpc: "https://rpc.gno.land:443", gnoweb: "https://example.org" });
  });
});
