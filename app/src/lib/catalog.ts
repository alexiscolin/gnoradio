import { CACHE_VERSION, idbStore, readCache, type Snapshot, type Store, writeCache } from "./cache";
import { CHAIN_ID, type Call, DataError, REALMS, RealmError, qjson } from "./gno";
import type { Infer } from "./guard";
import { nameOf } from "./names";
import { mediaURLs, safeHttps, safeMedia } from "./safe";
import { isAlbum, isAlbumPage, isTrack, isArtist, isArtistPage, isEvents, isGenres, isInfo, isPlaylist, isPlaylistPage, isSchedule, isStations, isTrackPage } from "./schemas";
import type { Album, Artist, Catalog, ConcertEvent, Schedule, Track, View } from "./types";

const PAGE = 100;

/**
 * settle keeps the items that loaded. An item the realm refuses (hidden,
 * unknown) or that does not match its schema is skipped, the latter with a
 * warning; a network failure fails the whole load so the catalog is never
 * silently truncated.
 */
export async function settle<T>(jobs: readonly Promise<T>[]): Promise<T[]> {
  const out = await Promise.allSettled(jobs);
  return out.flatMap((r) => {
    if (r.status === "fulfilled") return [r.value];
    if (r.reason instanceof RealmError) return [];
    if (r.reason instanceof DataError) {
      console.warn("GnoRadio: skipped a record that does not match its schema:", r.reason.message);
      return [];
    }
    throw r.reason;
  });
}

// Every URL from the chain is scheme-checked once, here, before any href or src.
const cleanTrack = (t: Track): Track => ({ ...t, audio: safeMedia(t.audio), cover: safeMedia(t.cover), source: safeHttps(t.source) });
const cleanArtist = (a: Infer<typeof isArtist>): Artist => ({ ...a, source: safeHttps(a.source), promo: a.promo ?? 0 });
const cleanAlbum = (a: Album): Album => ({ ...a, cover: safeMedia(a.cover) });
const cleanEvent = (e: ConcertEvent): ConcertEvent => ({ ...e, link: safeHttps(e.link) });

// Artists, albums and playlists come 100 per query (ids offset+1..offset+100).
const BATCH = 100;
const batches = (n: number) => Array.from({ length: Math.ceil(n / BATCH) }, (_, i) => i * BATCH);

/**
 * batched loads ids 1..total 100 at a time. If one record in a batch fails its
 * schema, that batch is re-read item by item so only the bad record is lost.
 */
export function batched<T>(total: number, many: (offset: number) => Promise<T[]>, one: (id: number) => Promise<T>): Promise<T[]> {
  return settle(
    batches(total).map((o) =>
      many(o).catch((e: unknown) => {
        if (!(e instanceof DataError)) throw e;
        console.warn(`GnoRadio: batch ${String(o + 1)}-${String(o + BATCH)} has a bad record, reading it one by one`);
        const ids = Array.from({ length: Math.min(BATCH, total - o) }, (_, i) => o + i + 1);
        // If the first two records fail too, the whole format differs (an older realm): skip the batch
        // rather than send a hundred doomed reads; one odd record alone only loses itself.
        const probe = settle(ids.slice(0, 2).map(one));
        return probe.then((ok) => (ok.length === 0 && ids.length > 1 ? [] : settle([...ok.map((r) => Promise.resolve(r)), ...ids.slice(2).map(one)])));
      }),
    ),
  ).then((pages) => pages.flat());
}

// The newest tracks come first (FIRST_PAGES pages) so the app opens at once;
// the rest of the catalog follows in the background.
const FIRST_PAGES = 2;

const HOUR = 3600_000;
const META_TTL = 6 * HOUR; // artists, albums, playlists are re-read at least this often
const FULL_TTL = 24 * HOUR; // everything is re-read at least this often
/** RECENT: newest track pages re-read on every visit (recent likes, tips, edits, hides). */
const RECENT = 2;

/** cacheKey ties the stored catalog to this chain, these realms and this record format. */
// A new release, chain or realm version starts from a fresh cache.
const cacheKey = (): string => [CHAIN_ID, REALMS.catalog, REALMS.radio, REALMS.tickets, String(CACHE_VERSION), import.meta.env.VITE_BUILD_ID ?? "dev"].join("|");
let browserStore: Store | undefined;

/** Touched is what a transaction can have changed: these tracks and artists, or anything ("all"). */
export type Touched = "all" | { readonly tracks: readonly number[]; readonly artists: readonly number[] };

/** touchedBy maps a signed call to what it can change in the catalog (no call: anything). */
export function touchedBy(c?: Pick<Call, "pkg" | "func" | "args">): Touched {
  if (!c) return "all";
  const id = (i: number) => [Number(c.args[i])].filter((n) => Number.isInteger(n) && n > 0);
  // Stations and events are re-read on every load: radio and tickets calls need nothing more.
  if (c.pkg !== REALMS.catalog) return c.pkg === REALMS.radio && c.func === "TipOnAir" ? { tracks: id(1), artists: [] } : { tracks: [], artists: [] };
  switch (c.func) {
    case "Like": case "Unlike": case "TipWithSupport": case "HideTrack":
      return { tracks: id(0), artists: [] };
    case "Follow": case "Unfollow":
      return { tracks: [], artists: id(0) };
    default:
      return "all";
  }
}

export interface LoadOptions {
  /** early receives, on a visit without a stored catalog, the stations, newest and on-air tracks (no artists yet). */
  readonly early?: ((c: Catalog) => void) | undefined;
  /** cached receives the stored catalog, before any network read. */
  readonly cached?: ((c: Catalog) => void) | undefined;
  /** touched: after a transaction, what to re-read whatever the cache says. */
  readonly touched?: Touched | undefined;
  /** store: where the catalog is kept (IndexedDB by default). */
  readonly store?: Store | undefined;
}

type RawArtist = Infer<typeof isArtist>;

function build(s: Pick<Snapshot, "info" | "radio" | "genres" | "events" | "tracks" | "artists" | "albums" | "playlists">): Catalog {
  const tracks = s.tracks.map(cleanTrack);
  return {
    tracks,
    byId: new Map(tracks.map((t) => [t.id, t])),
    artists: new Map(s.artists.map((a) => [a.id, cleanArtist(a)])),
    albums: s.albums.map(cleanAlbum),
    playlists: s.playlists,
    genres: s.genres,
    stations: s.radio.stations,
    pending: s.radio.pending,
    // radio.Queue: New this week only takes tracks above this id (0 from an older realm: the realm still checks).
    newFloor: s.radio.newFloor ?? 0,
    events: s.events.map(cleanEvent),
    admin: s.info.admin,
  };
}

/** refetch re-reads single records by id: a refused one (hidden, gone) comes back as null. */
const refetch = <T,>(ids: readonly number[], one: (id: number) => Promise<T>): Promise<Map<number, T | null>> =>
  Promise.all(ids.map((id) => one(id).then((v): [number, T | null] => [id, v], (e: unknown): [number, T | null] => {
    if (e instanceof RealmError) return [id, null];
    throw e;
  }))).then((pairs) => new Map(pairs));

/** patch replaces or drops (null) the records of xs that fresh holds. */
const patch = <T extends { readonly id: number }>(xs: readonly T[], fresh: ReadonlyMap<number, T | null>): T[] =>
  xs.flatMap((x) => {
    const f = fresh.get(x.id);
    return f === undefined ? [x] : f === null ? [] : [f];
  });

/**
 * loadCatalog reads everything the app shows, in parallel. A catalog stored by
 * an earlier visit is shown at once (cached), then revalidated: stations,
 * genres, events and Info() every time, only the newest track pages, and
 * artists, albums and playlists only when their counts moved or META_TTL has
 * passed; everything after FULL_TTL. Without a stored catalog, early receives
 * the newest tracks first. Right for a launch catalog of a few thousand tracks;
 * beyond that, an indexer takes over (SPEC §4).
 */
export async function loadCatalog(opts: LoadOptions = {}): Promise<Catalog> {
  const store = opts.store ?? (browserStore ??= idbStore());
  const key = cacheKey();
  const snap = await readCache(store, key);
  if (snap) opts.cached?.(build(snap));
  const now = Date.now();

  const events = qjson(REALMS.tickets, "EventsJSON(0, 20, true)", isEvents).then((r) => r.events).catch((): never[] => []);
  const [info, genres, radio] = await Promise.all([
    qjson(REALMS.catalog, "Info()", isInfo),
    qjson(REALMS.catalog, "GenresJSON()", isGenres),
    qjson(REALMS.radio, "StationsJSON()", isStations),
  ]);
  const touched = opts.touched ?? { tracks: [], artists: [] };
  // A catalog that shrank is another chain (a reset devnet): start over.
  const full = !snap || now - snap.fullAt >= FULL_TTL || info.tracks < snap.info.tracks;
  const counts = (i: typeof info) => [i.artists, i.albums, i.playlists].join();
  const meta = full || touched === "all" || now - snap.metaAt >= META_TTL || counts(info) !== counts(snap.info);

  // Track pages are newest first: page i holds ids n-i*PAGE down to n-(i+1)*PAGE+1. A page with a bad
  // record is re-read track by track, so only that record is lost.
  const page = (i: number) =>
    qjson(REALMS.catalog, `TracksJSON(${String(i * PAGE)}, ${String(PAGE)})`, isTrackPage).then((r) => r.tracks, (e: unknown) => {
      if (!(e instanceof DataError)) throw e;
      const top = info.tracks - i * PAGE;
      const ids = Array.from({ length: Math.min(PAGE, top) }, (_, j) => top - j);
      return settle(ids.map((id) => qjson(REALMS.catalog, `TrackJSON(${String(id)})`, isTrack)));
    });
  const total = Math.ceil(info.tracks / PAGE);
  // Revalidating: the pages holding new ids, plus the RECENT pages before them.
  const count = full ? total : Math.min(total, Math.ceil((info.tracks - snap.info.tracks) / PAGE) + RECENT);
  const pages = Array.from({ length: count }, (_, i) => i);
  const head = pages.slice(0, FIRST_PAGES).map(page);
  if (opts.early && !snap) {
    // The tracks on air on every station, so the radio plays before the rest arrives.
    const newest = (await settle(head)).flat();
    const have = new Set(newest.map((t) => t.id));
    const onAir = [...new Set(radio.stations.map((st) => st.now.track))].filter((id) => id > 0 && !have.has(id));
    const playing = await settle(onAir.map((id) => qjson(REALMS.catalog, `TrackJSON(${String(id)})`, isTrack)));
    opts.early(build({ info, radio, genres, events: [], tracks: [...newest, ...playing], artists: [], albums: [], playlists: [] }));
  }
  const oneTrack = (id: number) => qjson(REALMS.catalog, `TrackJSON(${String(id)})`, isTrack);
  const oneArtist = (id: number) => qjson(REALMS.catalog, `ArtistJSON(${String(id)})`, isArtist);
  const [trackPages, artists, albums, playlists, evs, tracksNow] = await Promise.all([
    settle([...head, ...pages.slice(FIRST_PAGES).map(page)]),
    meta ? batched(info.artists, (o) => qjson(REALMS.catalog, `ArtistsJSON(${String(o)}, ${String(BATCH)})`, isArtistPage).then((r) => r.artists), oneArtist) : snap.artists,
    meta ? batched(info.albums, (o) => qjson(REALMS.catalog, `AlbumsJSON(${String(o)}, ${String(BATCH)})`, isAlbumPage).then((r) => r.albums),
      (id) => qjson(REALMS.catalog, `AlbumJSON(${String(id)})`, isAlbum)) : snap.albums,
    meta ? batched(info.playlists, (o) => qjson(REALMS.catalog, `PlaylistsJSON(${String(o)}, ${String(BATCH)})`, isPlaylistPage).then((r) => r.playlists),
      (id) => qjson(REALMS.catalog, `PlaylistJSON(${String(id)})`, isPlaylist)) : snap.playlists,
    events,
    touched === "all" || full ? new Map<number, Track | null>() : refetch(touched.tracks, oneTrack),
  ]);

  let tracks = trackPages.flat();
  let fresh: RawArtist[] = artists;
  if (!full) {
    // Ids at or above lo were just re-read: a cached one missing there is hidden now.
    const lo = info.tracks - count * PAGE + 1;
    const kept = patch([...tracks, ...snap.tracks.filter((t) => t.id < lo)], tracksNow);
    // A track restored by the moderator comes back; newest first, as the realm pages them.
    const have = new Set(kept.map((t) => t.id));
    tracks = [...kept, ...[...tracksNow.values()].filter((t): t is Track => t !== null && !have.has(t.id))].sort((a, b) => b.id - a.id);
    if (touched !== "all") {
      // A like or a tip also moves the artist's counts.
      const who = [...touched.artists, ...[...tracksNow.values()].flatMap((t) => (t ? [t.artist] : []))];
      if (!meta) fresh = patch(artists, await refetch([...new Set(who)], oneArtist));
    }
    // An artist hidden since takes its tracks along, as in the realm's own pages.
    if (meta) {
      const shown = new Set(fresh.map((a) => a.id));
      tracks = tracks.filter((t) => shown.has(t.artist));
    }
  }
  const next: Snapshot = {
    key, fullAt: full ? now : snap.fullAt, metaAt: meta ? now : snap.metaAt,
    info, radio, genres, events: evs, tracks, artists: fresh, albums, playlists,
  };
  void writeCache(store, next);
  return build(next);
}

/** loadSchedule reads a station's next horizon seconds (the realm serves up to 7200 and 60 entries). */
export const loadSchedule = (station: number, horizon = 3600): Promise<Schedule> =>
  qjson(REALMS.radio, `ScheduleJSON(${String(station)}, ${String(horizon)})`, isSchedule);

/** audioURLs resolves an on-chain audio reference to URLs an <audio> element plays, best first. */
export const audioURLs = (t: Pick<Track, "audio">): string[] => mediaURLs(t.audio);

/** How a track list is ordered: a daily mix, or by likes, tips or age. */
export type TrackOrder = "mix" | "liked" | "tipped" | "new";

/** mixKey scatters ids in a fresh order each day (integer hash of id and day): no track sits on top for good. */
const mixKey = (id: number, day: number): number => {
  let h = Math.imul(id ^ Math.imul(day, 0x9e3779b1), 0x85ebca6b);
  h ^= h >>> 13;
  h = Math.imul(h, 0xc2b2ae35);
  return (h ^ (h >>> 16)) >>> 0;
};

/** sortTracks orders tracks; ties (same likes, same tips) fall back to the day's mix, so they rotate too. */
export function sortTracks(tracks: readonly Track[], order: TrackOrder, day = Math.floor(Date.now() / 86_400_000)): Track[] {
  const by = { mix: () => 0, liked: (t: Track) => -t.likes, tipped: (t: Track) => -t.tips, new: (t: Track) => -t.created }[order];
  return [...tracks].sort((a, b) => by(a) - by(b) || mixKey(a.id, day) - mixKey(b.id, day));
}

/** tracksOf resolves ids to tracks, dropping unknown or hidden ones. */
export const tracksOf = (cat: Catalog, ids: readonly number[]): Track[] =>
  ids.flatMap((id) => {
    const t = cat.byId.get(id);
    return t ? [t] : [];
  });

/** viewName is the label a screen's URL carries (artist name, track title…), "" when unknown. */
export function viewName(cat: Catalog | null, v: View): string {
  if (v.k === "listener") return nameOf(v.address); // the gno.land name, once loaded
  if (!cat) return "";
  switch (v.k) {
    case "artist":
      return cat.artists.get(v.id)?.name ?? "";
    case "track":
      return cat.byId.get(v.id)?.title ?? "";
    case "album":
      return cat.albums.find((a) => a.id === v.id)?.title ?? "";
    case "playlist":
      return cat.playlists.find((p) => p.id === v.id)?.title ?? "";
    case "library":
      return cat.genres.find((g) => g.id === v.genre)?.name ?? "";
    case "stations":
      return cat.stations.find((s) => s.id === v.live)?.name ?? "";
    default:
      return "";
  }
}
