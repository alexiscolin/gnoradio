// Minimal gno.land client: reads realm JSON exports through vm/qeval and
// sends transactions through the Adena wallet (or a session, or gnokey). Listening never touches it.

import { check, type Guard } from "./guard";

export const RPC = import.meta.env.VITE_RPC ?? "/rpc";
export const CHAIN_ID = import.meta.env.VITE_CHAIN_ID ?? (import.meta.env.PROD ? "onyx-1" : "dev");

/** networkLabel names a non-mainnet chain for the network badge; "" on mainnet. */
export function networkLabel(chainId: string): string {
  if (chainId === "gnoland-1") return "";
  if (chainId === "dev") return "Local devnet";
  if (/^(onyx|test)/.test(chainId)) return `Testnet · ${chainId}`;
  return chainId;
}

export const REALMS = {
  catalog: "gno.land/r/gnoradio/catalog/v0",
  radio: "gno.land/r/gnoradio/radio/v0",
  tickets: "gno.land/r/gnoradio/tickets/v0",
} as const;

export type RealmPath = (typeof REALMS)[keyof typeof REALMS] | SysPath;
/** gno.land system realms the app reads: names (r/sys/users) and the name registrar. */
export type SysPath = "gno.land/r/sys/users" | "gno.land/r/sys/namereg/v0" | "gno.land/r/sys/namereg/v1" | typeof SAFE;

/** SAFE screens dedications (p/gnoradio/safe); the app asks it before signing. */
export const SAFE = "gno.land/p/gnoradio/safe/v0";
export const MAX_NOTE = 40;

/** noteProblem is why a dedication would be refused ("" when fine): a free read. */
export async function noteProblem(note: string): Promise<string> {
  return note === "" ? "" : unquote(await qeval(SAFE, `Note(${JSON.stringify(note)}, ${String(MAX_NOTE)})`));
}

const toBase64 = (s: string) => btoa(String.fromCharCode(...new TextEncoder().encode(s)));
const fromBase64 = (s: string) => new TextDecoder().decode(Uint8Array.from(atob(s), (c) => c.charCodeAt(0)));

interface AbciResponse {
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

// At most MAX_INFLIGHT queries at once, so a big catalog never floods the public RPC.
const MAX_INFLIGHT = 6;
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
export const GNOWEB = import.meta.env.VITE_GNOWEB ?? (import.meta.env.DEV ? `${window.location.protocol}//${window.location.hostname}:8911` : "https://gno.land");

/** qeval runs `pkg.expr` read-only and returns the raw typed result, e.g. `("…" string)`. */
export function qeval(pkg: RealmPath, expr: string): Promise<string> {
  return slot(async () => {
    for (let attempt = 0; ; attempt++) {
      try {
        return await qevalOnce(pkg, expr);
      } catch (e) {
        // Retry rate limits, timeouts and network errors with backoff; realm errors are final.
        if (e instanceof RealmError || attempt >= 3) throw e;
        await sleep(400 * 2 ** attempt);
      }
    }
  });
}

async function qevalOnce(pkg: RealmPath, expr: string): Promise<string> {
  const res = await fetch(RPC, {
    method: "POST",
    headers: { "content-type": "application/json" },
    body: JSON.stringify({ jsonrpc: "2.0", id: 1, method: "abci_query", params: { path: "vm/qeval", data: toBase64(`${pkg}.${expr}`) } }),
    // A hung node must not hold one of the few query slots forever.
    signal: AbortSignal.timeout(TIMEOUT_MS),
  });
  if (!res.ok) throw new Error(`RPC returned ${res.status}`);
  const base = ((await res.json()) as AbciResponse).result?.response?.ResponseBase;
  if (!base) throw new Error("RPC unreachable");
  if (base.Error) throw new RealmError(base.Log || "query failed");
  return fromBase64(base.Data ?? "");
}

/** unquote unwraps a qeval string result, ("…" string) → …; "" when it isn't one. */
import { unquote } from "./proof";
export { unquote };

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

const ADDRESS = /^g1[02-9ac-hj-np-z]{38}$/;

/** gnoString quotes a value for a qeval expression; addresses are validated first. */
export function gnoAddress(a: string): string {
  if (!ADDRESS.test(a)) throw new Error("Invalid gno.land address");
  return JSON.stringify(a);
}

// ---- Adena (optional, only for writes) ----
// API per docs.adena.app and onbloc/adena-wallet src/inject.ts.

/** RPC the wallet itself must reach (the dev proxy /rpc is only for the page). */
export const WALLET_RPC =
  import.meta.env.VITE_WALLET_RPC ?? (CHAIN_ID === "dev" ? `http://${window.location.hostname}:27157` : "https://rpc.onyx.testnets.gno.land:443");
export const CHAIN_NAME = CHAIN_ID === "dev" ? "GnoRadio devnet" : `gno.land ${CHAIN_ID}`;

export interface AdenaResponse<T> {
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

export function adena(): AdenaWallet {
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
