import { arr, bool, type Guard, num, obj, oneOf, opt, str } from "./guard";
import type {
  Activity, Album, Artist, CatalogInfo, ConcertEvent, Fees, Genre, Playlist, Schedule, ScheduleEntry, Station, SupportInfo, Track, UserInfo,
} from "./types";

// Each guard is checked against its interface at compile time (Guard<T>).
const origin = oneOf("artist", "curated", "audius");

export const isTrack: Guard<Track> = obj({
  id: num, artist: num, artistName: str, claimed: bool, origin, title: str, genre: num, duration: num, license: str, cmo: str,
  credits: str, audio: str, audioSha256: str, cover: str, coverSha256: str, source: str, attribution: str, album: num,
  created: num, likes: num, tips: num, supporters: num, splits: arr(obj({ to: str, pct: num })),
});
export const isArtist: Guard<Artist> = obj({
  id: num, name: str, kind: origin, owner: str, bio: str, source: str, joined: num, tips: num, followers: num, verified: bool,
  tracks: arr(num), albums: arr(num),
});
export const isAlbum: Guard<Album> = obj({ id: num, artist: num, title: str, cover: str, year: num, tracks: arr(num) });
export const isPlaylist: Guard<Playlist> = obj({ id: num, owner: str, title: str, updated: num, tracks: arr(num) });
export const isGenres: Guard<Genre[]> = arr(obj({ id: num, name: str }));
export const isInfo: Guard<CatalogInfo> = obj({ version: str, admin: str, artists: num, tracks: num, albums: num, playlists: num });
export const isTrackPage: Guard<{ tracks: Track[] }> = obj({ tracks: arr(isTrack) });
export const isStations: Guard<{ stations: Station[] }> = obj({
  stations: arr(obj({ id: num, name: str, genre: num, tracks: num, loop: num, queued: num, now: obj({ track: num, offset: num, queued: bool }) })),
});
const isEntry: Guard<ScheduleEntry> = obj({ track: num, title: str, start: num, end: num, offset: num, queued: bool, by: str });
export const isSchedule: Guard<Schedule> = obj({ station: num, now: num, entries: arr(isEntry) });
export const isEvents: Guard<{ events: ConcertEvent[] }> = obj({
  events: arr(obj({ id: num, artist: num, title: str, venue: str, link: str, start: num, price: num, capacity: num, sold: num, cancelled: bool, fee: opt(num) })),
});
export const isActivities: Guard<Activity[]> = arr(
  obj({
    kind: oneOf("publish", "like", "follow", "tip", "support", "playlist", "album", "claim", "queue", "curator"),
    by: str, track: num, artist: opt(num), station: opt(num), amount: opt(num), at: num,
  }),
);
export const isSupport: Guard<SupportInfo> = obj({
  treasury: str, total: num, supporters: num, month: str, monthTotal: num, goal: num, top: arr(obj({ address: str, amount: num })),
});
export const isFees: Guard<Fees> = obj({ serviceFee: num, treasury: str });
export const isUser: Guard<UserInfo> = obj({ address: str, likes: num, follows: num, tipped: num, playlists: arr(num), artist: num });
export const isTickets: Guard<{ id: number; event: number; serial: number; attended: boolean }[]> = arr(
  obj({ id: num, event: num, serial: num, attended: bool }),
);
