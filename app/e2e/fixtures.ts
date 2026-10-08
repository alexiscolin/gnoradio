import { test as base, expect, type Locator, type Page } from "@playwright/test";
import type { Schedule, Station, Track } from "../src/lib/schemas";

/** The gnodev test1 account: seeded picks and playlists belong to it. */
export const TEST1 = "g1jg8mtutu9khhfwc4nxmuhcpftf0pajdhfvsqf5";
const RPC = "http://127.0.0.1:27157";
const ORIGIN = "http://127.0.0.1:5173";
const CATALOG = "gno.land/r/gnoradio/catalog/v1";
const RADIO = "gno.land/r/gnoradio/radio/v1";

// ---- RPC: what the chain says, so tests never hard-code titles that move with time ----

/** qeval reads `pkg.expr` from the devnet, raw (`("…" string)`). */
async function qeval(pkg: string, expr: string): Promise<string> {
  const res = await fetch(RPC, {
    method: "POST",
    headers: { "content-type": "application/json" },
    body: JSON.stringify({ jsonrpc: "2.0", id: 1, method: "abci_query", params: { path: "vm/qeval", data: Buffer.from(`${pkg}.${expr}`).toString("base64") } }),
  });
  const base = ((await res.json()) as { result: { response: { ResponseBase: { Error: unknown; Data: string | null; Log: string } } } }).result.response.ResponseBase;
  if (base.Error) throw new Error(`${expr}: ${base.Log}`);
  return Buffer.from(base.Data ?? "", "base64").toString();
}

/** unjson decodes a realm JSON export: `("{\"a\":1}" string)` → object. */
const unjson = (raw: string): unknown => {
  const quoted = /^\((".*") string\)$/s.exec(raw)?.[1];
  if (quoted === undefined) throw new Error(`not a JSON string: ${raw.slice(0, 80)}`);
  return JSON.parse(JSON.parse(quoted) as string);
};


export const rpc = {
  track: async (id: number) => (unjson(await qeval(CATALOG, `TrackJSON(${String(id)})`)) as Track),
  named: async (kind: "Artist" | "Album" | "Playlist", id: number) => (unjson(await qeval(CATALOG, `${kind}JSON(${String(id)})`)) as { name?: string; title?: string; owner?: string }),
  genres: async () => (unjson(await qeval(CATALOG, "GenresJSON()")) as { id: number; name: string }[]),
  stations: async () => (unjson(await qeval(RADIO, "StationsJSON()")) as { stations: Station[] }).stations,
  schedule: async (station: number, horizon = 7200) => (unjson(await qeval(RADIO, `ScheduleJSON(${String(station)}, ${String(horizon)})`)) as Schedule),
  /** tracks pages through TracksJSON (100 ids a page, hidden ones left out) and keeps those matching keep. */
  tracks: async (keep: (t: Track) => boolean) => {
    const out: Track[] = [];
    for (let o = 0, total = 1; o < total; o += 100) {
      const page = unjson(await qeval(CATALOG, `TracksJSON(${String(o)}, 100)`)) as { total: number; tracks: Track[] };
      total = page.total;
      out.push(...page.tracks.filter(keep));
    }
    return out;
  },
};

// ---- Audio: a long silent WAV stands in for every remote track (deterministic, offline) ----

function silentWav(seconds: number): Buffer {
  const rate = 4000;
  const n = rate * seconds;
  const b = Buffer.alloc(44 + n, 0x80); // 8-bit PCM silence is 0x80
  b.write("RIFF", 0); b.writeUInt32LE(36 + n, 4); b.write("WAVEfmt ", 8);
  b.writeUInt32LE(16, 16); b.writeUInt16LE(1, 20); b.writeUInt16LE(1, 22);
  b.writeUInt32LE(rate, 24); b.writeUInt32LE(rate, 28); b.writeUInt16LE(1, 32); b.writeUInt16LE(8, 34);
  b.write("data", 36); b.writeUInt32LE(n, 40);
  return b;
}
const WAV = silentWav(900);

const PIXEL = Buffer.from("iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNkYAAAAAYAAjCB0C8AAAAASUVORK5CYII=", "base64");

/**
 * offline keeps the suite off the internet: remote audio becomes a silent WAV (Range
 * honoured, so seeking works), remote images a pixel, any other remote call a 404.
 */
async function offline(page: Page) {
  await page.route((u) => u.origin !== ORIGIN, async (route) => {
    const type = route.request().resourceType();
    if (type === "image") return route.fulfill({ status: 200, contentType: "image/png", body: PIXEL, headers: { "access-control-allow-origin": "*" } });
    if (type !== "media") return route.fulfill({ status: 404, body: "", headers: { "access-control-allow-origin": "*" } });
    const m = /bytes=(\d+)-(\d*)/.exec(route.request().headers()["range"] ?? "");
    const from = m ? Number(m[1]) : 0;
    const to = m?.[2] ? Math.min(Number(m[2]), WAV.length - 1) : WAV.length - 1;
    await route.fulfill({
      status: m ? 206 : 200,
      headers: {
        "content-type": "audio/wav",
        "accept-ranges": "bytes",
        "access-control-allow-origin": "*",
        ...(m ? { "content-range": `bytes ${String(from)}-${String(to)}/${String(WAV.length)}` } : {}),
      },
      body: WAV.subarray(from, to + 1),
    });
  });
}

// ---- Fixtures ----

interface Fixtures {
  /** errors collects console.error and page errors; the test fails if any remain at the end. */
  errors: string[];
  /** jingles lists the /jingles/*.mp3 URLs requested so far. */
  jingles: string[];
  mobile: boolean;
}

export const test = base.extend<Fixtures>({
  mobile: async ({ isMobile }, use) => { await use(isMobile); },
  jingles: async ({ page }, use) => {
    const seen: string[] = [];
    page.on("request", (r) => { if (/\/jingles\/[^/]+\.mp3/.test(r.url())) seen.push(r.url()); });
    await use(seen);
  },
  errors: [async ({ page }, use) => {
    const errors: string[] = [];
    page.on("console", (m) => {
      if (m.type() !== "error") return;
      // The browser's own line for a remote resource we stubbed out (see offline) is not an app error.
      if (m.text().startsWith("Failed to load resource") && !m.location().url.startsWith(ORIGIN)) return;
      errors.push(`console.error: ${m.text()} @ ${m.location().url}`);
    });
    page.on("pageerror", (e) => { errors.push(`pageerror: ${e.message}`); });
    await offline(page);
    await use(errors);
    expect(errors, "no console.error / uncaught error").toEqual([]);
  }, { auto: true }],
});
export { expect };

// ---- Page helpers ----

/** open loads a path and waits for the app shell (splash gone, main navigation shown). */
export async function open(page: Page, path = "/") {
  await page.goto(path);
  await expect(nav(page)).toBeVisible({ timeout: 30_000 });
  await expect(page.getByText("Community radio · open music · on-chain")).toHaveCount(0); // the splash kicker
}

/** nav is the visible main navigation: the sidebar on desktop, the tab bar on a phone. */
export const nav = (page: Page): Locator => page.getByRole("navigation", { name: "Main" }).filter({ visible: true });

/** player is the Now playing panel, opened from the mini player on a phone. */
export async function player(page: Page, mobile: boolean): Promise<Locator> {
  const p = page.getByRole("region", { name: "Now playing" }).or(page.getByRole("dialog", { name: "Now playing" }));
  if (mobile && !(await p.isVisible())) await page.getByRole("button", { name: "Open player" }).click();
  await expect(p).toBeVisible();
  return p;
}

/** dialTime reads the dial's clock in seconds ("2:05 · of 4:10 · live" → 125). */
export async function dialTime(dial: Locator): Promise<number> {
  const label = (await dial.getAttribute("aria-valuetext")) ?? (await dial.getAttribute("aria-label")) ?? "";
  const m = /^(\d+):(\d\d) · /.exec(label);
  if (!m) throw new Error(`no time in dial label "${label}"`);
  return Number(m[1]) * 60 + Number(m[2]);
}

/** A genre station with tracks (not Main, not New this week), read from the chain. */
export async function genreStation(skip = 0) {
  const stations = (await rpc.stations()).filter((s) => s.genre > 0 && s.tracks > 0);
  const st = stations[skip];
  if (!st) throw new Error("no genre station on the devnet");
  return st;
}

/** openPick tunes to a genre station and opens its Pick next sheet. */
export async function openPick(page: Page, mobile: boolean) {
  const st = await genreStation(1);
  await open(page, `/live/${String(st.id)}`);
  const p = await player(page, mobile);
  await expect(p.getByRole("button", { name: st.name, exact: true })).toBeVisible();
  await p.getByRole("button", { name: `Pick what plays next on ${st.name}` }).click();
  const sheet = page.getByRole("dialog", { name: `Pick what plays next on ${st.name}` });
  await expect(sheet).toBeVisible();
  return { st, sheet };
}

