import { REALMS, RealmError, qjson } from "./gno";
import { isAlbum, isArtist, isEvents, isGenres, isInfo, isPlaylist, isSchedule, isStations, isTrackPage } from "./schemas";
import type { Catalog, Schedule, Track } from "./types";

const PAGE = 50;

/**
 * settle keeps the items that loaded; an item the realm refuses (hidden,
 * unknown) is skipped, but a network failure fails the whole load so the
 * catalog is never silently truncated.
 */
async function settle<T>(jobs: readonly Promise<T>[]): Promise<T[]> {
  const out = await Promise.allSettled(jobs);
  return out.flatMap((r) => {
    if (r.status === "fulfilled") return [r.value];
    if (r.reason instanceof RealmError) return [];
    throw r.reason;
  });
}

const range = (n: number) => Array.from({ length: n }, (_, i) => i + 1);

/**
 * loadCatalog reads everything the app shows, in parallel. Right for a launch
 * catalog of a few thousand tracks; beyond that, an indexer takes over (SPEC §4).
 */
export async function loadCatalog(): Promise<Catalog> {
  const [info, genres, stations] = await Promise.all([
    qjson(REALMS.catalog, "Info()", isInfo),
    qjson(REALMS.catalog, "GenresJSON()", isGenres),
    qjson(REALMS.radio, "StationsJSON()", isStations).then((r) => r.stations),
  ]);
  const pages = Array.from({ length: Math.ceil(info.tracks / PAGE) }, (_, i) =>
    qjson(REALMS.catalog, `TracksJSON(${String(i * PAGE)}, ${String(PAGE)})`, isTrackPage).then((r) => r.tracks),
  );
  const [trackPages, artists, albums, playlists, events] = await Promise.all([
    settle(pages),
    settle(range(info.artists).map((i) => qjson(REALMS.catalog, `ArtistJSON(${String(i)})`, isArtist))),
    settle(range(info.albums).map((i) => qjson(REALMS.catalog, `AlbumJSON(${String(i)})`, isAlbum))),
    settle(range(info.playlists).map((i) => qjson(REALMS.catalog, `PlaylistJSON(${String(i)})`, isPlaylist))),
    qjson(REALMS.tickets, "EventsJSON(0, 20, true)", isEvents).then((r) => r.events).catch((): never[] => []),
  ]);
  const tracks = trackPages.flat();
  return {
    tracks,
    byId: new Map(tracks.map((t) => [t.id, t])),
    artists: new Map(artists.map((a) => [a.id, a])),
    albums,
    playlists,
    genres,
    stations,
    events,
    admin: info.admin,
  };
}

export const loadSchedule = (station: number): Promise<Schedule> => qjson(REALMS.radio, `ScheduleJSON(${String(station)}, 3600)`, isSchedule);

/** audioURL resolves an on-chain audio reference to something an <audio> element plays. */
export function audioURL(t: Pick<Track, "audio">): string {
  const { audio } = t;
  if (audio.startsWith("ipfs://")) return `https://ipfs.io/ipfs/${audio.slice(7)}`;
  if (audio.startsWith("ar://")) return `https://arweave.net/${audio.slice(5)}`;
  if (audio.startsWith("audius:")) return `https://api.audius.co/v1/tracks/${audio.slice(7)}/stream?app_name=GnoRadio`;
  return audio;
}

/** tracksOf resolves ids to tracks, dropping unknown or hidden ones. */
export const tracksOf = (cat: Catalog, ids: readonly number[]): Track[] =>
  ids.flatMap((id) => {
    const t = cat.byId.get(id);
    return t ? [t] : [];
  });
