// Client-side copies of the catalog realm's input rules (validate.gno,
// tracks.gno, social.gno, moderation.gno), so forms explain a problem before
// Adena opens instead of after a failed transaction. The realm stays the judge.

export const LICENSES = [
  ["CC0-1.0", "CC0 · public domain"],
  ["CC-BY-4.0", "CC BY 4.0"],
  ["CC-BY-SA-4.0", "CC BY-SA 4.0"],
  ["CC-BY-ND-4.0", "CC BY-ND 4.0"],
  ["CC-BY-NC-4.0", "CC BY-NC 4.0"],
  ["CC-BY-NC-SA-4.0", "CC BY-NC-SA 4.0"],
  ["CC-BY-NC-ND-4.0", "CC BY-NC-ND 4.0"],
  ["ALL-RIGHTS-RESERVED", "All rights reserved"],
] as const;

export const MAX_SPLITS = 4;
export const MAX_SPLIT_PCT = 90;
export const MAX_LIST_TRACKS = 200;
export const MIN_DURATION = 10;
export const MAX_DURATION = 1200;

const TEXT_EXTRA = new Set([" ", ".", ",", "'", "-", "!", "?", ":", "/", "&"]);
const NAME_EXTRA = new Set([" ", ".", "'", "-", "&"]);
const URL_CHARS = /^[A-Za-z0-9\-._~:/?#=&%+@]*$/;
const ADDRESS = /^g1[02-9ac-hj-np-z]{38}$/;

/** validText: letters, digits, spaces and . , ' - ! ? : / & only; length in characters. */
export function validText(s: string, min: number, max: number): boolean {
  let n = 0;
  for (const ch of s) {
    n++;
    if (/^[\p{L}\p{Nd}]$/u.test(ch) || TEXT_EXTRA.has(ch)) continue;
    return false;
  }
  return n >= min && n <= max;
}

export const textRule = (field: string, min: number, max: number) =>
  `${field} must be ${String(min)}-${String(max)} characters: letters, digits, spaces and . , ' - ! ? : / & only`;

/** validName: artist names in Latin letters, 2 to 40 characters, no double or edge spaces. */
export function validName(s: string): boolean {
  if (s.trim() !== s || s.includes("  ")) return false;
  let n = 0;
  for (const ch of s) {
    n++;
    const c = ch.codePointAt(0) ?? 0;
    const latin = (c >= 0x61 && c <= 0x7a) || (c >= 0x41 && c <= 0x5a) || (c >= 0x30 && c <= 0x39);
    const latin1 = c >= 0xc0 && c <= 0xff && c !== 0xd7 && c !== 0xf7;
    if (latin || latin1 || NAME_EXTRA.has(ch)) continue;
    return false;
  }
  return n >= 2 && n <= 40;
}

/** parseClock reads "m:ss" (or plain seconds) like the realm; undefined when malformed. */
export function parseClock(s: string): number | undefined {
  const v = s.trim();
  const [m, sec, extra] = v.split(":");
  if (sec === undefined) return /^\d{1,5}$/.test(v) ? Number(v) : undefined;
  if (extra !== undefined || m === undefined || !/^\d{1,3}$/.test(m) || !/^\d{2}$/.test(sec)) return undefined;
  const sv = Number(sec);
  return sv > 59 ? undefined : Number(m) * 60 + sv;
}

export const isSHA256 = (s: string): boolean => /^[0-9a-f]{64}$/.test(s);
export const isAddress = (s: string): boolean => ADDRESS.test(s);
export const validHTTPS = (s: string): boolean => s.startsWith("https://") && s.length > 10 && s.length <= 300 && URL_CHARS.test(s);
export const hostOf = (url: string): string => (url.replace(/^https:\/\//, "").split("/")[0] ?? "").toLowerCase();

/**
 * mediaProblem checks an audio or cover reference (mustMedia). Hosts of https
 * links are allowlisted on-chain; pass hostAllowed when it is known.
 */
export function mediaProblem(field: string, uri: string, sha: string, audio: boolean, hostAllowed?: boolean): string {
  if (sha !== "" && !isSHA256(sha)) return `${field} sha256 must be 64 hex characters`;
  if (uri.startsWith("ipfs://")) return /^[A-Za-z0-9]{46,100}$/.test(uri.slice(7)) ? "" : `${field} ipfs:// needs a valid CID`;
  if (uri.startsWith("ar://")) {
    const id = uri.slice(5);
    return id.length === 43 && URL_CHARS.test(id) ? "" : `${field} ar:// needs a 43-character transaction id`;
  }
  if (uri.startsWith("audius:")) return audio && /^[A-Za-z0-9]{1,24}$/.test(uri.slice(7)) ? "" : `${field} audius:<trackId> is only valid for audio`;
  if (uri.startsWith("https://")) {
    if (!validHTTPS(uri) || hostAllowed === false) return `${field} host is not allowed (ask the admin to add it)`;
    return sha === "" ? `${field} over https needs the file's sha256` : "";
  }
  return `${field} must be ipfs://, ar://, audius: or an allowed https:// link`;
}

export interface SplitRow {
  readonly to: string;
  readonly pct: string;
}

/** splitsProblem mirrors parseSplits: up to 4 collaborators, 1-90% each, 90% in total. */
export function splitsProblem(rows: readonly SplitRow[], self: string): string {
  const used = rows.filter((r) => r.to.trim() !== "" || r.pct.trim() !== "");
  if (used.length > MAX_SPLITS) return "at most 4 collaborators";
  const seen = new Set<string>();
  let sum = 0;
  for (const r of used) {
    const to = r.to.trim();
    const pct = Number(r.pct.trim().replace(/%$/, ""));
    if (!isAddress(to)) return "each collaborator needs a g1… address";
    if (to === self) return "you already receive the artist share";
    if (seen.has(to)) return "each collaborator once";
    if (!Number.isInteger(pct) || pct < 1 || pct > MAX_SPLIT_PCT) return "each share is a whole percent between 1 and 90";
    seen.add(to);
    sum += pct;
  }
  return sum > MAX_SPLIT_PCT ? "collaborators may receive at most 90%" : "";
}

export const formatSplits = (rows: readonly SplitRow[]): string =>
  rows.filter((r) => r.to.trim() !== "").map((r) => `${r.to.trim()}:${r.pct.trim().replace(/%$/, "")}`).join(",");

export interface TrackDraft {
  readonly title: string;
  readonly genre: number;
  readonly duration: string;
  readonly license: string;
  readonly cmo: string;
  readonly credits: string;
  readonly audio: string;
  readonly audioSha: string;
  readonly cover: string;
  readonly coverSha: string;
  readonly splits: readonly SplitRow[];
  readonly rights: boolean;
}

/** trackProblems lists every reason PublishTrack would refuse the draft. */
export function trackProblems(d: TrackDraft, self: string, hosts: { readonly audio?: boolean | undefined; readonly cover?: boolean | undefined } = {}): string[] {
  const out: string[] = [];
  if (!validText(d.title.trim(), 1, 64)) out.push(textRule("Title", 1, 64));
  if (!Number.isInteger(d.genre) || d.genre < 1 || d.genre > 12) out.push("Pick a genre");
  const secs = parseClock(d.duration);
  if (secs === undefined || secs < MIN_DURATION || secs > MAX_DURATION) out.push("Duration as m:ss, between 0:10 and 20:00");
  if (!LICENSES.some(([id]) => id === d.license)) out.push("Pick a license");
  if (d.cmo === "sacem-nc" && !d.license.includes("-NC")) out.push("SACEM members may only publish works under a CC NC license");
  if (!validText(d.credits.trim(), 0, 160)) out.push(textRule("Credits", 0, 160));
  const audio = mediaProblem("Audio", d.audio.trim(), d.audioSha.trim().toLowerCase(), true, hosts.audio);
  if (audio) out.push(audio);
  if (d.cover.trim() !== "") {
    const cover = mediaProblem("Cover", d.cover.trim(), d.coverSha.trim().toLowerCase(), false, hosts.cover);
    if (cover) out.push(cover);
  }
  const splits = splitsProblem(d.splits, self);
  if (splits) out.push(`Collaborators: ${splits}`);
  if (!d.rights) out.push("Declare that you own the rights");
  return out;
}

export function artistProblems(name: string, bio: string): string[] {
  const out: string[] = [];
  if (!validName(name.trim())) out.push("Name: 2-40 Latin letters, digits, spaces and . ' - &, no double spaces");
  if (!validText(bio.trim(), 0, 280)) out.push(textRule("Bio", 0, 280));
  return out;
}

export function playlistProblems(title: string, ids: readonly number[]): string[] {
  const out: string[] = [];
  if (!validText(title.trim(), 1, 64)) out.push(textRule("Title", 1, 64));
  if (ids.length === 0) out.push("Add at least one track");
  if (ids.length > MAX_LIST_TRACKS) out.push("At most 200 tracks");
  if (new Set(ids).size !== ids.length) out.push("Each track once");
  return out;
}

export function reportProblems(reason: string): string[] {
  return validText(reason.trim(), 4, 200) ? [] : [`${textRule("Reason", 4, 200)}. Links with _ = % ~ are refused, use a plain one`];
}

/** sha256Hex hashes bytes with WebCrypto. */
export async function sha256Hex(data: ArrayBuffer): Promise<string> {
  const digest = await crypto.subtle.digest("SHA-256", data);
  return [...new Uint8Array(digest)].map((b) => b.toString(16).padStart(2, "0")).join("");
}

/** sha256OfURL downloads a file and hashes it; fails when the host refuses cross-origin reads. */
export async function sha256OfURL(url: string, signal?: AbortSignal): Promise<string> {
  const res = await fetch(url, signal ? { signal } : {});
  if (!res.ok) throw new Error(`The host returned ${String(res.status)}`);
  return sha256Hex(await res.arrayBuffer());
}
