// A per-IP rate limit for the robot's and the preview image's functions.

// The first line of defence is each function's config.rateLimit: Netlify refuses
// the excess before the function runs, so it is not billed. This one is the
// second, inside the function. ponytail: in memory, per instance, so its real
// ceiling is perMinute × instances; a shared store (Netlify Blobs) if that matters.
const hits = new Map<string, number[]>();
const MAX_KEYS = 10_000;

/** clientKey: an IPv4 address, or an IPv6 address's /64 (one network hands out the whole /64), "::" expanded first. */
export function clientKey(ip: string): string {
  if (!ip.includes(":")) return ip;
  const v4 = /(\d+\.\d+\.\d+\.\d+)$/.exec(ip); // ::ffff:1.2.3.4
  if (v4?.[1]) return v4[1];
  const [head = "", tail] = ip.toLowerCase().split("::");
  const h = head ? head.split(":") : [];
  const t = tail ? tail.split(":") : [];
  const groups = tail === undefined ? h : [...h, ...Array<string>(Math.max(0, 8 - h.length - t.length)).fill("0"), ...t];
  return groups.slice(0, 4).map((g) => g.replace(/^0+(?=.)/, "")).join(":");
}

/** tooMany counts a call from req's client and tells whether it is over perMinute in the last minute. */
export function tooMany(req: Request, perMinute: number): boolean {
  // Netlify sets this header itself: a client cannot choose it.
  const ip = clientKey(req.headers.get("x-nf-client-connection-ip") ?? "");
  const now = Date.now();
  const recent = (hits.get(ip) ?? []).filter((t) => now - t < 60_000);
  recent.push(now);
  hits.delete(ip); // re-inserted last: the map stays oldest first
  hits.set(ip, recent);
  // Bounded memory: drop the least recently seen clients, never every counter at once.
  for (const k of hits.keys()) { if (hits.size <= MAX_KEYS) break; hits.delete(k); }
  return recent.length > perMinute;
}

/** rateLimit is Netlify's per-IP limit, applied before invocation (config.rateLimit). */
export const rateLimit = (perMinute: number) => ({ windowLimit: perMinute, windowSize: 60, aggregateBy: ["ip", "domain"] as ["ip", "domain"] });
