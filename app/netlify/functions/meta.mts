// /api/meta and /api/stream: the titles, artists and covers of the Audius and
// Jamendo tracks GnoRadio points to (netlify/refs.ts), and Jamendo's streams.
// Both are bounded by what is on chain, never by what a client asks for: the
// function reads the chain for the pointers of a bucket (or of a track), and
// asks the platforms for those only. A bucket is one 100-id slice of the
// on-chain track ids, so the cache keys are a finite set (the number of
// buckets) and any other parameter is refused (docs/ARCHITECTURE-v1.md, section 6).
//
//   GET /api/meta?bucket=3        →  { "audius:D7KyD": {…} | null, … }  (a failed platform's refs are left out)
//   GET /api/stream/205           →  302 to the stream of track 205, when it is a jamendo: pointer
import { audioOf, bucketOf, jamendo, metaOf, parseBucket, REF } from "../refs";
import { RealmError } from "../cards";
import { rateLimit, tooMany } from "../limit";
import { serverRPC } from "../../src/lib/network";

export const config = { path: ["/api/meta", "/api/stream/:trackId"], rateLimit: rateLimit(120) };

// The platforms' terms allow session caching: the shared copies last an hour (the browser a few minutes).
// Netlify's durable cache holds one copy for every edge, so one hour is one platform call per bucket, not per edge.
const META = { "cache-control": "public, max-age=300", "netlify-cdn-cache-control": "public, durable, s-maxage=3600, stale-while-revalidate=300", "netlify-vary": "query=bucket" };
// A stream URL is kept an hour at most, and never in the durable cache: a removed track stops within the hour.
const STREAM = { "cache-control": "public, max-age=300", "netlify-cdn-cache-control": "public, s-maxage=3600" };
// An answer that is incomplete or may be transient: a minute at the CDN, none in the browser.
const SHORT = { "cache-control": "no-store", "netlify-cdn-cache-control": "public, s-maxage=60" };
const NONE = { "cache-control": "no-store" };

const json = (status: number, body: unknown, cache: Record<string, string> = NONE) =>
  new Response(JSON.stringify(body), { status, headers: { "content-type": "application/json", ...cache } });

export default async (req: Request): Promise<Response> => {
  if (req.method !== "GET") return json(405, { error: "GET only" });
  if (tooMany(req, 120)) return json(429, { error: "Too many requests, try again in a minute." });
  const url = new URL(req.url);
  try {
    const one = /^\/api\/stream\/(0|[1-9]\d{0,8})$/.exec(url.pathname)?.[1];
    if (one !== undefined) {
      if ([...url.searchParams.keys()].length > 0) return json(400, { error: "No query parameters" });
      const audio = await audioOf(serverRPC(), Number(one)).catch((e: unknown) => { if (e instanceof RealmError) return ""; throw e; });
      const id = /^jamendo:([A-Za-z0-9]{1,32})$/.exec(audio)?.[1];
      if (!id) return json(404, { error: "Not a Jamendo track" }, SHORT);
      const stream = (await jamendo([id])).get(id)?.audio ?? "";
      return stream ? new Response(null, { status: 302, headers: { location: stream, ...STREAM } }) : json(404, { error: "Not on Jamendo" }, SHORT);
    }
    const bucket = parseBucket(url.searchParams);
    if (bucket === null) return json(400, { error: "bucket: the number of one bucket of 100 track ids, and no other parameter" });
    const refs = (await bucketOf(serverRPC(), bucket)).filter((r) => REF.test(r));
    if (refs.length === 0) return json(200, {}, META);
    const { meta, partial } = await metaOf(refs);
    return json(200, meta, partial ? SHORT : META);
  } catch {
    return json(502, { error: "The music source did not answer, try again later." }, SHORT); // never echoes a key
  }
};
