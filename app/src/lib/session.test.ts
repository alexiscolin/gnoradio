import { describe, expect, it } from "vitest";
import { Tx, Wallet } from "@gnolang/tm2-js-client";
import { REALMS } from "./gno";
import { inSession, signCall } from "./session";

const MASTER = "g1jg8mtutu9khhfwc4nxmuhcpftf0pajdhfvsqf5";
const KEY = Uint8Array.from({ length: 32 }, (_, i) => i + 1); // a throwaway test key

describe("signCall", () => {
  it("signs the legacy sign doc with the session's number and sequence, and names the session", async () => {
    const bytes = await signCall(KEY, MASTER, { pkg: REALMS.catalog, func: "Like", args: ["12"] }, { accountNumber: "7", sequence: "3" }, "onyx-1");
    const tx = Tx.decode(bytes);
    const signer = (await Wallet.fromPrivateKey(KEY)).getSigner();
    const sig = tx.signatures[0];
    expect(sig?.session_addr).toBe(await signer.getAddress());
    // What the chain rebuilds and verifies (std.GetSignaturePayloadLegacy, amino JSON, sorted keys).
    const doc =
      `{"account_number":"7","chain_id":"onyx-1","fee":{"gas_fee":"40000ugnot","gas_wanted":"40000000"},"memo":"gnoradio",` +
      `"msgs":[{"@type":"/vm.m_call","args":["12"],"caller":"${MASTER}","func":"Like","max_deposit":"","pkg_path":"gno.land/r/gnoradio/catalog/v0","send":""}],"sequence":"3"}`;
    expect(await signer.verifySignature(new TextEncoder().encode(doc), sig?.signature ?? new Uint8Array())).toBe(true);
    expect(tx.fee).toEqual({ gas_wanted: 40_000_000n, gas_fee: "40000ugnot" });
  });
});

describe("inSession", () => {
  it("takes GnoRadio calls without coins, never a payment or another realm", () => {
    expect(inSession({ pkg: REALMS.catalog, func: "Like", args: ["1"] })).toBe(true);
    expect(inSession({ pkg: REALMS.radio, func: "Queue", args: ["1", "2"] })).toBe(true);
    expect(inSession({ pkg: REALMS.catalog, func: "TipWithSupport", args: ["1", "10"], send: 1_000_000 })).toBe(false);
    expect(inSession({ pkg: REALMS.tickets, func: "BuyTicket", args: ["1"] })).toBe(false);
  });
});
