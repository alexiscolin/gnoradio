export const clock = (seconds: number): string => {
  const s = Math.max(0, Math.floor(seconds));
  return `${Math.floor(s / 60)}:${String(s % 60).padStart(2, "0")}`;
};

/** UGNOT is the number of ugnot in one GNOT. */
export const UGNOT = 1_000_000;
/** DEFAULT_GOAL is the monthly goal shown before the admin sets one (ugnot). */
export const DEFAULT_GOAL = 50 * UGNOT;

export const gnot = (ugnot: number): string => `${(ugnot / UGNOT).toLocaleString("en", { maximumFractionDigits: 2 })} GNOT`;

export const shortAddr = (a: string): string => (a.length > 12 ? `${a.slice(0, 7)}…${a.slice(-4)}` : a);

export const licenseLabel = (l: string): string => (l === "Audius-OML" ? "Audius Open Music License" : l.replaceAll("-", " "));

/**
 * licenseURL links a license id to its text, as home.gno's licenseLink does.
 * Creative Commons ids read CC-<terms>-<version>[-<port>], e.g. CC-BY-SA-3.0-DE →
 * creativecommons.org/licenses/by-sa/3.0/de/. "" when there is no public text.
 */
export function licenseURL(l: string): string {
  if (l === "CC0-1.0") return "https://creativecommons.org/publicdomain/zero/1.0/";
  if (l === "Audius-OML") return "https://openaudiofoundation.org/open-music-license.pdf";
  const m = /^CC-((?:[A-Z]+-)*[A-Z]+)-(\d+\.\d+)(?:-([A-Z]+))?$/i.exec(l);
  if (!m?.[1] || !m[2]) return "";
  return `https://creativecommons.org/licenses/${m[1].toLowerCase()}/${m[2]}/${m[3] ? `${m[3].toLowerCase()}/` : ""}`;
}

export function hostOf(url: string): string {
  try {
    return new URL(url).host.replace(/^www\./, "");
  } catch {
    return "source";
  }
}

/** fnv is the same 32-bit FNV-1a hash the realms use to pick generated covers. */
export function fnv(s: string): number {
  let h = 2166136261 >>> 0;
  for (let i = 0; i < s.length; i++) {
    h ^= s.charCodeAt(i);
    h = Math.imul(h, 16777619) >>> 0;
  }
  return h;
}

// Known realm panics and node errors, in plain words. First match wins.
const PLAIN: readonly (readonly [RegExp, string])[] = [
  [/one track per station per hour/i, "You already picked on this station in the last hour. Try again later."],
  [/programmed two hours ahead/i, "Listeners have filled the next 2 hours of this station. Try again a little later."],
  [/already have a track waiting/i, "Your pick is already waiting on this station."],
  [/already programmed/i, "This track is already coming up on this station."],
  [/queue is full/i, "This station's queue is full for now. Try again later."],
  [/already has 2 tracks in the queue/i, "This artist already has 2 tracks coming up here. Pick someone else."],
  [/does not belong to this station/i, "This track's genre doesn't match this station."],
  [/already liked/i, "You already like this track."],
  [/already following/i, "You already follow this artist."],
  [/sold out/i, "This concert is sold out."],
  [/ticket limit reached/i, "You hold the most tickets allowed for this concert."],
  [/insufficient (funds|coins)|insufficient account funds/i, "Not enough GNOT in your wallet for this, including the storage deposit."],
  [/name is already taken/i, "This artist name is taken, or looks too much like one that is."],
  [/already has an artist profile/i, "This wallet already has an artist profile."],
  [/open reports, wait/i, "You have 5 open reports. Wait for the moderators to handle them."],
  [/paused for an upgrade/i, "GnoRadio is paused for an upgrade. Try again soon."],
  [/host is not allowed/i, "This file host isn't allowed yet. Use IPFS or Arweave, or ask the moderators to add it."],
];

/** errorMessage turns an error into a sentence a listener can act on. */
export function errorMessage(e: unknown): string {
  const raw = e instanceof Error ? e.message : String(e);
  for (const [re, text] of PLAIN) if (re.test(raw)) return text;
  // Strip the realm prefix of other panics ("catalog: …") and capitalize.
  const m = /(?:catalog|radio|tickets|home): ([^\n]+)/.exec(raw);
  if (m?.[1]) return m[1].charAt(0).toUpperCase() + m[1].slice(1);
  return raw;
}

/** firstNonEmpty returns the first non-empty string (realms use "" for "unset"). */
export const firstNonEmpty = (...xs: readonly (string | undefined)[]): string => xs.find((x) => x !== undefined && x !== "") ?? "";

/** plural writes "1 follower", "3 followers". */
export const plural = (n: number, word: string): string => `${String(n)} ${word}${n === 1 ? "" : "s"}`;

/** esc makes text safe in HTML, XML and SVG markup (text and quoted attributes). */
export const esc = (s: string): string => s.replace(/[&<>"']/g, (c) => `&#${String(c.charCodeAt(0))};`);

/** utf8Base64 encodes a string as UTF-8 then base64 (btoa alone mangles anything past Latin-1). */
export const utf8Base64 = (s: string): string => btoa(String.fromCharCode(...new TextEncoder().encode(s)));
