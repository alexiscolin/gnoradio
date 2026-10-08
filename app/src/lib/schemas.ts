import { arr, bool, type Infer, num, obj, oneOf, opt, str } from "./guard";

// The domain types are derived from these guards (bottom of file): one source of truth.
const origin = oneOf("artist", "curated", "audius", "jamendo");

export const isTrack = obj({
  id: num, artist: num, artistName: str, claimed: bool, origin, title: str, genre: num, duration: num, license: str, cmo: str,
  credits: str, audio: str, audioSha256: str, cover: str, coverSha256: str, source: str, attribution: str, album: num,
  created: num, likes: num, tips: num, supporters: num, splits: arr(obj({ to: str, pct: num })),
});
export const isArtist = obj({
  id: num, name: str, kind: origin, owner: str, bio: str, source: str, joined: num, tips: num, followers: num, verified: bool,
  // Fields added after v0 are optional on the wire, so an app newer than the realm still reads it.
  promo: opt(num), sponsor: opt(num),
  proofHost: opt(str), // where a verified artist's proof was found (catalog.ProofHost), "" when none
  tracks: arr(num), albums: arr(num),
});
export const isAlbum = obj({ id: num, artist: num, title: str, cover: str, year: num, tracks: arr(num) });
export const isPlaylist = obj({ id: num, owner: str, title: str, updated: num, tracks: arr(num) });
export const isGenres = arr(obj({ id: num, name: str }));
export const isInfo = obj({ version: str, admin: str, artists: num, tracks: num, albums: num, playlists: num });
export const isArtistPage = obj({ artists: arr(isArtist) });
export const isAlbumPage = obj({ albums: arr(isAlbum) });
export const isPlaylistPage = obj({ playlists: arr(isPlaylist) });
export const isTrackPage = obj({ total: opt(num), tracks: arr(isTrack) }); // total: the realm's count when the page was read
export const isStations = obj({
  pending: num,
  newFloor: opt(num), // radio: only tracks above this id may be picked on New this week
  stations: arr(obj({ id: num, name: str, genre: num, tracks: num, loop: num, queued: num, now: obj({ track: num, offset: num, queued: bool }) })),
});
const isEntry = obj({ track: num, title: str, start: num, end: num, offset: num, queued: bool, by: str, note: opt(str), sponsored: opt(num), at: opt(num), relay: opt(bool) });
const isBooked = obj({ track: num, start: num, end: num, at: num, by: str });
export const isSchedule = obj({ station: num, now: num, entries: arr(isEntry), booked: opt(arr(isBooked)) });
export const isEvent = obj({ id: num, artist: num, title: str, venue: str, link: str, start: num, price: num, capacity: num, sold: num, cancelled: bool, fee: opt(num) });
export const isEvents = obj({ events: arr(isEvent), next: opt(num) });
export const isActivities = arr(
  obj({
    kind: oneOf("publish", "like", "follow", "tip", "support", "playlist", "album", "claim", "queue", "curator", "sponsored"),
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

export type Track = Infer<typeof isTrack>;
export type Artist = Omit<Infer<typeof isArtist>, "promo"> & { readonly promo: number };
export type Album = Infer<typeof isAlbum>;
export type Playlist = Infer<typeof isPlaylist>;
export type Genre = Infer<typeof isGenres>[number];
export type Station = Infer<typeof isStations>["stations"][number];
/** relay: on Main, an entry that is not Main's own slot (the hour's genre station, its picks included), simulcast. */
export type ScheduleEntry = Omit<Infer<typeof isEntry>, "sponsored" | "at" | "relay"> & { readonly sponsored?: number | undefined; readonly at?: number | undefined; readonly relay?: boolean | undefined };
/** A pick booked for a time (radio.QueueAt): "at" is the time asked, "start" the track boundary it airs at. */
export type Booked = Infer<typeof isBooked>;
// "sponsored" (v0.7), "at" and "booked" (v0.8) are optional: fixtures and older realms omit them.
export type Schedule = Omit<Infer<typeof isSchedule>, "entries" | "booked"> & { readonly entries: ScheduleEntry[]; readonly booked?: readonly Booked[] | undefined };
export type ConcertEvent = Infer<typeof isEvent>;
export type Activity = Infer<typeof isActivities>[number];
export type SupportInfo = Infer<typeof isSupport>;
export type UserInfo = Infer<typeof isUser>;
export type OwnedTicket = Infer<typeof isTickets>[number];
