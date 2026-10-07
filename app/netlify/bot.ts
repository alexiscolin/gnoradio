// The GnoRadio robot's key, shared by its functions. It only calls functions
// that give it no power over funds or settings (radio.Sync, optional),
// and signs certificates without paying: artist verification (catalog.Claim)
// and dedications (radio.QueueWithNote). Env: BOT_MNEMONIC (never committed),
// BOT_SIGNING_KEY, BOT_RPC (defaults to onyx).
import { GnoJSONRPCProvider, GnoWallet } from "@gnolang/gno-js-client";
import { TransactionEndpoint } from "@gnolang/tm2-js-client";

export const provider = (): Promise<GnoJSONRPCProvider> =>
  GnoJSONRPCProvider.create(process.env["BOT_RPC"] ?? "https://rpc.onyx.testnets.gno.land:443");

// The whole gas limit is charged at the chain price (auth/gasprice: 1 ugnot
// per 1000 gas on onyx and mainnet), so callers keep limits tight.

/** botCall signs one call with the robot key; false when no key is set on this server. */
export async function botCall(p: GnoJSONRPCProvider, pkg: string, fn: string, args: string[], gas: bigint): Promise<boolean> {
  const mnemonic = process.env["BOT_MNEMONIC"];
  if (!mnemonic) return false;
  const bot = await GnoWallet.fromMnemonic(mnemonic);
  bot.connect(p);
  await bot.callMethod(pkg, fn, args, TransactionEndpoint.BROADCAST_TX_COMMIT, undefined, undefined, { gas_wanted: gas, gas_fee: `${String(gas / 1000n)}ugnot` });
  return true;
}

// Ed25519 seed of the robot's certificates (32 bytes, hex). It signs
// catalog.ClaimMessage and radio.NoteMessage, so its public key must be set
// with both catalog.SetBot and radio.SetModBot. PKCS#8 wraps the raw seed for Web Crypto.
const PKCS8_ED25519 = "302e020100300506032b657004220420";
const fromHex = (h: string) => Uint8Array.from(h.match(/../g) ?? [], (b) => parseInt(b, 16));
const toHex = (b: ArrayBuffer) => [...new Uint8Array(b)].map((x) => x.toString(16).padStart(2, "0")).join("");

/** signCertificate signs a catalog.ClaimMessage or radio.NoteMessage; "" when no key is set on this server. */
export async function signCertificate(message: string): Promise<string> {
  const seed = process.env["BOT_SIGNING_KEY"];
  if (!seed || !/^[0-9a-f]{64}$/i.test(seed)) return "";
  const key = await crypto.subtle.importKey("pkcs8", fromHex(PKCS8_ED25519 + seed), { name: "Ed25519" }, false, ["sign"]);
  return toHex(await crypto.subtle.sign("Ed25519", key, new TextEncoder().encode(message)));
}

/** sameSite accepts calls from this site only (Netlify sets URL); only `netlify dev` may run without one. */
function sameSite(req: Request): boolean {
  const site = process.env["URL"];
  if (!site) return process.env["NETLIFY_DEV"] === "true";
  const origin = req.headers.get("origin");
  return origin !== null && URL.canParse(origin) && new URL(origin).host === new URL(site).host;
}

export const reply = (status: number, body: object): Response => Response.json(body, { status });

// ponytail: in memory, per function instance. Netlify runs several instances
// under load, so the real ceiling is perMinute × instances, and a botnet with
// many IPs is not stopped. Netlify's config.rateLimit or a shared store
// (Netlify Blobs) when that matters.
const hits = new Map<string, number[]>();

function tooMany(ip: string, perMinute: number): boolean {
  const now = Date.now();
  if (hits.size > 10_000) hits.clear(); // bounded memory, at the cost of a reset
  const recent = (hits.get(ip) ?? []).filter((t) => now - t < 60_000);
  recent.push(now);
  hits.set(ip, recent);
  return recent.length > perMinute;
}

/**
 * refuse turns away what the app never sends before any outbound call: another
 * method or site (Origin is a CSRF check only: curl sets it at will), a large
 * body, more than perMinute calls from one client IP. null lets the call through.
 */
const MAX_BODY = 4096;

/** readBody parses a JSON request body read up to MAX_BODY bytes (a chunked body has no content-length to check); null when larger or not JSON. */
export async function readBody(req: Request): Promise<unknown> {
  const reader = req.body?.getReader();
  if (!reader) return null;
  const decoder = new TextDecoder();
  let text = "";
  let size = 0;
  for (;;) {
    const { done, value } = await reader.read();
    if (done) break;
    size += value.length;
    if (size > MAX_BODY) { await reader.cancel(); return null; }
    text += decoder.decode(value, { stream: true });
  }
  try { return JSON.parse(text + decoder.decode()) as unknown; } catch { return null; }
}

export function refuse(req: Request, perMinute: number): Response | null {
  if (req.method !== "POST") return reply(405, { error: "POST only" });
  if (!sameSite(req)) return reply(403, { error: "forbidden" });
  if (Number(req.headers.get("content-length") ?? 0) > MAX_BODY) return reply(413, { error: "invalid request" });
  // Netlify sets this header itself: a client cannot choose it.
  if (tooMany(req.headers.get("x-nf-client-connection-ip") ?? "", perMinute)) return reply(429, { error: "Too many tries. Wait a minute and try again." });
  return null;
}
