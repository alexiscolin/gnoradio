// The GnoRadio robot's key, shared by its functions. It only calls functions
// that give it no power over funds or settings (radio.Sync, radio.HideNote),
// and signs artist verification certificates (catalog.Claim) without paying. Env: BOT_MNEMONIC (never committed), BOT_RPC
// (defaults to onyx).
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

// Ed25519 seed of the verification certificates (32 bytes, hex), the key named
// with catalog.SetBot. PKCS#8 wraps the raw seed for Web Crypto.
const PKCS8_ED25519 = "302e020100300506032b657004220420";
const fromHex = (h: string) => Uint8Array.from(h.match(/../g) ?? [], (b) => parseInt(b, 16));
const toHex = (b: ArrayBuffer) => [...new Uint8Array(b)].map((x) => x.toString(16).padStart(2, "0")).join("");

/** signCertificate signs a catalog.ClaimMessage; "" when no key is set on this server. */
export async function signCertificate(message: string): Promise<string> {
  const seed = process.env["BOT_SIGNING_KEY"];
  if (!seed || !/^[0-9a-f]{64}$/i.test(seed)) return "";
  const key = await crypto.subtle.importKey("pkcs8", fromHex(PKCS8_ED25519 + seed), { name: "Ed25519" }, false, ["sign"]);
  return toHex(await crypto.subtle.sign("Ed25519", key, new TextEncoder().encode(message)));
}

/** sameSite accepts calls from this site only (Netlify sets URL); in dev there is none. */
export function sameSite(req: Request): boolean {
  const site = process.env["URL"];
  if (!site) return true;
  const origin = req.headers.get("origin");
  return origin !== null && URL.canParse(origin) && new URL(origin).host === new URL(site).host;
}
