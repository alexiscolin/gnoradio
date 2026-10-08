// Chain data is untrusted: a URL from a realm (or a compromised RPC) only
// reaches an href or src after its scheme is checked here.

const MEDIA = /^(https:\/\/|ipfs:\/\/|ar:\/\/|audius:)/;

/** safeHttps returns u when it is an absolute https URL, else "". */
export function safeHttps(u: string): string {
  if (!u.startsWith("https://")) return "";
  try {
    return new URL(u).protocol === "https:" ? u : "";
  } catch {
    return "";
  }
}

/** safeMedia accepts the media references the realm allows (https, ipfs, ar, audius), else "". */
export function safeMedia(u: string): string {
  if (!MEDIA.test(u)) return "";
  return u.startsWith("https://") ? safeHttps(u) : u;
}

const IPFS_GATEWAYS = ["https://ipfs.io/ipfs/", "https://dweb.link/ipfs/", "https://cloudflare-ipfs.com/ipfs/"] as const;

/** mediaURLs resolves a media reference to playable URLs, best first (several IPFS gateways). */
export function mediaURLs(ref: string): string[] {
  const u = safeMedia(ref);
  if (u.startsWith("ipfs://")) return IPFS_GATEWAYS.map((g) => g + u.slice(7));
  if (u.startsWith("ar://")) return [`https://arweave.net/${u.slice(5)}`];
  if (u.startsWith("audius:")) return [`https://api.audius.co/v1/tracks/${encodeURIComponent(u.slice(7))}/stream?app_name=GnoRadio`];
  return u ? [u] : [];
}

// The hosts a server may fetch a cover from (the link-preview image): the
// gateways mediaURLs uses, the realm's default https hosts, and Audius.
const COVER_HOSTS = ["ipfs.io", "dweb.link", "cloudflare-ipfs.com", "arweave.net", "archive.org", "wikimedia.org", "audius.co"];

/** coverHost accepts an https URL on an allowed media host (or a subdomain): no port, no credentials. */
export function coverHost(u: string): boolean {
  if (!safeHttps(u)) return false;
  const { hostname: h, port, username, password } = new URL(u);
  return !port && !username && !password && COVER_HOSTS.some((s) => h === s || h.endsWith(`.${s}`));
}
