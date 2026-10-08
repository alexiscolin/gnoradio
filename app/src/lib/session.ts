// Quick actions: a gno.land account session (tm2 auth, live on onyx and mainnet).
// The user approves once, in Adena, a key this browser made: it may only call
// GnoRadio's catalog and radio realms, spend at most DAILY_UGNOT a day (fees and
// storage deposits) and expires after DAYS. Calls with it are signed here, no
// prompt; the realm sees the user's own address as the caller. The key never
// leaves this browser; Turn off revokes it on-chain.
//
// What a stolen key (an extension or script reading localStorage) can do: the
// chain scopes allow_paths to a realm, never to a function, so the key may call
// ANY function of catalog and radio as the user, until it expires or is revoked.
// spend_limit caps only what leaves the account (fees, deposits, sent coins), not
// what a call changes: for an artist that includes EditTrack, SetPromoShare and
// the other artist settings. So sessions are refused to every address holding a
// GnoRadio role (admin of a realm, treasury, release owner or guardian), whose
// calls change the whole station rather than one listener's account; such an
// address signs everything in Adena. inSession keeping payments on Adena is this
// app's choice too. The daily cap is sized for fees and deposits (measured: a pick
// about 0.07 GNOT fee + up to 0.9 deposit, a like 0.05 + 0.3): about a dozen
// listener actions a day.

import { CHAIN_ID, REALMS, RPC, type Call, type RealmPath, type SessionKey, type TxResult, qeval, sign } from "./gno";
import { feeFor, gasFor } from "./gnokey";

export const DAYS = 7;
export const DAILY_UGNOT = 10_000_000;
const REALMS_ALLOWED: readonly RealmPath[] = [REALMS.catalog, REALMS.radio];

interface Saved {
  readonly key: string; // hex secp256k1 private key
  readonly expires: number; // unix seconds
}

const slot = (master: string) => `gnoradio.session.${CHAIN_ID}.${master}`;
const hex = (b: Uint8Array) => Array.from(b, (x) => x.toString(16).padStart(2, "0")).join("");
const unhex = (s: string) => Uint8Array.from(s.match(/../g) ?? [], (x) => parseInt(x, 16));

/** savedSession is this browser's live session for master, if any. */
export function savedSession(master: string): Saved | undefined {
  try {
    const s = JSON.parse(localStorage.getItem(slot(master)) ?? "null") as Saved | null;
    return s && s.expires > Date.now() / 1000 ? s : undefined;
  } catch {
    return undefined;
  }
}

const forget = (master: string) => { try { localStorage.removeItem(slot(master)); } catch { /* nothing kept */ } };

// The GnoRadio roles a session must never act for, held or offered: each read returns one address.
const ROLES: readonly (readonly [RealmPath, string])[] = [
  [REALMS.catalog, "Admin()"], [REALMS.catalog, "Treasury()"], [REALMS.radio, "Admin()"],
  [REALMS.tickets, "Admin()"], [REALMS.data, "Owner()"], [REALMS.data, "Guardian()"],
  // an offered role counts too: AcceptAdmin needs only the offered address
  [REALMS.catalog, "PendingAdmin()"], [REALMS.radio, "PendingAdmin()"], [REALMS.tickets, "PendingAdmin()"],
];

// A role read is kept a few minutes per address: every quick action checks it.
const ROLE_TTL = 5 * 60_000;
const roleSeen = new Map<string, { readonly held: boolean; readonly at: number }>();
/** clearRoles drops the kept role reads (tests). */
export const clearRoles = (): void => { roleSeen.clear(); revokeTried.clear(); };
const revokeTried = new Set<string>(); // masters whose revoke was asked this page load: a rejected prompt is not repeated

/** holdsRole reads whether master holds a GnoRadio role; it throws when a read fails (never cached). */
async function holdsRole(master: string): Promise<boolean> {
  const seen = roleSeen.get(master);
  if (seen && Date.now() - seen.at < ROLE_TTL) return seen.held;
  const held = (await Promise.all(ROLES.map(([pkg, expr]) => qeval(pkg, expr)))).some((raw) => raw.includes(`"${master}"`));
  roleSeen.set(master, { held, at: Date.now() });
  return held;
}

/**
 * privileged tells whether master holds a GnoRadio role (realm admin, treasury,
 * release owner or guardian). A failed read counts as yes: sessions fail closed.
 * The robot keys (SetBot, SetModBot) are Ed25519 certificate keys, not accounts:
 * no session can stand for them.
 */
export async function privileged(master: string): Promise<boolean> {
  try {
    return await holdsRole(master);
  } catch {
    return true;
  }
}

/**
 * usableSession is master's session if it may be used now. A confirmed role
 * revokes it on chain, then forgets it; a failed role read only refuses this
 * use, so one flaky RPC read never costs a listener their key. The revoke is an Adena
 * prompt: only a caller acting on a click passes revoke, and it asks once per page load.
 */
export async function usableSession(master: string, revoke = true): Promise<boolean> {
  if (!savedSession(master)) return false;
  let held: boolean;
  try {
    held = await holdsRole(master);
  } catch {
    return false;
  }
  if (!held) return true;
  if (!revoke || revokeTried.has(master)) return false;
  revokeTried.add(master);
  // A session made before the address got its role would act for that role: revoke it on chain
  // (one Adena prompt), and forget the key only once that worked, so "Turn off" can still revoke it.
  await endSession(master).catch(() => undefined);
  return false;
}

export const ROLE_REFUSED = "Quick actions are off for GnoRadio's admin, treasury, owner and guardian addresses: sign in Adena.";

/** inSession tells whether c may go through the session: no coins sent, a GnoRadio realm. */
export const inSession = (c: Call): boolean => !c.send && REALMS_ALLOWED.includes(c.pkg);

// The signing libraries are only loaded by the users who turn sessions on.
async function keyOf(key: Uint8Array) {
  const [gno, tm2] = await Promise.all([import("@gnolang/gno-js-client"), import("@gnolang/tm2-js-client")]);
  const signer = (await tm2.Wallet.fromPrivateKey(key)).getSigner();
  const pub = gno.secp256k1PubKeyToAny(await signer.getPublicKey());
  const sessionKey: SessionKey = { type_url: pub.type_url, value: [...pub.value] };
  return { gno, tm2, signer, pub, sessionKey };
}

/** startSession makes a key in this browser and has Adena approve it as master's session. */
export async function startSession(master: string): Promise<void> {
  if (await privileged(master)) throw new Error(ROLE_REFUSED);
  const key = crypto.getRandomValues(new Uint8Array(32));
  const { sessionKey } = await keyOf(key);
  const expires = Math.floor(Date.now() / 1000) + DAYS * 86_400;
  await sign([{
    type: "/auth.m_create_session",
    value: {
      creator: master,
      session_key: sessionKey,
      expires_at: String(expires),
      allow_paths: REALMS_ALLOWED.map((p) => `vm/exec:${p}`),
      spend_limit: `${String(DAILY_UGNOT)}ugnot`,
      spend_period: "86400",
    },
  }]);
  localStorage.setItem(slot(master), JSON.stringify({ key: hex(key), expires } satisfies Saved));
}

/** endSession revokes master's session on-chain (one Adena prompt), then forgets the key. */
export async function endSession(master: string): Promise<void> {
  const s = savedSession(master);
  if (s) await sign([{ type: "/auth.m_revoke_session", value: { creator: master, session_key: (await keyOf(unhex(s.key))).sessionKey } }]);
  forget(master);
}

interface AbciBase { Error: unknown; Data: string | null; Log: string }
interface Broadcast { check_tx: { ResponseBase: AbciBase }; deliver_tx: { ResponseBase: AbciBase }; hash: string; height: string }

async function rpc<T>(method: string, params: object): Promise<T> {
  const res = await fetch(RPC, { method: "POST", headers: { "content-type": "application/json" }, body: JSON.stringify({ jsonrpc: "2.0", id: 1, method, params }) });
  const body = (await res.json()) as { result?: T; error?: { data?: string; message?: string } };
  if (!body.result) throw new Error(body.error?.data ?? body.error?.message ?? `RPC returned ${String(res.status)}`);
  return body.result;
}

const b64 = (b: Uint8Array) => btoa(String.fromCharCode(...b));

/**
 * signCall signs c for master with key, as session sessionAddr at its account
 * number and sequence. The sign doc is the legacy one (fee as gas_wanted and
 * gas_fee), the only one mainnet verifies and one onyx still accepts.
 */
export async function signCall(key: Uint8Array, master: string, c: Call, at: { accountNumber: string; sequence: string }, chainId = CHAIN_ID): Promise<Uint8Array> {
  const { gno, tm2, signer, pub } = await keyOf(key);
  const gas = gasFor(c.func);
  const fee = { gas_wanted: BigInt(gas), gas_fee: `${String(feeFor(gas))}ugnot` };
  const messages = [{
    type_url: "/vm.m_call",
    value: gno.MsgCall.encode({ caller: master, send: "", max_deposit: "", pkg_path: c.pkg, func: c.func, args: [...c.args] }).finish(),
  }];
  const doc = {
    chain_id: chainId,
    account_number: at.accountNumber,
    sequence: at.sequence,
    fee: { gas_wanted: String(gas), gas_fee: fee.gas_fee },
    msgs: gno.decodeTxMessages(messages),
    memo: "gnoradio",
  };
  const signature = await signer.signData(new TextEncoder().encode(tm2.encodeCharacterSet(tm2.sortedJsonStringify(doc))));
  // session_addr is not signed: it tells the chain which of master's sessions signed.
  const session_addr = await signer.getAddress();
  return tm2.Tx.encode({ messages, fee, memo: "gnoradio", signatures: [{ pub_key: pub, signature, session_addr }] }).finish();
}

/** sessionCall signs c with master's session key and broadcasts it, no prompt. The caller checks usableSession first (once per action). */
export async function sessionCall(master: string, c: Call): Promise<TxResult> {
  const s = savedSession(master);
  if (!s) throw new Error("Quick actions are off.");
  const key = unhex(s.key);
  const { gno, signer } = await keyOf(key);
  const sessionAddr = await signer.getAddress();
  // The session account holds its own number and sequence, under the master account.
  const q = await rpc<{ response: { ResponseBase: AbciBase } }>("abci_query", { path: `auth/accounts/${master}/session/${sessionAddr}`, data: "" });
  const found = q.response.ResponseBase;
  if (found.Error || !found.Data) {
    // Forget the key only when the chain says the session is gone (revoked elsewhere or expired: back to Adena);
    // a node hiccup keeps it, or the live session could no longer be revoked from here.
    if (/session expired|unknown session/.test(JSON.stringify(found.Error ?? "") + found.Log)) {
      forget(master);
      throw new Error("Quick actions ended. Turn them on again, or sign with Adena.");
    }
    throw new Error("Could not check Quick actions just now. Try again in a moment.");
  }
  const acc = gno.normalizeSessionAccount(JSON.parse(atob(found.Data)));
  const tx = await signCall(key, master, c, { accountNumber: acc.account_number ?? "0", sequence: acc.sequence ?? "0" });
  const res = await rpc<Broadcast>("broadcast_tx_commit", { tx: b64(tx) });
  const failed = [res.check_tx.ResponseBase, res.deliver_tx.ResponseBase].find((r) => r.Error);
  if (failed) {
    if (failed.Log.includes("spend limit exceeded")) throw new Error(`Quick actions spent today's ${String(DAILY_UGNOT / 1e6)} GNOT. Turn them off to sign with Adena, or wait a day.`);
    if (/session expired|unknown session/.test(failed.Log)) forget(master);
    throw new Error(failed.Log || "The transaction failed on-chain.");
  }
  return { hash: res.hash, height: res.height };
}
