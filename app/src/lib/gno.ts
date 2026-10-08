// Minimal gno.land client: reads realm JSON exports through vm/qeval and
// sends transactions through the Adena wallet (or a session, or gnokey). Listening never touches it.

import { check, type Guard } from "./guard";
import { MAX_NOTE } from "./moderation";
import { endpoints } from "./network";
import { isAddress, unquote } from "./proof";
import { REALMS, SAFE } from "./realms";
import { utf8Base64 } from "./format";

export { MAX_NOTE, REALMS, SAFE, unquote };

/** NET: the chain this build talks to (lib/network.ts); a production build without VITE_NETWORK is onyx. */
// (No window when the build prerenders /features: the host only matters on a devnet.)
const NET = endpoints(import.meta.env, import.meta.env.PROD ? "onyx" : "dev", typeof window === "undefined" ? undefined : window.location.hostname);
export const RPC = NET.rpc;
export const CHAIN_ID = NET.chainId;

/** networkLabel names a non-mainnet chain for the network badge; "" on mainnet. */
export function networkLabel(chainId: string): string {
  if (chainId === "gnoland-1") return "";
  if (chainId === "dev") return "Local devnet";
  if (/^(onyx|test)/.test(chainId)) return `Testnet · ${chainId}`;
  return chainId;
}

/** A gno.land package path: GnoRadio's realms (REALMS, by release), the system realms (SysPath), SAFE. */
export type RealmPath = `gno.land/${string}`;
/** gno.land system realms the app reads: names (r/sys/users) and the name registrar. */
export type SysPath = "gno.land/r/sys/users" | "gno.land/r/sys/namereg/v0" | "gno.land/r/sys/namereg/v1" | typeof SAFE;

/** noteProblem is why a dedication would be refused ("" when fine): a free read. */
export async function noteProblem(note: string): Promise<string> {
  return note === "" ? "" : unquote(await qeval(SAFE, `Note(${JSON.stringify(note)}, ${String(MAX_NOTE)})`));
}

const fromBase64 = (s: string) => new TextDecoder().decode(Uint8Array.from(atob(s), (c) => c.charCodeAt(0)));

interface AbciResponse {
  id?: unknown;
  result?: { response?: { ResponseBase?: { Error: unknown; Data: string | null; Log: string } } };
}

/** RealmError is a panic or error returned by the realm itself (unknown id, hidden item…). */
export class RealmError extends Error {
  override name = "RealmError";
}

/** DataError is a reply that does not parse or match its schema: one bad record, not an outage. */
export class DataError extends Error {
  override name = "DataError";
}

const TIMEOUT_MS = 8000;

// At most MAX_INFLIGHT requests at once, so a big catalog never floods the public RPC.
const MAX_INFLIGHT = 6;
// Queries issued together go out as JSON-RPC batches of BATCH. The node answers a batch's
// queries one after the other: small batches keep its parallelism and the requests few.
const BATCH = 4;
let inflight = 0;
const waiting: (() => void)[] = [];

async function slot<T>(fn: () => Promise<T>): Promise<T> {
  if (inflight >= MAX_INFLIGHT) await new Promise<void>((r) => { waiting.push(r); });
  inflight++;
  try {
    return await fn();
  } finally {
    inflight--;
    waiting.shift()?.();
  }
}

const sleep = (ms: number) => new Promise((r) => setTimeout(r, ms));

/** GNOWEB is the gnoweb site for links to realm pages (the local gnodev web in development). */
export const GNOWEB = NET.gnoweb;

/** qeval runs `pkg.expr` read-only and returns the raw typed result, e.g. `("…" string)`. */
export async function qeval(pkg: RealmPath, expr: string): Promise<string> {
  for (let attempt = 0; ; attempt++) {
    try {
      return await qevalOnce(pkg, expr);
    } catch (e) {
      // Retry rate limits, timeouts and network errors with backoff; realm errors are final.
      if (e instanceof RealmError || attempt >= 3) throw e;
      await sleep(400 * 2 ** attempt);
    }
  }
}

interface Query {
  readonly data: string;
  readonly done: (r: AbciResponse | undefined) => void;
  readonly fail: (e: unknown) => void;
}
let queued: Query[] = [];
// Off for the rest of the visit once a batch fails as a whole (network, any HTTP error, not an array).
let batching = true;

function qevalOnce(pkg: RealmPath, expr: string): Promise<string> {
  return new Promise<AbciResponse | undefined>((done, fail) => {
    // Queries issued in the same tick (a catalog load) share a few requests.
    if (queued.length === 0) queueMicrotask(flush);
    queued.push({ data: utf8Base64(`${pkg}.${expr}`), done, fail });
  }).then((r) => {
    const base = r?.result?.response?.ResponseBase;
    if (!base) throw new Error("RPC unreachable");
    if (base.Error) throw new RealmError(base.Log || "query failed");
    return fromBase64(base.Data ?? "");
  });
}

function flush() {
  const qs = queued;
  queued = [];
  const size = batching ? BATCH : 1;
  for (let i = 0; i < qs.length; i += size) void slot(() => send(qs.slice(i, i + size)));
}

async function send(qs: readonly Query[]): Promise<void> {
  const req = (q: Query, id: number) => ({ jsonrpc: "2.0", id, method: "abci_query", params: { path: "vm/qeval", data: q.data } });
  let reply: unknown;
  try {
    const res = await fetch(RPC, {
      method: "POST",
      headers: { "content-type": "application/json" },
      body: JSON.stringify(qs.length === 1 && qs[0] ? req(qs[0], 0) : qs.map(req)),
      // A hung node must not hold one of the few request slots forever; a batch gets the time of its queries.
      signal: AbortSignal.timeout(TIMEOUT_MS * qs.length),
    });
    if (!res.ok) throw new Error(`RPC returned ${String(res.status)}`);
    reply = await res.json();
    if (qs.length > 1 && !Array.isArray(reply)) throw new Error("RPC does not batch");
  } catch (e) {
    if (qs.length === 1) {
      // A throttled, failing or slow node: the query fails and qeval backs off and retries it.
      qs[0]?.fail(e);
      return;
    }
    // A batch that fails as a whole (network, 4xx, 5xx, not an array): one query per
    // request for the rest of the visit, these retried one by one.
    batching = false;
    queued.push(...qs);
    flush();
    return;
  }
  if (qs.length === 1) {
    qs[0]?.done(reply as AbciResponse);
    return;
  }
  // Each query settles on its own reply: a refused or missing one never fails the others.
  const byId = new Map((reply as AbciResponse[]).map((r) => [r.id, r]));
  qs.forEach((q, i) => { q.done(byId.get(i)); });
}

/** qjson evaluates a realm function returning a JSON string, parses it and validates it with guard. */
export async function qjson<T>(pkg: RealmPath, expr: string, guard: Guard<T>): Promise<T> {
  const raw = await qeval(pkg, expr);
  try {
    const quoted = /^\((".*") string\)$/s.exec(raw)?.[1];
    if (quoted === undefined) throw new Error(`Unexpected result from ${expr}`);
    const inner: unknown = JSON.parse(quoted);
    if (typeof inner !== "string") throw new Error(`Unexpected result from ${expr}`);
    return check(JSON.parse(inner), guard, expr);
  } catch (e) {
    throw new DataError(e instanceof Error ? e.message : String(e));
  }
}

/** gnoAddress quotes a validated address for a qeval expression. */
export function gnoAddress(a: string): string {
  if (!isAddress(a)) throw new Error("Invalid gno.land address");
  return JSON.stringify(a);
}

// ---- Adena (optional, only for writes) ----
// API per docs.adena.app and onbloc/adena-wallet src/inject.ts.

/** RPC the wallet itself must reach (the dev proxy /rpc is only for the page). */
export const WALLET_RPC = NET.walletRpc;
const CHAIN_NAME = CHAIN_ID === "dev" ? "GnoRadio devnet" : `gno.land ${CHAIN_ID}`;

interface AdenaResponse<T> {
  readonly code: number;
  readonly status: "success" | "failure";
  readonly type: string;
  readonly message: string;
  readonly data?: T;
}

export interface AdenaAccount {
  readonly accountNumber?: string;
  readonly address: string;
  readonly coins?: string;
  readonly chainId: string;
  readonly sequence?: string;
  readonly status?: "ACTIVE" | "IN_ACTIVE";
}

export interface TxResult {
  readonly hash: string;
  readonly height: string;
  readonly deliverTx?: { readonly ResponseBase?: { readonly Error?: unknown; readonly Log?: string } };
}

type AdenaEvent = "changedAccount" | "changedNetwork";

/** A message Adena signs: a realm call, or (Adena 1.22+) an account session's creation or revocation. */
export type AdenaMessage =
  | { type: "/vm.m_call"; value: { caller: string; send: string; pkg_path: string; func: string; args: string[] } }
  | { type: "/auth.m_create_session"; value: { creator: string; session_key: SessionKey; expires_at: string; allow_paths: string[]; spend_limit: string; spend_period: string } }
  | { type: "/auth.m_revoke_session"; value: { creator: string; session_key: SessionKey } };
/** SessionKey is a secp256k1 public key as an Any, its bytes as numbers (they cross Adena's message channel as JSON). */
export interface SessionKey { type_url: string; value: number[] }

interface AdenaWallet {
  AddEstablish(name: string, chainIds?: string | string[]): Promise<AdenaResponse<unknown>>;
  GetAccount(): Promise<AdenaResponse<AdenaAccount>>;
  AddNetwork(net: { chainId: string; chainName: string; rpcUrl: string }): Promise<AdenaResponse<unknown>>;
  SwitchNetwork(chainId: string): Promise<AdenaResponse<unknown>>;
  On?: (event: AdenaEvent, cb: (value: string) => void) => boolean;
  DoContract(tx: { messages: AdenaMessage[]; memo?: string }): Promise<AdenaResponse<TxResult>>;
}

declare global {
  interface Window {
    adena?: AdenaWallet;
  }
}

/** AdenaError carries Adena's response type so the UI can react (rejected, locked…). */
export class AdenaError extends Error {
  constructor(
    message: string,
    readonly type: string,
    readonly code: number,
  ) {
    super(message);
    this.name = "AdenaError";
  }
}

const FRIENDLY: Record<string, string> = {
  CONNECTION_REJECTED: "Connection cancelled.",
  TRANSACTION_REJECTED: "Cancelled.",
  SWITCH_NETWORK_REJECTED: "Network switch cancelled.",
  ADD_NETWORK_REJECTED: "Cancelled.",
  WALLET_LOCKED: "Unlock Adena and try again.",
  ALREADY_OPENED: "An Adena window is already open.",
  NOT_CONNECTED: "Connect Adena first.",
};

function fail(res: AdenaResponse<unknown>): never {
  throw new AdenaError(FRIENDLY[res.type] ?? (res.message || "Adena refused the request."), res.type, res.code);
}

export const isCancel = (e: unknown): boolean => e instanceof AdenaError && e.code === 4000;

export const hasAdena = (): boolean => window.adena !== undefined;
/** isPhone: Adena has no phone app yet, so a phone can listen but not sign. */
export const isPhone = (): boolean => /Android|iPhone|iPad/i.test(navigator.userAgent);

function adena(): AdenaWallet {
  if (!window.adena) throw new Error("Install the Adena wallet to sign actions.");
  return window.adena;
}

/** account returns the connected account without prompting, or undefined. */
export async function account(): Promise<AdenaAccount | undefined> {
  if (!window.adena) return undefined;
  const res = await window.adena.GetAccount().catch(() => undefined);
  return res?.status === "success" && res.data?.address ? res.data : undefined;
}

/** connect asks Adena for the user's consent and returns the account. */
export async function connect(): Promise<AdenaAccount> {
  const res = await adena().AddEstablish("GnoRadio");
  if (res.status !== "success" && res.type !== "ALREADY_CONNECTED") fail(res);
  const acc = await account();
  if (!acc) throw new Error("Adena did not return an account.");
  return acc;
}

/** switchNetwork selects the GnoRadio network, adding it to Adena first if needed. */
export async function switchNetwork(): Promise<void> {
  const a = adena();
  const res = await a.SwitchNetwork(CHAIN_ID);
  if (res.status === "success" || res.type === "REDUNDANT_CHANGE_REQUEST") return;
  if (res.type !== "UNADDED_NETWORK") fail(res);
  const added = await a.AddNetwork({ chainId: CHAIN_ID, chainName: CHAIN_NAME, rpcUrl: WALLET_RPC });
  if (added.status !== "success" && added.type !== "NETWORK_ALREADY_EXISTS") fail(added);
  const again = await a.SwitchNetwork(CHAIN_ID);
  if (again.status !== "success" && again.type !== "REDUNDANT_CHANGE_REQUEST") fail(again);
}

/** Call is one realm function call, whoever signs it (Adena, a session, gnokey). */
export interface Call {
  readonly pkg: RealmPath;
  readonly func: string;
  readonly args: readonly string[];
  /** ugnot sent with the call (a tip, a ticket); none when 0 or absent */
  readonly send?: number | undefined;
}

/** sign has Adena sign and broadcast messages; it returns the tx or throws its failure. */
export async function sign(messages: AdenaMessage[]): Promise<TxResult> {
  const res = await adena().DoContract({ messages, memo: "gnoradio" });
  if (res.status !== "success" || !res.data) fail(res);
  const base = res.data.deliverTx?.ResponseBase;
  if (base?.Error) throw new Error(base.Log ?? "The transaction failed on-chain.");
  return res.data;
}

/** call sends c as a MsgCall signed by the user's wallet (Adena estimates the gas) and returns the tx. */
export const call = (caller: string, c: Call): Promise<TxResult> =>
  sign([{ type: "/vm.m_call", value: { caller, send: c.send ? `${String(c.send)}ugnot` : "", pkg_path: c.pkg, func: c.func, args: [...c.args] } }]);

/** explorerURL links a tx on gnoscan (public chains only). */
export function explorerURL(hash: string): string | undefined {
  if (CHAIN_ID === "dev") return undefined;
  return `https://gnoscan.io/transactions/details?txhash=${encodeURIComponent(hash)}&chainId=${encodeURIComponent(CHAIN_ID)}`;
}

// Adena has no Off(): subscribe once per page and fan out locally.
type Listener = () => void;
const walletListeners = new Set<Listener>();
let walletSubscribed = false;

/** onWalletChange notifies on account or network changes; returns an unsubscribe. */
export function onWalletChange(cb: Listener): () => void {
  walletListeners.add(cb);
  if (!walletSubscribed && window.adena?.On) {
    walletSubscribed = true;
    const emit = () => { walletListeners.forEach((l) => { l(); }); };
    window.adena.On("changedAccount", emit);
    window.adena.On("changedNetwork", emit);
  }
  return () => { walletListeners.delete(cb); };
}
