import { afterEach, describe, expect, it, vi } from "vitest";
import { Tx, Wallet } from "@gnolang/tm2-js-client";
import { CHAIN_ID, REALMS } from "./gno";
import { ROLE_REFUSED, clearRoles, inSession, sessionCall, privileged, savedSession, signCall, startSession, usableSession } from "./session";

// Who holds GnoRadio's roles: "realm.Expr()" -> address (anything else holds none).
let roles: Record<string, string> = {};
const qeval = vi.fn((pkg: string, expr: string) => Promise.resolve(`(${JSON.stringify(roles[`${pkg}.${expr}`] ?? "")} .uverse.address)`));
const sign = vi.fn(() => Promise.resolve({ hash: "h", height: "1" }));
vi.mock("./gno", async (orig) => ({ ...(await orig<object>()), qeval: (pkg: string, expr: string) => qeval(pkg, expr), sign: () => sign() }));
// Node's own localStorage shadows jsdom's here (as in useWallet.test): an in-memory one.
const store = new Map<string, string>();
vi.stubGlobal("localStorage", {
  getItem: (k: string) => store.get(k) ?? null,
  setItem: (k: string, v: string) => { store.set(k, v); },
  removeItem: (k: string) => { store.delete(k); },
});
afterEach(() => { roles = {}; store.clear(); clearRoles(); qeval.mockClear(); });

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
      `"msgs":[{"@type":"/vm.m_call","args":["12"],"caller":"${MASTER}","func":"Like","max_deposit":"","pkg_path":"gno.land/r/gnoradio/catalog/v1","send":""}],"sequence":"3"}`;
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

describe("sessions and GnoRadio roles", () => {
  const ADMIN = "g1u7y667z64x2h7vc6fmpcprgey4ck233jaww9zq";
  const keep = (master: string) => { localStorage.setItem(`gnoradio.session.${CHAIN_ID}.${master}`, JSON.stringify({ key: "01".repeat(32), expires: Date.now() / 1000 + 3600 })); };

  it("finds the admins, the treasury, the owner and the guardian; a failed read counts as a role", async () => {
    expect(await privileged(MASTER)).toBe(false);
    for (const at of [`${REALMS.catalog}.Admin()`, `${REALMS.catalog}.Treasury()`, `${REALMS.radio}.Admin()`, `${REALMS.tickets}.Admin()`, `${REALMS.data}.Owner()`, `${REALMS.data}.Guardian()`]) {
      roles = { [at]: ADMIN };
      clearRoles();
      expect(await privileged(ADMIN), at).toBe(true);
      expect(await privileged(MASTER), at).toBe(false);
    }
    clearRoles();
    qeval.mockRejectedValueOnce(new Error("down"));
    expect(await privileged(MASTER)).toBe(true);
  });

  it("never starts a session for a role holder, and drops one it already holds", async () => {
    roles = { [`${REALMS.radio}.Admin()`]: ADMIN };
    await expect(startSession(ADMIN)).rejects.toThrow(ROLE_REFUSED);
    expect(sign).not.toHaveBeenCalled();
    keep(ADMIN);
    expect(await usableSession(ADMIN)).toBe(false);
    expect(savedSession(ADMIN)).toBeUndefined();
    // Revoked on chain before the key is dropped: it cannot stay live with the role's power.
    expect(sign).toHaveBeenCalledTimes(1);
    keep(MASTER);
    expect(await usableSession(MASTER)).toBe(true);
    expect(savedSession(MASTER)).toBeDefined();
  });

  it("revokes a role holder's session only when asked to, and asks once per page load", async () => {
    roles = { [`${REALMS.radio}.Admin()`]: ADMIN };
    keep(ADMIN);
    expect(await usableSession(ADMIN, false)).toBe(false); // the passive connect check: no prompt
    expect(sign).not.toHaveBeenCalled();
    expect(savedSession(ADMIN)).toBeDefined();
    sign.mockRejectedValueOnce(new Error("rejected"));
    expect(await usableSession(ADMIN)).toBe(false); // an action: one prompt, refused by the user
    expect(await usableSession(ADMIN)).toBe(false); // not again
    expect(sign).toHaveBeenCalledTimes(1);
    expect(savedSession(ADMIN)).toBeDefined(); // "Turn off" can still revoke it
  });

  it("keeps a listener's session when a role read fails: refuses this use only", async () => {
    keep(MASTER);
    qeval.mockRejectedValueOnce(new Error("down"));
    expect(await usableSession(MASTER)).toBe(false);
    expect(savedSession(MASTER)).toBeDefined();
    expect(await usableSession(MASTER)).toBe(true);
  });

  it("reads the roles once per address for a few minutes, and sessionCall does not read them again", async () => {
    keep(MASTER);
    expect(await usableSession(MASTER)).toBe(true);
    expect(qeval).toHaveBeenCalledTimes(9);
    expect(await usableSession(MASTER)).toBe(true);
    expect(await privileged(MASTER)).toBe(false);
    expect(qeval).toHaveBeenCalledTimes(9);
    const net = vi.spyOn(globalThis, "fetch").mockRejectedValue(new Error("offline"));
    await expect(sessionCall(MASTER, { pkg: REALMS.catalog, func: "Like", args: ["1"] })).rejects.toThrow("offline");
    net.mockRestore();
    expect(qeval).toHaveBeenCalledTimes(9);
  });
});

describe("sessionCall when the session account cannot be read", () => {
  const keep = () => { localStorage.setItem(`gnoradio.session.${CHAIN_ID}.${MASTER}`, JSON.stringify({ key: "01".repeat(32), expires: Date.now() / 1000 + 3600 })); };
  const answer = (ResponseBase: object) => vi.spyOn(globalThis, "fetch").mockResolvedValue(new Response(JSON.stringify({ result: { response: { ResponseBase } } })));
  const like = { pkg: REALMS.catalog, func: "Like", args: ["1"] };

  it("keeps the key on a transient node error, so the session can still be revoked", async () => {
    keep();
    answer({ Error: { "@type": "/std.InternalError" }, Data: null, Log: "node is busy" });
    await expect(sessionCall(MASTER, like)).rejects.toThrow("Try again");
    expect(savedSession(MASTER)).toBeDefined();
  });

  it("forgets the key when the chain says the session expired", async () => {
    keep();
    answer({ Error: { "@type": "/std.UnauthorizedError" }, Data: null, Log: "session expired" });
    await expect(sessionCall(MASTER, like)).rejects.toThrow("Quick actions ended");
    expect(savedSession(MASTER)).toBeUndefined();
  });
});
