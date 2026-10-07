import { DataError, REALMS, RealmError, qjson } from "./gno";
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
const cleanArtist = (a: Artist): Artist => ({ ...a, source: safeHttps(a.source) });
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
        return settle(ids.map(one));
      }),
    ),
  ).then((pages) => pages.flat());
}

/**
 * loadCatalog reads everything the app shows, in parallel. Right for a launch
 * catalog of a few thousand tracks; beyond that, an indexer takes over (SPEC §4).
 */
export async function loadCatalog(): Promise<Catalog> {
  const [info, genres, radio] = await Promise.all([
    qjson(REALMS.catalog, "Info()", isInfo),
    qjson(REALMS.catalog, "GenresJSON()", isGenres),
    qjson(REALMS.radio, "StationsJSON()", isStations),
  ]);
  // Track pages are newest first: page i holds ids n-i*PAGE down to n-(i+1)*PAGE+1. A page with a bad
  // record is re-read track by track, so only that record is lost.
  const pages = Array.from({ length: Math.ceil(info.tracks / PAGE) }, (_, i) =>
    qjson(REALMS.catalog, `TracksJSON(${String(i * PAGE)}, ${String(PAGE)})`, isTrackPage).then((r) => r.tracks, (e: unknown) => {
      if (!(e instanceof DataError)) throw e;
      const top = info.tracks - i * PAGE;
      const ids = Array.from({ length: Math.min(PAGE, top) }, (_, j) => top - j);
      return settle(ids.map((id) => qjson(REALMS.catalog, `TrackJSON(${String(id)})`, isTrack)));
    }),
  );
  const [trackPages, artists, albums, playlists, events] = await Promise.all([
    settle(pages),
    batched(info.artists, (o) => qjson(REALMS.catalog, `ArtistsJSON(${String(o)}, ${String(BATCH)})`, isArtistPage).then((r) => r.artists),
      (id) => qjson(REALMS.catalog, `ArtistJSON(${String(id)})`, isArtist)),
    batched(info.albums, (o) => qjson(REALMS.catalog, `AlbumsJSON(${String(o)}, ${String(BATCH)})`, isAlbumPage).then((r) => r.albums),
      (id) => qjson(REALMS.catalog, `AlbumJSON(${String(id)})`, isAlbum)),
    batched(info.playlists, (o) => qjson(REALMS.catalog, `PlaylistsJSON(${String(o)}, ${String(BATCH)})`, isPlaylistPage).then((r) => r.playlists),
      (id) => qjson(REALMS.catalog, `PlaylistJSON(${String(id)})`, isPlaylist)),
    qjson(REALMS.tickets, "EventsJSON(0, 20, true)", isEvents).then((r) => r.events).catch((): never[] => []),
  ]);
  const tracks = trackPages.flat().map(cleanTrack);
  return {
    tracks,
    byId: new Map(tracks.map((t) => [t.id, t])),
    artists: new Map(artists.map((a) => [a.id, cleanArtist(a)])),
    albums: albums.map(cleanAlbum),
    playlists,
    genres,
    stations: radio.stations,
    pending: radio.pending,
    events: events.map(cleanEvent),
    admin: info.admin,
  };
}

export const loadSchedule = (station: number): Promise<Schedule> => qjson(REALMS.radio, `ScheduleJSON(${String(station)}, 3600)`, isSchedule);

/** audioURLs resolves an on-chain audio reference to URLs an <audio> element plays, best first. */
export const audioURLs = (t: Pick<Track, "audio">): string[] => mediaURLs(t.audio);

/** tracksOf resolves ids to tracks, dropping unknown or hidden ones. */
export const tracksOf = (cat: Catalog, ids: readonly number[]): Track[] =>
  ids.flatMap((id) => {
    const t = cat.byId.get(id);
    return t ? [t] : [];
  });

/** viewName is the label a screen's URL carries (artist name, track title…), "" when unknown. */
export function viewName(cat: Catalog | null, v: View): string {
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
