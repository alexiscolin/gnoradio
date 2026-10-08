// On-air info: what the player says about the moment, one quiet line at a time.
import type { ScheduleEntry, Track } from "./types";

/** The 3-hour UTC blocks of the main station's flow (radio/v1 flow.gno dayparts). */
const DAYPARTS = ["Night", "Early morning", "Morning", "Midday", "Afternoon", "Drive time", "Evening", "Late night"] as const;

/** daypart names the UTC 3-hour block of a chain timestamp (seconds). */
export const daypart = (ts: number): string => DAYPARTS[Math.floor((((ts % 86400) + 86400) % 86400) / 10800)] ?? "Night";

/** setName titles a Main set: "Late-night Ambient set". */
export function setName(genre: string, ts: number): string {
  const d = daypart(ts).replace(" ", "-");
  return genre ? `${d} ${genre} set` : `${d} set`;
}

type NoteKind = "pick" | "curator" | "new" | "favourite" | "next" | "intro" | "artist";
export interface Note { readonly kind: NoteKind; readonly text: string }

const WEEK = 7 * 86400;

/** favouriteMin is the like count a track needs to be a listener favourite: the top 10, at least 3 likes. */
export function favouriteMin(tracks: readonly Pick<Track, "likes">[]): number {
  const top = tracks.map((t) => t.likes).sort((a, b) => b - a)[9] ?? 0;
  return Math.max(3, top);
}

/**
 * why is the one reason a track plays, most meaningful first: a listener's pick,
 * a curator's pick, a new release, a listener favourite. Plain rotation says nothing.
 */
export function why(t: (Pick<Track, "created" | "likes"> & { readonly artistName?: string }) | undefined, entry: Pick<ScheduleEntry, "queued" | "by" | "sponsored"> | undefined, now: number, favMin: number, who: (a: string) => string): Note | null {
  if (entry?.queued && entry.sponsored) return { kind: "pick", text: `sponsored pick · paid by ${t?.artistName ?? "the artist"}` };
  if (entry?.queued) return entry.by ? { kind: "pick", text: `picked by ${who(entry.by)}` } : { kind: "curator", text: "curator pick" };
  if (!t) return null;
  if (t.created > 0 && now - t.created < WEEK) return { kind: "new", text: "new release" };
  if (t.likes >= favMin) return { kind: "favourite", text: "listener favourite" };
  return null;
}

/**
 * nextSet finds when the flow switches genre: the first programmed (not picked)
 * entry after now whose genre differs from the set on air. Picks are skipped
 * both ways, they interrupt a set without ending it.
 */
export function nextSet(entries: readonly ScheduleEntry[], now: number, genreOf: (track: number) => number): { genre: number; at: number } | null {
  const flow = entries.filter((e) => !e.queued);
  const cur = flow.filter((e) => e.start <= now).at(-1);
  if (!cur) return null;
  const g = genreOf(cur.track);
  const n = flow.find((e) => e.start > now && genreOf(e.track) !== g && genreOf(e.track) !== 0);
  return n ? { genre: genreOf(n.track), at: n.start } : null;
}

/** inMinutes reads a countdown: "in 1 min", "in 12 min". */
export const inMinutes = (s: number): string => `in ${String(Math.max(1, Math.round(s / 60)))} min`;

/** shortBio is the first sentence of a bio, cut on a word near max characters. */
export function shortBio(bio: string, max = 90): string {
  const flat = bio.replace(/\s+/g, " ").trim();
  const first = /^.+?[.!?](?=\s|$)/.exec(flat)?.[0] ?? flat;
  if (first.length <= max) return first;
  const cut = first.slice(0, max);
  const sp = cut.lastIndexOf(" ");
  return `${(sp > max / 2 ? cut.slice(0, sp) : cut).replace(/[\s,;:.–-]+$/, "")}…`;
}

const TEASE_S = 5 * 60; // the next-set teaser shows in the last minutes only
const INTRO_S = 15; // set name / station line after a tune-in or a new track
const ARTIST_S = 45; // then the artist's line, until here

/**
 * pickNote chooses the one line the player shows now (since: seconds since the
 * track or station changed). A listener's pick always keeps its credit; else
 * the coming set in its last minutes, the intro, the artist, then a reason.
 */
export function pickNote(since: number, n: { why: Note | null; next: Note | null; nextIn: number; intro: Note | null; artist: Note | null }): Note | null {
  if (n.why?.kind === "pick") return n.why;
  if (n.next && n.nextIn > 0 && n.nextIn <= TEASE_S) return n.next;
  if (since < INTRO_S && n.intro) return n.intro;
  if (since < ARTIST_S && n.artist) return n.artist;
  return n.why;
}

// One line per station, keyed by the name the chain gives it.
const STATION_LINES: Readonly<Record<string, string>> = {
  Main: "Everything, programmed like a real radio",
  Electronica: "Off the dancefloor: IDM, glitch, downtempo and odd machines",
  Synthwave: "Neon, chrome and night drives that never end",
  Ambient: "Ambient around the clock, from calm drones to deep space",
  Techno: "Four on the floor, straight from the warehouse",
  House: "Warm chords, soulful voices, a kick that never quits",
  "Drum & Bass": "Rolling breaks at 174, liquid to neurofunk",
  "Dubstep & Trap": "Low end first: wobbles, halftime and festival trap",
  "Lo-fi Beats": "Dusty beats to read, code or watch the rain to",
  "Hip-hop & Rap": "Bars over beats, boom bap to the newest flows",
  "R&B & Soul": "Smooth voices and slow grooves, old souls and new",
  "Rock & Indie": "Guitars up: garage, indie and the bands you'll love next",
  "Metal & Punk": "Loud, fast and proudly unpolished",
  Pop: "Hooks you'll hum all day",
  "Jazz & Blues": "Late-night standards, blue notes and new improvisers",
  "Folk & Acoustic": "Wood, strings and stories told close to the mic",
  "Cinematic & Classical": "Scores, strings and pieces that need no words",
  World: "Sounds from everywhere, rhythms from every corner",
  Latin: "Cumbia, reggaeton, bossa and everything that sways",
  "Reggae & Dub": "Roots, rockers and deep echo chambers",
  "Funk & Disco": "Slap bass, strings and mirror balls",
  "New this week": "The 300 newest tracks on GnoRadio",
  "Listeners' choice": "Every track listeners picked lately, back on air",
};

/** stationLine is a station's one-line identity, with a fallback for names not written yet. */
export const stationLine = (name: string, genre = 0): string =>
  STATION_LINES[name] ?? (genre > 0 ? `${name}, all day and all night` : "Live for everyone, the same second");

/**
 * pickerOf is who a tip on air shares the artist's promo share with (radio.TipOnAir):
 * the listener whose pick is playing. Not the admin's picks, and not a sponsored pick,
 * whose picker the realm never pays from tips. undefined: nobody.
 */
export const pickerOf = (onAir: Pick<ScheduleEntry, "queued" | "by" | "sponsored"> | undefined, admin: string): string | undefined =>
  onAir?.queued && !onAir.sponsored && onAir.by !== admin ? onAir.by : undefined;
