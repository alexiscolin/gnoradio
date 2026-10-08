// The link-preview image of a page: /og/track/12.png, /og/live/3.png… (the
// edge function meta.ts points og:image here). A 1200×630 PNG in og.png's
// Bauhaus layout: the page's cover (its real one, else the same generated
// composition as Cover.tsx), big title, a line, the brand shapes. An SVG drawn
// here, rasterised by resvg (wasm) with Geist. Anything wrong: /og.png.
import { readFileSync } from "node:fs";
import { createRequire } from "node:module";
import { inflateSync } from "node:zlib";
import { Resvg, initWasm } from "@resvg/resvg-wasm";
import { type Card, cardOf, version } from "../cards";
import { rateLimit, tooMany } from "../limit";
import { esc, fnv } from "../../src/lib/format";
import { coverHost, mediaURLs } from "../../src/lib/safe";
import { serverRPC } from "../../src/lib/network";

export const config = { path: "/og/*", rateLimit: rateLimit(30) };

const W = 1200;
const H = 630;
const C = { ground: "#f4f2ec", ink: "#0d0d0d", red: "#e5432f", yellow: "#f2b51d", blue: "#2445c9", paper: "#f2efe9", stone: "#8f8b84" };
// An hour, then the CDN serves the old image once while it draws the new one: a hidden
// track or artist leaves the previews within the hour (cardOf then fails: /og.png).
const CACHE = { "cache-control": "public, max-age=3600", "netlify-cdn-cache-control": "public, s-maxage=3600, stale-while-revalidate=86400" };
/** PER_MINUTE: images drawn for one client IP a minute (preview bots fetch a few). */
const PER_MINUTE = 30;

// ---- fonts: Geist from @fontsource (WOFF 1: zlib tables, unwrapped to the TrueType resvg reads) ----

/** sfnt turns a WOFF 1 file back into the font it wraps. */
function sfnt(woff: Uint8Array): Uint8Array {
  const v = new DataView(woff.buffer, woff.byteOffset, woff.byteLength);
  const n = v.getUint16(12);
  const tables = Array.from({ length: n }, (_, i) => {
    const d = 44 + i * 20;
    const [off, comp, orig] = [v.getUint32(d + 4), v.getUint32(d + 8), v.getUint32(d + 12)];
    const raw = woff.subarray(off, off + comp);
    return { tag: v.getUint32(d), sum: v.getUint32(d + 16), data: comp < orig ? new Uint8Array(inflateSync(raw)) : raw };
  });
  let size = 12 + 16 * n;
  for (const t of tables) size += (t.data.length + 3) & ~3;
  const out = new Uint8Array(size);
  const o = new DataView(out.buffer);
  o.setUint32(0, v.getUint32(4)); // flavor
  o.setUint16(4, n);
  const p2 = 2 ** Math.floor(Math.log2(n));
  o.setUint16(6, p2 * 16);
  o.setUint16(8, Math.log2(p2));
  o.setUint16(10, n * 16 - p2 * 16);
  let at = 12 + 16 * n;
  tables.forEach((t, i) => {
    const d = 12 + i * 16;
    o.setUint32(d, t.tag);
    o.setUint32(d + 4, t.sum);
    o.setUint32(d + 8, at);
    o.setUint32(d + 12, t.data.length);
    out.set(t.data, at);
    at += (t.data.length + 3) & ~3;
  });
  return out;
}

/** advances maps each character of a font to its advance width, in em. */
function advances(ttf: Uint8Array): Map<number, number> {
  const v = new DataView(ttf.buffer, ttf.byteOffset, ttf.byteLength);
  const table = (tag: string) => {
    for (let i = 0; i < v.getUint16(4); i++) if (String.fromCharCode(...ttf.subarray(12 + i * 16, 16 + i * 16)) === tag) return v.getUint32(12 + i * 16 + 8);
    throw new Error(`font: no ${tag}`);
  };
  const upm = v.getUint16(table("head") + 18);
  const nh = v.getUint16(table("hhea") + 34);
  const hmtx = table("hmtx");
  const adv = (g: number) => v.getUint16(hmtx + 4 * Math.min(g, nh - 1)) / upm;
  const cmap = table("cmap");
  const out = new Map<number, number>();
  for (let i = 0; i < v.getUint16(cmap + 2); i++) {
    const sub = cmap + v.getUint32(cmap + 4 + i * 8 + 4);
    if (v.getUint16(sub) !== 4) continue; // format 4: the Basic Multilingual Plane, all Geist's latin subsets hold
    const segs = v.getUint16(sub + 6) / 2;
    for (let s = 0; s < segs; s++) {
      const end = v.getUint16(sub + 14 + s * 2);
      const start = v.getUint16(sub + 16 + segs * 2 + s * 2);
      const delta = v.getInt16(sub + 16 + segs * 4 + s * 2);
      const roAt = sub + 16 + segs * 6 + s * 2;
      const ro = v.getUint16(roAt);
      for (let c = start; c <= end && c !== 0xffff; c++) {
        const g = ro === 0 ? (c + delta) & 0xffff : v.getUint16(roAt + ro + (c - start) * 2);
        if (g !== 0) out.set(c, adv(ro === 0 ? g : (g + delta) & 0xffff));
      }
    }
  }
  return out;
}

interface Fonts { buffers: Uint8Array[]; em: Record<400 | 600, Map<number, number>> }
let ready: Promise<Fonts> | undefined;

/** load starts resvg and reads Geist once per instance (the cold start). */
function load(): Promise<Fonts> {
  ready ??= (async () => {
    const req = createRequire(import.meta.url);
    await initWasm(readFileSync(req.resolve("@resvg/resvg-wasm/index_bg.wasm")));
    const font = (f: string) => sfnt(readFileSync(req.resolve(`@fontsource/geist/files/geist-${f}-normal.woff`)));
    const [l4, x4, l6, x6] = ["latin-400", "latin-ext-400", "latin-600", "latin-ext-600"].map(font) as [Uint8Array, Uint8Array, Uint8Array, Uint8Array];
    const both = (a: Uint8Array, b: Uint8Array) => new Map([...advances(b), ...advances(a)]);
    return { buffers: [l4, x4, l6, x6], em: { 400: both(l4, x4), 600: both(l6, x6) } };
  })();
  ready.catch(() => { ready = undefined; });
  return ready;
}

// ---- text ----

interface Style { size: number; weight: 400 | 600; track: number }

/** fit keeps the characters Geist draws (another script would come out blank) and folds the whitespace. */
const fit = (f: Fonts, s: string) => Array.from(s.normalize("NFC")).filter((ch) => /\s/.test(ch) || f.em[400].has(ch.codePointAt(0) ?? 0)).join("").replace(/\s+/g, " ").trim();

const width = (f: Fonts, s: string, st: Style) => Array.from(s).reduce((w, ch) => w + (f.em[st.weight].get(ch.codePointAt(0) ?? 0) ?? 0.6) * st.size + st.track * st.size, 0);

/** wrap breaks s into lines of at most max pixels, the last one cut with an ellipsis when s does not fit in n lines. */
function wrap(f: Fonts, s: string, st: Style, max: number, n: number): { lines: string[]; cut: boolean } {
  const lines: string[] = [];
  let line = "";
  const words = s.split(" ");
  for (let i = 0; i < words.length; i++) {
    const word = words[i] ?? "";
    const next = line ? `${line} ${word}` : word;
    if (width(f, next, st) <= max) { line = next; continue; }
    if (line) { lines.push(line); line = ""; i--; continue; } // the word starts the next line
    let part = ""; // a word wider than a line breaks anywhere
    for (const ch of word) {
      if (width(f, part + ch, st) > max) { lines.push(part); part = ""; }
      part += ch;
    }
    line = part;
  }
  if (line) lines.push(line);
  if (lines.length <= n) return { lines, cut: false };
  let last = lines[n - 1] ?? "";
  while (last && width(f, `${last}…`, st) > max) last = last.slice(0, -1);
  return { lines: [...lines.slice(0, n - 1), `${last.trimEnd()}…`], cut: true };
}

const text = (s: string, x: number, y: number, st: Style, fill: string) =>
  `<text x="${String(x)}" y="${String(y)}" font-family="${st.weight === 600 ? "Geist SemiBold" : "Geist"}" font-size="${String(st.size)}" font-weight="${String(st.weight)}" letter-spacing="${(st.track * st.size).toFixed(2)}" fill="${fill}">${esc(s)}</text>`;

// ---- the cover ----

/** composition draws Cover.tsx's generated cover (styles.css .cover.v0…v5) in a 100×100 box. */
export function composition(seed: string): string {
  switch (fnv(seed) % 6) {
    case 0: return `<rect width="100" height="100" fill="${C.ink}"/><circle cx="50" cy="50" r="32" fill="${C.yellow}"/><rect x="66" y="66" width="34" height="34" fill="${C.red}"/>`;
    case 1: return `<rect width="100" height="100" fill="${C.paper}"/><path d="M0 100V30A70 70 0 0 1 70 100z" fill="${C.blue}"/><circle cx="73" cy="27" r="13" fill="${C.red}"/>`;
    case 2: return `<rect width="100" height="100" fill="${C.red}"/><rect y="50" width="100" height="50" fill="${C.paper}"/><rect x="32" y="32" width="36" height="36" fill="${C.ink}"/>`;
    case 3: return `<rect width="100" height="100" fill="${C.yellow}"/><rect width="50" height="100" fill="${C.ink}"/><circle cx="50" cy="50" r="20" fill="${C.paper}"/>`;
    case 4: return `<rect width="100" height="100" fill="${C.blue}"/><path d="M50 50L88 88H12z" fill="${C.yellow}"/><circle cx="50" cy="26" r="12" fill="${C.paper}"/>`;
    default: return `<rect width="100" height="100" fill="${C.paper}"/><rect x="10" y="10" width="50" height="50" fill="${C.red}"/><path d="M40 90A50 50 0 0 1 90 40V90z" fill="${C.ink}"/>`;
  }
}

const MAX_IMAGE = 4 << 20;
/** MAX_SIDE: a cover is drawn 390 px wide; a larger image is refused before resvg decodes it (a small file can unpack to gigabytes). */
const MAX_SIDE = 4096;

/** readCapped reads a body up to max bytes; null when longer (a body without content-length included). */
async function readCapped(body: ReadableStream<Uint8Array>, max: number): Promise<Uint8Array | null> {
  const reader = body.getReader();
  const parts: Uint8Array[] = [];
  let size = 0;
  for (;;) {
    const { done, value } = await reader.read();
    if (done) break;
    size += value.length;
    if (size > max) { await reader.cancel(); return null; }
    parts.push(value);
  }
  return new Uint8Array(Buffer.concat(parts));
}

/** dims reads an image's width and height from its header (PNG, JPEG, GIF, WebP), null when it cannot. */
export function dims(b: Uint8Array): [number, number] | null {
  const u16 = (i: number) => ((b[i] ?? 0) << 8) | (b[i + 1] ?? 0);
  const le = (i: number, n: number) => Array.from({ length: n }, (_, k) => (b[i + k] ?? 0) * 256 ** k).reduce((x, y) => x + y, 0);
  const head = String.fromCharCode(...b.subarray(0, 16));
  if (head.startsWith("\x89PNG")) return b.length >= 24 ? [u16(16) * 65536 + u16(18), u16(20) * 65536 + u16(22)] : null;
  if (head.startsWith("GIF8")) return b.length >= 10 ? [le(6, 2), le(8, 2)] : null;
  if (head.startsWith("RIFF") && head.slice(8, 12) === "WEBP") {
    const chunk = head.slice(12, 16);
    if (chunk === "VP8 " && b.length >= 30) return [le(26, 2) & 0x3fff, le(28, 2) & 0x3fff];
    if (chunk === "VP8L" && b.length >= 25) { const v = le(21, 4); return [(v & 0x3fff) + 1, ((v >>> 14) & 0x3fff) + 1]; }
    if (chunk === "VP8X" && b.length >= 30) return [le(24, 3) + 1, le(27, 3) + 1];
    return null;
  }
  if (head.startsWith("\xff\xd8")) {
    // Walk the segments to the frame header (SOF0-SOF15 but DHT, JPG, DAC).
    for (let i = 2; i + 9 < b.length;) {
      if (b[i] !== 0xff) return null;
      const m = b[i + 1] ?? 0;
      if (m === 0xff) { i++; continue; }
      if (m >= 0xc0 && m <= 0xcf && m !== 0xc4 && m !== 0xc8 && m !== 0xcc) return [u16(i + 7), u16(i + 5)];
      i += 2 + u16(i + 2);
    }
  }
  return null;
}

/** fetchImage reads an image from an allowed host (redirects too), small and quick, as a data URL; "" otherwise. */
async function fetchImage(url: string, ok: (u: string) => boolean, signal: AbortSignal): Promise<string> {
  let at = url;
  for (let hop = 0; hop < 4; hop++) {
    if (!ok(at)) return "";
    const r = await fetch(at, { redirect: "manual", signal, headers: { "user-agent": "GnoRadio-og/1" } });
    const next = r.status >= 300 && r.status < 400 ? r.headers.get("location") : null;
    if (next !== null) { at = new URL(next, at).href; continue; }
    if (!r.ok || !r.body || Number(r.headers.get("content-length") ?? 0) > MAX_IMAGE) return "";
    const b = await readCapped(r.body, MAX_IMAGE);
    if (!b) return "";
    // The bytes say what the image is, whatever the server claims: only formats resvg draws, of a sane size.
    const head = String.fromCharCode(...b.subarray(0, 12));
    const type = head.startsWith("\xff\xd8\xff") ? "jpeg" : head.startsWith("\x89PNG") ? "png" : head.startsWith("GIF8") ? "gif" : head.startsWith("RIFF") && head.endsWith("WEBP") ? "webp" : "";
    const [w = 0, h = 0] = dims(b) ?? [];
    if (!type || w < 1 || h < 1 || w > MAX_SIDE || h > MAX_SIDE) return "";
    return `data:image/${type};base64,${Buffer.from(b).toString("base64")}`;
  }
  return "";
}

/**
 * cover resolves a card's real cover as Cover.tsx does (https, IPFS, Arweave),
 * fetched only from coverHost's hosts. A pointer's platform artwork is never
 * fetched here: the preview shows the generated cover.
 */
export async function cover(ref: string): Promise<string> {
  const url = ref && !/^(audius|jamendo):/.test(ref) ? mediaURLs(ref)[0] : undefined;
  return url ? fetchImage(url, coverHost, AbortSignal.timeout(4000)) : "";
}

// ---- the card ----

const S = { kicker: { size: 21, weight: 600, track: 0.1 }, by: { size: 36, weight: 400, track: -0.01 }, foot: { size: 18, weight: 400, track: 0.12 } } as const;
const TITLES = ([[96, 1], [84, 1], [96, 2], [84, 2], [72, 2], [60, 3]] as const).map(([size, n]): [Style, number] => [{ size, weight: 600, track: -0.045 }, n]);
const LEFT = 76;
const COL = 600;
// og.png's right block (x 680–1130, y 70–550): the cover, and under it its four shapes in a row.
const BOX = { x: 740, y: 70, s: 390 };

/** svg draws the card: the text column left, the cover framed by the brand shapes right. */
export function svg(f: Fonts, c: Card, art: string): string {
  const title = fit(f, c.title) || "GnoRadio";
  // One line if it holds at a big size, else two (three at the smallest), else cut.
  const fits = TITLES.map(([st, n]) => ({ st, ...wrap(f, title, st, COL, n) }));
  const t = fits.reduceRight((best, x) => (x.cut ? best : x)); // the first that fits, else the last
  const kicker = wrap(f, fit(f, c.kicker).toUpperCase(), S.kicker, COL, 1).lines[0] ?? "";
  const by = wrap(f, fit(f, c.by), S.by, COL, 1).lines[0] ?? "";
  const lh = t.st.size * 1.0;
  // The block (kicker, title, by) sits centred between the wordmark and the footer.
  const block = S.kicker.size + 34 + t.lines.length * lh + (by ? 26 + S.by.size : 0);
  let y = Math.round(150 + (510 - 150 - block) / 2) + S.kicker.size;
  const parts = [text(kicker, LEFT, y, S.kicker, C.red)];
  y += 34;
  for (const l of t.lines) { y += lh; parts.push(text(l, LEFT - t.st.size * 0.04, y - t.st.size * 0.12, t.st, C.ink)); }
  if (by) { y += 26 + S.by.size * 0.8; parts.push(text(by, LEFT, y, S.by, C.ink)); }
  const { x, y: by0, s } = BOX;
  const pic = art
    ? `<image href="${art}" x="${String(x)}" y="${String(by0)}" width="${String(s)}" height="${String(s)}" preserveAspectRatio="xMidYMid slice" clip-path="url(#box)"/>`
    : `<svg x="${String(x)}" y="${String(by0)}" width="${String(s)}" height="${String(s)}" viewBox="0 0 100 100">${composition(c.seed)}</svg>`;
  return `<svg xmlns="http://www.w3.org/2000/svg" width="${String(W)}" height="${String(H)}" viewBox="0 0 ${String(W)} ${String(H)}">
<defs><clipPath id="box"><rect x="${String(x)}" y="${String(by0)}" width="${String(s)}" height="${String(s)}"/></clipPath></defs>
<rect width="${String(W)}" height="${String(H)}" fill="${C.ground}"/>
${pic}
<rect x="${String(x + 0.75)}" y="${String(by0 + 0.75)}" width="${String(s - 1.5)}" height="${String(s - 1.5)}" fill="none" stroke="${C.ink}" stroke-opacity=".1" stroke-width="1.5"/>
<g transform="translate(${String(x)} ${String(by0 + s + 10)})">
<rect width="90" height="90" fill="${C.red}"/>
<path d="M100 90V0A90 90 0 0 1 190 90z" fill="${C.blue}"/>
<circle cx="245" cy="45" r="45" fill="${C.yellow}"/>
<path d="M345 0L390 90H300z" fill="${C.ink}"/>
</g>
${text("GnoRadio", LEFT, 104, { size: 38, weight: 600, track: -0.04 }, C.ink)}<circle cx="${String(LEFT + width(f, "GnoRadio", { size: 38, weight: 600, track: -0.04 }) + 7)}" cy="99" r="5.5" fill="${C.red}"/>
${parts.join("\n")}
${text("BUILT ON GNO.LAND · YOUR SONG. ON AIR. FOR EVERYONE.", LEFT, 566, S.foot, C.stone)}
</svg>`;
}

/** render draws the card as a PNG; cached tells whether it may be kept long (the real cover came, or there is none). */
export async function render(c: Card): Promise<{ png: Uint8Array; cached: boolean }> {
  const f = await load();
  const art = await cover(c.art).catch(() => "");
  const r = new Resvg(svg(f, c, art), { font: { fontBuffers: f.buffers, defaultFontFamily: "Geist" }, fitTo: { mode: "width", value: W } });
  try {
    return { png: r.render().asPng(), cached: !c.art || art !== "" };
  } finally {
    r.free();
  }
}

const fallback = (origin: string, cache = "public, max-age=300") => new Response(null, { status: 302, headers: { location: `${origin}/og.png`, "cache-control": cache } });

export default async (req: Request): Promise<Response> => {
  const url = new URL(req.url);
  const path = /^\/og(\/[a-z]+\/[\w-]{1,120}|\/features)\.png$/.exec(url.pathname)?.[1];
  if (path === undefined) return fallback(url.origin);
  // Every new URL misses the CDN: one client IP gets PER_MINUTE renders, then the default image, not cached.
  if (tooMany(req, PER_MINUTE)) return fallback(url.origin, "no-store");
  const rpc = serverRPC();
  try {
    const out = await Promise.race([
      (async () => {
        const c = await cardOf(rpc, path);
        if (!c) return null;
        // One URL per card and version: any other slug or ?v (each a new CDN key) goes to it, undrawn.
        const canonical = `/og${c.path}.png?v=${version(c)}`;
        if (`${url.pathname}${url.search}` !== canonical) return canonical;
        return render(c);
      })(),
      new Promise<null>((resolve) => setTimeout(() => { resolve(null); }, 8000)),
    ]);
    if (!out) return fallback(url.origin);
    if (typeof out === "string") return new Response(null, { status: 302, headers: { location: `${url.origin}${out}`, "cache-control": "public, max-age=300" } });
    return new Response(out.png.slice(), {
      headers: { "content-type": "image/png", ...(out.cached ? CACHE : { "cache-control": "public, max-age=600" }), "netlify-vary": "query=v" },
    });
  } catch {
    return fallback(url.origin);
  }
};
