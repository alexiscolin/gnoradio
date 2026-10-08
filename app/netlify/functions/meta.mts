// /api/meta: the titles, artists and covers of the Audius and Jamendo tracks
// GnoRadio points to (netlify/refs.ts), and Jamendo's stream URLs (the player
// plays them as they are: a play costs no Jamendo call). It is bounded by what is on chain, never by what a client asks for: the
// function reads the chain for the pointers of a bucket (or of a track), and
// asks the platforms for those only. A bucket is one 100-id slice of the
// on-chain track ids, so the cache keys are a finite set (the number of
// buckets) and any other parameter is refused (docs/ARCHITECTURE-v1.md, section 6).
//
//   GET /api/meta?bucket=3        →  { "audius:D7KyD": {…} | null, … }  (a failed platform's refs are left out)
import { bucketOf, metaOf, parseBucket, REF } from "../refs";
import { rateLimit, tooMany } from "../limit";
import { serverRPC } from "../../src/lib/network";

export const config = { path: "/api/meta", rateLimit: rateLimit(120) };

// The platforms' terms allow session caching: the shared copies last three hours (the browser a few minutes).
// Netlify's durable cache holds one copy for every edge, so three hours is one platform call per bucket, not per edge.
const META = { "cache-control": "public, max-age=300", "netlify-cdn-cache-control": "public, durable, s-maxage=10800, stale-while-revalidate=300", "netlify-vary": "query=bucket" };
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
