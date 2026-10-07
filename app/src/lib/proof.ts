// Artist verification proof, shared by the app (what to publish) and the bot
// (netlify/functions/verify.mts, what to look for). Pure: no Vite env here.

/** proofLine is what an artist publishes on a page they control to claim artistID for wallet. */
export const proofLine = (artistID: number, wallet: string): string => `gnoradio:${String(artistID)}:${wallet}`;

const G1 = "g1[02-9ac-hj-np-z]{38}";
const ADDRESS = new RegExp(`^${G1}$`);
const LINE = new RegExp(`gnoradio:(\\d+):(${G1})`, "g");

/** isAddress tells whether s is a gno.land g1… address (bech32 charset, 40 characters). */
export const isAddress = (s: string): boolean => ADDRESS.test(s);

/**
 * hasProof reports whether text proves artistID belongs to wallet: it must
 * name exactly one wallet for that artist, so a page listing several (a
 * comment thread, a copied bio) proves nothing.
 */
export function hasProof(text: string, artistID: number, wallet: string): boolean {
  const wallets = new Set<string>();
  for (const m of text.matchAll(LINE)) if (Number(m[1]) === artistID && m[2]) wallets.add(m[2]);
  return wallets.size === 1 && wallets.has(wallet);
}

/** proofPage accepts a public https page the bot may read: no port, no IP, no local host. */
export function proofPage(raw: string): URL | null {
  let u: URL;
  try {
    u = new URL(raw.trim());
  } catch {
    return null;
  }
  const h = u.hostname;
  if (u.protocol !== "https:" || u.port || u.username || !h.includes(".") || /^[\d.]+$/.test(h) || h.includes(":") || /(^|\.)(localhost|local|internal|ts\.net)$/.test(h)) return null;
  return u;
}

/**
 * Pages whose content the artist does not control alone: a proof there could
 * be planted by an uploader or a commenter, so they never count.
 */
const SHARED_HOSTS = ["archive.org", "wikimedia.org", "github.com", "gno.land", "bandcamp.com", "soundcloud.com"];
export const isSharedHost = (host: string): boolean => SHARED_HOSTS.some((s) => host === s || host.endsWith(`.${s}`));

/** WELL_KNOWN is where a non-Audius artist proves a domain: a file only its owner can write. */
export const WELL_KNOWN = "/.well-known/gnoradio.txt";

/**
 * privateIP reports addresses the robot must never fetch (loopback, private,
 * link-local, carrier-grade NAT, benchmark, unique-local IPv6, and the IPv6
 * forms that wrap an IPv4 address: mapped, NAT64, 6to4): a public name
 * pointing there would turn the robot into a probe of internal services.
 */
export function privateIP(ip: string): boolean {
  if (ip.includes(":")) return /^(::1?$|fe[89ab]|f[cd]|::ffff:|64:ff9b:|2002:)/i.test(ip);
  const [a = 0, b = 0, c = 0] = ip.split(".").map(Number);
  return a === 0 || a === 10 || a === 127 || (a === 169 && b === 254) || (a === 172 && b >= 16 && b <= 31) || (a === 192 && b === 168) || (a === 192 && b === 0 && c === 0) ||
    (a === 198 && (b === 18 || b === 19)) || (a === 100 && b >= 64 && b <= 127) || a >= 224;
}

/** unquote reads a vm/qeval string result: ("…" string) → its value, else "". */
export function unquote(raw: string): string {
  const m = /^\((".*") string\)$/s.exec(raw.trim());
  const v: unknown = m?.[1] === undefined ? "" : JSON.parse(m[1]);
  return typeof v === "string" ? v : "";
}
