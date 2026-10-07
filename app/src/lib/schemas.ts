import { arr, bool, type Infer, num, obj, oneOf, opt, str } from "./guard";

// The domain types are derived from these guards (bottom of file): one source of truth.
const origin = oneOf("artist", "curated", "audius");

export const isTrack = obj({
  id: num, artist: num, artistName: str, claimed: bool, origin, title: str, genre: num, duration: num, license: str, cmo: str,
  credits: str, audio: str, audioSha256: str, cover: str, coverSha256: str, source: str, attribution: str, album: num,
  created: num, likes: num, tips: num, supporters: num, splits: arr(obj({ to: str, pct: num })),
});
export const isArtist = obj({
  id: num, name: str, kind: origin, owner: str, bio: str, source: str, joined: num, tips: num, followers: num, verified: bool,
  tracks: arr(num), albums: arr(num),
});
export const isAlbum = obj({ id: num, artist: num, title: str, cover: str, year: num, tracks: arr(num) });
export const isPlaylist = obj({ id: num, owner: str, title: str, updated: num, tracks: arr(num) });
export const isGenres = arr(obj({ id: num, name: str }));
export const isInfo = obj({ version: str, admin: str, artists: num, tracks: num, albums: num, playlists: num });
export const isArtistPage = obj({ artists: arr(isArtist) });
export const isAlbumPage = obj({ albums: arr(isAlbum) });
export const isPlaylistPage = obj({ playlists: arr(isPlaylist) });
export const isTrackPage = obj({ tracks: arr(isTrack) });
export const isStations = obj({
  pending: num,
  stations: arr(obj({ id: num, name: str, genre: num, tracks: num, loop: num, queued: num, now: obj({ track: num, offset: num, queued: bool }) })),
});
const isEntry = obj({ track: num, title: str, start: num, end: num, offset: num, queued: bool, by: str, note: opt(str) });
export const isSchedule = obj({ station: num, now: num, entries: arr(isEntry) });
export const isEvents = obj({
  events: arr(obj({ id: num, artist: num, title: str, venue: str, link: str, start: num, price: num, capacity: num, sold: num, cancelled: bool, fee: opt(num) })),
});
export const isActivities = arr(
  obj({
    kind: oneOf("publish", "like", "follow", "tip", "support", "playlist", "album", "claim", "queue", "curator"),
    by: str, track: num, artist: opt(num), station: opt(num), amount: opt(num), at: num,
  }),
);
export const isSupport = obj({
  treasury: str, total: num, supporters: num, month: str, monthTotal: num, goal: num, top: arr(obj({ address: str, amount: num })),
});
export const isFees = obj({ serviceFee: num, treasury: str });
export const isUser = obj({ address: str, likes: num, follows: num, tipped: num, playlists: arr(num), artist: num });
export const isTickets = arr(
  obj({ id: num, event: num, serial: num, attended: bool }),
);

export type Origin = Infer<typeof origin>;
export type Track = Infer<typeof isTrack>;
export type Split = Track["splits"][number];
export type Artist = Infer<typeof isArtist>;
export type Album = Infer<typeof isAlbum>;
export type Playlist = Infer<typeof isPlaylist>;
export type Genre = Infer<typeof isGenres>[number];
export type CatalogInfo = Infer<typeof isInfo>;
export type Station = Infer<typeof isStations>["stations"][number];
export type ScheduleEntry = Infer<typeof isEntry>;
export type Schedule = Infer<typeof isSchedule>;
export type ConcertEvent = Infer<typeof isEvents>["events"][number];
export type Activity = Infer<typeof isActivities>[number];
export type SupportInfo = Infer<typeof isSupport>;
export type Fees = Infer<typeof isFees>;
export type UserInfo = Infer<typeof isUser>;
export type OwnedTicket = Infer<typeof isTickets>[number];
