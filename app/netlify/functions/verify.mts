// The GnoRadio verification bot. An artist publishes proofLine(id, wallet) on
// a page only they control, then asks the app to check: this reads that page
// and, if the line is there, signs a short-lived certificate (catalog.ClaimMessage)
// that the artist submits with catalog.Claim, paying the gas. The realm keeps the
// claim public for 72 hours before it counts, caps claims per day and lets the
// admin cancel it. The signing key holds no other power (netlify/bot.ts).
import type { GnoJSONRPCProvider } from "@gnolang/gno-js-client";
import { provider, sameSite, signCertificate } from "../bot";
import { WELL_KNOWN, hasProof, isSharedHost, privateIP, proofLine, proofPage, unquote } from "../../src/lib/proof";

const CATALOG = "gno.land/r/gnoradio/catalog/v0";
const ADDRESS = /^g1[02-9ac-hj-np-z]{38}$/;
const MAX_PAGE = 1_000_000;
const CERT_LIFE = 3600; // seconds; the realm accepts at most 2 hours
const UNREADABLE = "We could not read that file. Check the address and that it is public.";

interface Artist { id: number; kind: string; owner: string; source: string; verified: boolean; tracks: number[] }

const reply = (status: number, body: object) => Response.json(body, { status });

async function readJSON<T>(p: GnoJSONRPCProvider, expr: string): Promise<T> {
  return JSON.parse(unquote(await p.evaluateExpression(CATALOG, expr))) as T;
}

/** publicHost resolves a name (DNS over HTTPS) and refuses one that points inside a network. */
async function publicHost(host: string): Promise<boolean> {
  const ips: string[] = [];
  for (const type of ["A", "AAAA"]) {
    const r = await fetch(`https://cloudflare-dns.com/dns-query?name=${encodeURIComponent(host)}&type=${type}`, { headers: { accept: "application/dns-json" }, signal: AbortSignal.timeout(4000) });
    const answers = ((await r.json()) as { Answer?: { type: number; data: string }[] }).Answer ?? [];
    ips.push(...answers.filter((x) => x.type === 1 || x.type === 28).map((x) => x.data));
  }
  return ips.length > 0 && !ips.some(privateIP);
}

/** fetchText reads a public page, following redirects only on its own host, with a size and time cap. */
async function fetchText(url: URL): Promise<string> {
  if (!(await publicHost(url.hostname))) throw new Error(UNREADABLE);
  let at = url;
  for (let hop = 0; hop < 4; hop++) {
    const r = await fetch(at, { redirect: "manual", signal: AbortSignal.timeout(8000), headers: { "user-agent": "GnoRadio-verify/1" } });
    const next = r.status >= 300 && r.status < 400 ? r.headers.get("location") : null;
    if (next === null) {
      if (!r.ok) throw new Error(UNREADABLE);
      return (await r.text()).slice(0, MAX_PAGE);
    }
    at = new URL(next, at);
    if (at.hostname !== url.hostname || at.protocol !== "https:") throw new Error(UNREADABLE);
  }
  throw new Error(UNREADABLE);
}

/** Audius: the profile is the one owning the artist's first track (a stable id, unlike the handle). */
async function audiusProof(p: GnoJSONRPCProvider, a: Artist): Promise<{ text: string; page: string }> {
  const first = a.tracks[0];
  if (first === undefined) throw new Error("this artist has no track to check");
  const t = await readJSON<{ audio: string }>(p, `TrackJSON(${String(first)})`);
  const id = t.audio.startsWith("audius:") ? t.audio.slice(7) : "";
  if (!id) throw new Error("this track is not an Audius track");
  const r = await fetch(`https://api.audius.co/v1/tracks/${encodeURIComponent(id)}?app_name=GnoRadio`, { signal: AbortSignal.timeout(8000) });
  const user = ((await r.json()) as { data?: { user?: { handle?: string; bio?: string } } }).data?.user;
  if (!user?.handle) throw new Error("Audius did not answer, try again in a minute");
  return { text: user.bio ?? "", page: `https://audius.co/${user.handle}` };
}

export default async (req: Request): Promise<Response> => {
  if (req.method !== "POST") return reply(405, { error: "POST only" });
  if (!sameSite(req)) return reply(403, { error: "forbidden" });
  let body: { artist?: unknown; wallet?: unknown; page?: unknown };
  try {
    body = (await req.json()) as typeof body;
  } catch {
    return reply(400, { error: "invalid request" });
  }
  const artistID = Number(body.artist);
  const wallet = typeof body.wallet === "string" ? body.wallet : "";
  if (!Number.isInteger(artistID) || artistID < 1 || !ADDRESS.test(wallet)) return reply(400, { error: "invalid artist or wallet" });

  try {
    const p = await provider();
    const a = await readJSON<Artist>(p, `ArtistJSON(${String(artistID)})`);
    if (a.verified) return reply(409, { error: "This profile is already verified." });
    if (a.owner && a.owner !== wallet) return reply(403, { error: "This profile belongs to another wallet." });

    // Where to look: Audius through the account owning the artist's track; any
    // other artist through a file on their own domain (an imported profile: the
    // domain of its recorded page), never a page others can comment on.
    let found: { text: string; page: string };
    if (a.kind === "audius") {
      found = await audiusProof(p, a);
    } else {
      const site = proofPage(a.kind === "curated" ? a.source : typeof body.page === "string" ? body.page : "");
      if (!site) return reply(400, { error: "Give your website's address, e.g. https://yourname.com" });
      if (isSharedHost(site.hostname) || site.hostname.endsWith(".bandcamp.com") || site.hostname.endsWith("soundcloud.com")) {
        return reply(400, { error: `${site.hostname} pages can be written by others, so they cannot prove who you are. Use your own website.` });
      }
      const file = new URL(WELL_KNOWN, site.origin);
      found = { text: await fetchText(file), page: file.href };
    }
    if (!hasProof(found.text, artistID, wallet)) {
      return reply(422, { error: "notFound", page: found.page, line: proofLine(artistID, wallet) });
    }

    // A certificate the artist submits with catalog.Claim from their own wallet:
    // the robot signs, the artist pays the gas.
    const expires = Math.floor(Date.now() / 1000) + CERT_LIFE;
    const message = unquote(await p.evaluateExpression(CATALOG, `ClaimMessage(${String(artistID)}, ${JSON.stringify(wallet)}, ${JSON.stringify(found.page)}, ${String(expires)})`));
    const sig = await signCertificate(message);
    if (!sig) return reply(200, { found: true, page: found.page, note: "Proof found, but the robot key is not set on this server." });
    return reply(200, { found: true, page: found.page, expires, sig });
  } catch (e) {
    // Only our own messages go back: nothing about the fetched host leaks.
    return reply(502, { error: e instanceof Error && e.message === UNREADABLE ? UNREADABLE : "The check failed, try again in a minute." });
  }
};

export const config = { path: "/api/verify" };
