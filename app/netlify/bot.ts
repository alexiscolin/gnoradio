// The GnoRadio robot's key, shared by its functions. It holds no account and
// sends no transaction: it reads the chain and signs certificates the user
// submits from their own wallet, artist verification (catalog.Claim) and
// dedications (radio.QueueWithNote), so GnoRadio pays no gas. Env:
// BOT_SIGNING_KEY, BOT_RPC (defaults to the site's network, lib/network.ts).
import { serverChainId, serverRPC, set } from "../src/lib/network";
import { REALMS, runtimeEnv } from "../src/lib/realms";
import { qeval, qevalRaw } from "./cards";
import { tooMany } from "./limit";

/** chain reads a realm expression's string result through the robot's RPC (BOT_RPC, else the site's network). */
const rpc = (): string => set(process.env["BOT_RPC"]) ?? serverRPC();
export const chain = (realm: string, expr: string): Promise<string> => qeval(rpc(), realm, expr);
/** chainRaw is chain without the string unquoting (an int64 answer). */
export const chainRaw = (realm: string, expr: string): Promise<string> => qevalRaw(rpc(), realm, expr);

/**
 * certificate is the exact text the realm signs over (catalog.ClaimMessage, radio.NoteMessage), built here
 * from this site's chain and namespace: the robot compares the realm's answer with it and signs nothing else.
 */
export const certificate = (kind: "claim" | "note", ...fields: readonly (string | number)[]): string =>
  [`gnoradio-${kind}`, serverChainId(), REALMS.data, ...fields.map(String)].join("|");

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
  // The site's main URL, and this deploy's own (deploy previews, branch deploys).
  const hosts = [site, process.env["DEPLOY_PRIME_URL"], process.env["DEPLOY_URL"]].filter((u): u is string => !!u && URL.canParse(u)).map((u) => new URL(u).host);
  return origin !== null && URL.canParse(origin) && hosts.includes(new URL(origin).host);
}

export const reply = (status: number, body: object): Response => Response.json(body, { status });

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

/**
 * refuse turns away what the app never sends before any outbound call: another
 * method or site (Origin is a CSRF check only: curl sets it at will), a large
 * body, more than perMinute calls from one client IP. null lets the call through.
 */
export function refuse(req: Request, perMinute: number): Response | null {
  if (req.method !== "POST") return reply(405, { error: "POST only" });
  if (!sameSite(req)) return reply(403, { error: "forbidden" });
  if (Number(req.headers.get("content-length") ?? 0) > MAX_BODY) return reply(413, { error: "invalid request" });
  if (tooMany(req, perMinute)) return reply(429, { error: "Too many tries. Wait a minute and try again." });
  // A deployed site without its namespace would read (and certify for) gno.land/r/gnoradio, which anyone may register.
  if (process.env["NETLIFY_DEV"] !== "true" && process.env["URL"] && !runtimeEnv("VITE_GNORADIO_NS")) return reply(503, { error: "The robot is not configured on this site." });
  return null;
}
