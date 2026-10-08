// The GnoRadio verification bot. An artist publishes proofLine(id, wallet) on
// a page only they control, then asks the app to check: this reads that page
// and, if the line is there, signs a short-lived certificate (catalog.ClaimMessage)
// that the artist submits with catalog.Claim, paying the gas. The realm keeps the
// claim public for 72 hours before it counts and lets the admin cancel it or
// revoke the key (SetBot voids every pending claim it signed). The signing key holds no other power (netlify/bot.ts).
import { RealmError } from "../cards";
import { certificate, chain, readBody, refuse, reply, signCertificate } from "../bot";
import { WELL_KNOWN, hasProof, isAddress, isSharedHost, privateIP, proofLine, proofPage } from "../../src/lib/proof";
import { REALMS } from "../../src/lib/realms";
import { rateLimit } from "../limit";

const CATALOG = REALMS.catalog;
const MAX_PAGE = 1_000_000;
const CERT_LIFE = 3600; // seconds; the realm accepts at most 2 hours
const UNREADABLE = "We could not read that file. Check the address and that it is public.";

interface Artist { id: number; kind: string; owner: string; source: string; verified: boolean; tracks: number[] }

async function readJSON<T>(expr: string): Promise<T> {
  return JSON.parse(await chain(CATALOG, expr)) as T;
}

/** refused is a read the realm refused (a hidden or unknown id) as null; a timeout or an outage stays an error, so the artist is told to retry. */
const refused = (e: unknown): null => {
  if (e instanceof RealmError) return null;
  throw e;
};

/** publicHost resolves a name (DNS over HTTPS) and refuses one that points inside a network. */
// ponytail: fetch() resolves the name again, so a rebinding DNS could answer
// differently. What it reaches is bounded: https on 443 with a certificate valid
// for the attacker's name (an internal service cannot present one), a fixed
// path, one found/notFound bit back. Pin the vetted IP (node:https with a
// custom lookup) if the robot ever fetches plain http or other paths.
async function publicHost(host: string): Promise<boolean> {
  const ips: string[] = [];
  for (const type of ["A", "AAAA"]) {
    const r = await fetch(`https://cloudflare-dns.com/dns-query?name=${encodeURIComponent(host)}&type=${type}`, { headers: { accept: "application/dns-json" }, signal: AbortSignal.timeout(4000) });
    const answers = ((await r.json()) as { Answer?: { type: number; data: string }[] }).Answer ?? [];
    ips.push(...answers.filter((x) => x.type === 1 || x.type === 28).map((x) => x.data));
  }
  return ips.length > 0 && !ips.some(privateIP);
}

/** readCapped reads at most MAX_PAGE characters, then hangs up: an endless file never fills memory. */
async function readCapped(body: ReadableStream<Uint8Array>): Promise<string> {
  const reader = body.getReader();
  const decoder = new TextDecoder();
  let text = "";
  for (;;) {
    const { done, value } = await reader.read();
    if (done) return text + decoder.decode();
    text += decoder.decode(value, { stream: true });
    if (text.length >= MAX_PAGE) {
      await reader.cancel();
      return text.slice(0, MAX_PAGE);
    }
  }
}

/** fetchText reads a public page, following redirects only on its own host, with a size and time cap. */
async function fetchText(url: URL): Promise<string> {
  if (!(await publicHost(url.hostname))) throw new Error(UNREADABLE);
  let at = url;
  for (let hop = 0; hop < 4; hop++) {
    const r = await fetch(at, { redirect: "manual", signal: AbortSignal.timeout(8000), headers: { "user-agent": "GnoRadio-verify/1" } });
    const next = r.status >= 300 && r.status < 400 ? r.headers.get("location") : null;
    if (next === null) {
      if (!r.ok || !r.body) throw new Error(UNREADABLE);
      return await readCapped(r.body);
    }
    at = new URL(next, at);
    if (at.host !== url.host || at.protocol !== "https:") throw new Error(UNREADABLE); // same host and port
  }
  throw new Error(UNREADABLE);
}

/** Audius: the profile is the one owning the artist's first visible track (a stable id, unlike the handle). */
async function audiusProof(a: Artist): Promise<{ text: string; page: string }> {
  let t: { audio: string } | undefined;
  // A hidden track does not read (TrackJSON refuses it): the next one does.
  for (const id of a.tracks.slice(0, 20)) {
    t = (await readJSON<{ audio: string }>(`TrackJSON(${String(id)})`).catch(refused)) ?? undefined;
    if (t) break;
  }
  if (!t) throw new Error("this artist has no track to check");
  const id = t.audio.startsWith("audius:") ? t.audio.slice(7) : "";
  if (!id) throw new Error("this track is not an Audius track");
  const r = await fetch(`https://api.audius.co/v1/tracks/${encodeURIComponent(id)}?app_name=GnoRadio`, { signal: AbortSignal.timeout(8000) });
  const user = ((await r.json()) as { data?: { user?: { handle?: string; bio?: string } } }).data?.user;
  if (!user?.handle) throw new Error("Audius did not answer, try again in a minute");
  return { text: user.bio ?? "", page: `https://audius.co/${user.handle}` };
}

export default async (req: Request): Promise<Response> => {
  // An artist checks a few times while publishing the file; each check costs outbound fetches.
  const no = refuse(req, 5);
  if (no) return no;
  const body = (await readBody(req)) as { artist?: unknown; wallet?: unknown; page?: unknown } | null;
  if (!body || typeof body !== "object") return reply(400, { error: "invalid request" });
  const artistID = Number(body.artist);
  const wallet = typeof body.wallet === "string" ? body.wallet : "";
  if (!Number.isInteger(artistID) || artistID < 1 || !isAddress(wallet)) return reply(400, { error: "invalid artist or wallet" });

  try {
    // An unknown or hidden artist does not read: say so, not "try again".
    const a = await readJSON<Artist>(`ArtistJSON(${String(artistID)})`).catch(refused);
    if (!a) return reply(404, { error: "No such artist on GnoRadio (or it is hidden)." });
    if (a.verified) return reply(409, { error: "This profile is already verified." });
    if (a.owner && a.owner !== wallet) return reply(403, { error: "This profile belongs to another wallet." });
    // An imported profile's page is its source's (an archive, a label): no page proves the
    // artist, so only the moderator gives it an owner (catalog.AssignArtist; Claim refuses it).
    if (a.kind === "curated") return reply(400, { error: "Imported profiles are verified by the GnoRadio moderator: contact them to claim this one." });

    // Where to look: Audius through the account owning the artist's track; any
    // other artist through a file on their own domain, never a page others can comment on.
    let found: { text: string; page: string };
    if (a.kind === "audius") {
      found = await audiusProof(a);
    } else {
      const site = proofPage(typeof body.page === "string" ? body.page : "");
      if (!site) return reply(400, { error: "Give your website's address, e.g. https://yourname.com" });
      if (isSharedHost(site.hostname)) {
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
    const message = await chain(CATALOG, `ClaimMessage(${String(artistID)}, ${JSON.stringify(wallet)}, ${JSON.stringify(found.page)}, ${String(expires)})`);
    // Signed only when the realm's text is exactly this artist, wallet, page and expiry on this chain and deployment.
    if (message !== certificate("claim", artistID, wallet, found.page, expires)) return reply(503, { error: "The robot is not configured on this site." });
    const sig = await signCertificate(message);
    if (!sig) return reply(200, { found: true, page: found.page, note: "Proof found, but the robot key is not set on this server." });
    return reply(200, { found: true, page: found.page, expires, sig });
  } catch (e) {
    // Only our own messages go back: nothing about the fetched host leaks.
    return reply(502, { error: e instanceof Error && e.message === UNREADABLE ? UNREADABLE : "The check failed, try again in a minute." });
  }
};

export const config = { path: "/api/verify", rateLimit: rateLimit(10) };
