import { afterEach, describe, expect, it, vi } from "vitest";
import { AdenaError, call, connect, isCancel, switchNetwork } from "./gno";

interface Res { code: number; status: "success" | "failure"; type: string; message: string; data?: unknown }
const ok = (type: string, data?: unknown): Res => ({ code: 0, status: "success", type, message: "", data });
const ko = (code: number, type: string): Res => ({ code, status: "failure", type, message: type });

function installAdena(over: Record<string, (...a: unknown[]) => Promise<Res>>) {
  const base = {
    AddEstablish: vi.fn(() => Promise.resolve(ok("CONNECTION_SUCCESS"))),
    GetAccount: vi.fn(() => Promise.resolve(ok("GET_ACCOUNT", { address: "g1jg8mtutu9khhfwc4nxmuhcpftf0pajdhfvsqf5", chainId: "dev" }))),
    AddNetwork: vi.fn(() => Promise.resolve(ok("ADD_NETWORK_SUCCESS"))),
    SwitchNetwork: vi.fn(() => Promise.resolve(ok("SWITCH_NETWORK_SUCCESS"))),
    DoContract: vi.fn(() => Promise.resolve(ok("TRANSACTION_SUCCESS", { hash: "abc+/=", height: "42" }))),
  };
  const adena = { ...base, ...over };
  vi.stubGlobal("adena", adena);
  Object.defineProperty(window, "adena", { value: adena, configurable: true });
  return adena;
}

afterEach(() => {
  vi.unstubAllGlobals();
  Reflect.deleteProperty(window, "adena");
});

describe("Adena client", () => {
  it("treats an existing connection as success", async () => {
    installAdena({ AddEstablish: () => Promise.resolve(ko(4001, "ALREADY_CONNECTED")) });
    await expect(connect()).resolves.toMatchObject({ address: expect.stringMatching(/^g1/) as unknown as string });
  });
  it("reports a rejected connection as a cancel", async () => {
    installAdena({ AddEstablish: () => Promise.resolve(ko(4000, "CONNECTION_REJECTED")) });
    const err: unknown = await connect().catch((e: unknown) => e);
    expect(err).toBeInstanceOf(AdenaError);
    expect(isCancel(err)).toBe(true);
  });
  it("does nothing when already on the right network", async () => {
    const a = installAdena({ SwitchNetwork: () => Promise.resolve(ko(4001, "REDUNDANT_CHANGE_REQUEST")) });
    await expect(switchNetwork()).resolves.toBeUndefined();
    expect(a.AddNetwork).not.toHaveBeenCalled();
  });
  it("adds the network only when it is missing", async () => {
    const switches = [ko(4001, "UNADDED_NETWORK"), ok("SWITCH_NETWORK_SUCCESS")];
    const a = installAdena({ SwitchNetwork: () => Promise.resolve(switches.shift() ?? ok("SWITCH_NETWORK_SUCCESS")) });
    await switchNetwork();
    expect(a.AddNetwork).toHaveBeenCalledOnce();
  });
  it("does not add the network when the user refuses the switch", async () => {
    const a = installAdena({ SwitchNetwork: () => Promise.resolve(ko(4000, "SWITCH_NETWORK_REJECTED")) });
    await expect(switchNetwork()).rejects.toThrow("Network switch cancelled.");
    expect(a.AddNetwork).not.toHaveBeenCalled();
  });
  it("returns the tx hash and height", async () => {
    installAdena({});
    await expect(call("g1x", { pkg: "gno.land/r/gnoradio/catalog/v0", func: "Like", args: ["1"] })).resolves.toMatchObject({ hash: "abc+/=", height: "42" });
  });
  it("surfaces an on-chain failure", async () => {
    installAdena({ DoContract: () => Promise.resolve(ok("TRANSACTION_SUCCESS", { hash: "h", height: "1", deliverTx: { ResponseBase: { Error: {}, Log: "catalog: already liked" } } })) });
    await expect(call("g1x", { pkg: "gno.land/r/gnoradio/catalog/v0", func: "Like", args: ["1"] })).rejects.toThrow("catalog: already liked");
  });
});
