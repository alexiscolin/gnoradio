// Titles, artists and covers of the Audius and Jamendo tracks GnoRadio points
// to (the chain keeps only audius:<id> / jamendo:<id>): read live from the two
// platforms, whose API terms allow session caching only: the shared copies
// (CDN) last an hour. Used by /api/meta and /api/stream only, and only for
// pointers the chain holds. Fixed hosts only: api.audius.co and
// api.jamendo.com; the stream and artwork URLs they return are checked too.
import { REALMS, runtimeEnv } from "../src/lib/realms";
import { qeval } from "./cards";

/** RefMeta is what the app shows for a pointer; streamable false hides the track. */
export interface RefMeta {
  title: string;
  artist: string;
  artistId: string;
  artwork: string;
  permalink: string;
  streamable: boolean;
}

export const MAX_IDS = 100;
export const REF = /^(audius|jamendo):([A-Za-z0-9]{1,32})$/;
const httpsOn = (u: unknown, host: RegExp): string => {
  try { return typeof u === "string" && /^https:\/\/[^/?#]+/.test(u) && host.test(new URL(u).hostname) ? u : ""; } catch { return ""; } // a malformed URL is no URL
};

interface AudiusTrack { id: string; title?: string; permalink?: string; is_streamable?: boolean; artwork?: Record<string, string>; user?: { id?: string; name?: string } }
interface JamendoTrack { id: string | number; name?: string; artist_name?: string; artist_id?: string | number; image?: string; album_image?: string; shareurl?: string; audio?: string }

async function getJSON<T>(url: string, headers: Record<string, string> = {}): Promise<T> {
  const r = await fetch(url, { headers, signal: AbortSignal.timeout(8000) });
  if (!r.ok) throw new Error(`upstream ${String(r.status)}`);
  return (await r.json()) as T;
}

/** audius reads up to 100 tracks in one call (GET /v1/tracks?id=…&id=…). */
async function audius(ids: string[]): Promise<Map<string, RefMeta>> {
  const key = runtimeEnv("AUDIUS_API_KEY");
  const q = ids.map((id) => `id=${encodeURIComponent(id)}`).join("&");
  const j = await getJSON<{ data?: AudiusTrack[] }>(`https://api.audius.co/v1/tracks?${q}&app_name=GnoRadio`, key ? { "x-api-key": key } : {});
  if (!Array.isArray(j.data)) throw new Error("upstream audius failed"); // an error, not "unknown tracks"
  return new Map(j.data.map((t) => [t.id, {
    title: t.title ?? "", artist: t.user?.name ?? "", artistId: t.user?.id ?? "",
    artwork: httpsOn(t.artwork?.["480x480"], /./), permalink: t.permalink ? `https://audius.co${t.permalink}` : "",
    streamable: t.is_streamable !== false,
  }]));
}

/** JAMENDO_IDS: Jamendo takes at most 50 values per parameter (checked live: 100 is refused). */
const JAMENDO_IDS = 50;

/** jamendo reads the tracks 50 ids a call (id=1+2+3); its audio URL is for /api/stream only. */
export async function jamendo(ids: string[]): Promise<Map<string, RefMeta & { audio: string }>> {
  const client = runtimeEnv("JAMENDO_CLIENT_ID");
  if (!client) throw new Error("JAMENDO_CLIENT_ID is not set"); // an error (never cached), not "unknown tracks"
  const chunks = Array.from({ length: Math.ceil(ids.length / JAMENDO_IDS) }, (_, i) => ids.slice(i * JAMENDO_IDS, (i + 1) * JAMENDO_IDS));
  const pages = await Promise.all(chunks.map((c) => getJSON<{ headers?: { status?: string }; results?: JamendoTrack[] }>(
    `https://api.jamendo.com/v3.0/tracks/?client_id=${encodeURIComponent(client)}&format=json&limit=${String(JAMENDO_IDS)}&audioformat=mp32&id=${c.join("+")}`)));
  // Jamendo answers errors with HTTP 200 and headers.status "failed": an error, not "unknown tracks".
  if (pages.some((j) => j.headers?.status !== "success")) throw new Error("upstream jamendo failed");
  return new Map(pages.flatMap((j) => j.results ?? []).map((t) => {
    const audio = httpsOn(t.audio, /(^|\.)jamendo\.com$/);
    return [String(t.id), {
      title: t.name ?? "", artist: t.artist_name ?? "", artistId: String(t.artist_id ?? ""),
      artwork: httpsOn([t.album_image, t.image].find(Boolean), /(^|\.)jamendo\.com$/), permalink: httpsOn(t.shareurl, /(^|\.)jamendo\.com$/),
      streamable: audio !== "", audio,
    }];
  }));
}

/** metaOf answers the refs it was given: null for one the platform does not know (or no longer serves), and no key at
 * all for the refs of a platform that failed (unknown, retry: partial is then true). It throws only when every platform
 * asked failed. */
export async function metaOf(refs: string[]): Promise<{ meta: Record<string, RefMeta | null>; partial: boolean }> {
  const by = { audius: [] as string[], jamendo: [] as string[] };
  for (const r of refs) {
    const m = REF.exec(r);
    if (m?.[1] === "audius" || m?.[1] === "jamendo") by[m[1]].push(m[2] ?? "");
  }
  const asked = [by.audius.length ? audius(by.audius) : null, by.jamendo.length ? jamendo(by.jamendo) : null];
  const [a, j] = await Promise.allSettled(asked.map((p) => p ?? Promise.resolve(new Map())));
  const out: Record<string, RefMeta | null> = {};
  let failed = 0, ok = 0;
  if (a?.status === "fulfilled") { if (by.audius.length) ok++; for (const id of by.audius) out[`audius:${id}`] = (a.value.get(id) as RefMeta | undefined) ?? null; } else failed++;
  if (j?.status === "fulfilled") {
    if (by.jamendo.length) ok++;
    for (const id of by.jamendo) {
      const m = j.value.get(id) as (RefMeta & { audio: string }) | undefined;
      out[`jamendo:${id}`] = m ? { title: m.title, artist: m.artist, artistId: m.artistId, artwork: m.artwork, permalink: m.permalink, streamable: m.streamable } : null;
    }
  } else failed++;
  if (failed > 0 && ok === 0) throw new Error("no music source answered");
  return { meta: out, partial: failed > 0 };
}

/** bucketOf reads the chain for the pointers among the track ids of bucket n (ids n*100 to n*100+99, as the app
 * cuts them): one page read after a count read, hidden tracks left out. Only these are ever asked of a platform. */
export async function bucketOf(rpc: string, n: number): Promise<string[]> {
  const total = (JSON.parse(await qeval(rpc, REALMS.catalog, "TracksJSON(0, 1)")) as { total: number }).total;
  const lo = Math.max(1, n * MAX_IDS), hi = Math.min(n * MAX_IDS + MAX_IDS - 1, total);
  if (lo > hi) return [];
  const page = JSON.parse(await qeval(rpc, REALMS.catalog, `TracksJSON(${String(total - hi)}, ${String(hi - lo + 1)})`)) as { tracks: { id: number; audio: string }[] };
  return [...new Set(page.tracks.filter((t) => t.id >= lo && t.id <= hi && REF.test(t.audio)).map((t) => t.audio))].sort();
}

/** audioOf is the audio reference of track id on chain; RealmError when it is unknown or hidden. */
export async function audioOf(rpc: string, id: number): Promise<string> {
  return (JSON.parse(await qeval(rpc, REALMS.catalog, `TrackJSON(${String(id)})`)) as { audio: string }).audio;
}

/** parseBucket reads ?bucket=N as the only query param, a canonical number (no sign, zeros or fraction); null otherwise. */
export function parseBucket(params: URLSearchParams): number | null {
  const b = params.get("bucket");
  return [...params.keys()].length === 1 && params.getAll("bucket").length === 1 && b !== null && /^(0|[1-9]\d{0,5})$/.test(b) ? Number(b) : null;
}
