// /api/meta: the titles, artists and covers of the Audius and Jamendo tracks
// GnoRadio points to (netlify/refs.ts). One call answers up to 100 tracks, and
// the CDN keeps the answer 6 hours for every visitor, so the platforms see a
// few calls a day whatever the audience (docs/ARCHITECTURE-v1.md, section 6).
//
//   GET /api/meta?ids=audius:D7KyD,jamendo:1886257  →  { "audius:D7KyD": {…} | null, … }
//   GET /api/jamendo/1886257                         →  302 to the stream (the API's audio URL)
import { jamendo, MAX_IDS, metaOf, parseIDs } from "../refs";
import { rateLimit, tooMany } from "../limit";

export const config = { path: ["/api/meta", "/api/jamendo/:id"], rateLimit: rateLimit(120) };

// Meta: the browser keeps it 6 h; Netlify's durable cache (one copy for every edge) 6 h, then serves it
// stale for a day while one call refreshes it. A stream URL stays the same: its redirect is kept 30 days.
const META = { "cache-control": "public, max-age=21600", "netlify-cdn-cache-control": "public, durable, s-maxage=21600, stale-while-revalidate=86400" };
const STREAM = { "cache-control": "public, max-age=86400", "netlify-cdn-cache-control": "public, durable, s-maxage=2592000" };
const NONE = { "cache-control": "no-store" };

const json = (status: number, body: unknown, cache: Record<string, string> = NONE) =>
  new Response(JSON.stringify(body), { status, headers: { "content-type": "application/json", ...cache } });

export default async (req: Request): Promise<Response> => {
  if (req.method !== "GET") return json(405, { error: "GET only" });
  if (tooMany(req, 120)) return json(429, { error: "Too many requests, try again in a minute." });
  const url = new URL(req.url);
  try {
    const one = /^\/api\/jamendo\/([A-Za-z0-9]{1,32})$/.exec(url.pathname)?.[1];
    if (one) {
      const audio = (await jamendo([one])).get(one)?.audio ?? "";
      return audio ? new Response(null, { status: 302, headers: { location: audio, ...STREAM } }) : json(404, { error: "Not on Jamendo" }, META);
    }
    const ids = parseIDs(url.searchParams.get("ids"));
    if (!ids) return json(400, { error: `ids: 1 to ${String(MAX_IDS)} of audius:<id> or jamendo:<id>, comma-separated` });
    return json(200, await metaOf(ids), META);
  } catch {
    return json(502, { error: "The music source did not answer, try again later." }); // never cached, never echoes a key
  }
};
