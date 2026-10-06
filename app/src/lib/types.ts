// Domain types, mirroring the JSON exports of the GnoRadio realms.

export type Origin = "artist" | "curated" | "audius";

export interface Split {
  readonly to: string;
  readonly pct: number;
}

export interface Track {
  readonly id: number;
  readonly artist: number;
  readonly artistName: string;
  readonly claimed: boolean;
  readonly origin: Origin;
  readonly title: string;
  readonly genre: number;
  readonly duration: number;
  readonly license: string;
  readonly cmo: string;
  readonly credits: string;
  readonly audio: string;
  readonly audioSha256: string;
  readonly cover: string;
  readonly coverSha256: string;
  readonly source: string;
  readonly attribution: string;
  readonly album: number;
  readonly created: number;
  readonly likes: number;
  readonly tips: number;
  readonly supporters: number;
  readonly splits: readonly Split[];
}

export interface Artist {
  readonly id: number;
  readonly name: string;
  readonly kind: Origin;
  readonly owner: string;
  readonly bio: string;
  readonly source: string;
  readonly joined: number;
  readonly tips: number;
  readonly followers: number;
  readonly verified: boolean;
  readonly tracks: readonly number[];
  readonly albums: readonly number[];
}

export interface Album {
  readonly id: number;
  readonly artist: number;
  readonly title: string;
  readonly cover: string;
  readonly year: number;
  readonly tracks: readonly number[];
}

export interface Playlist {
  readonly id: number;
  readonly owner: string;
  readonly title: string;
  readonly updated: number;
  readonly tracks: readonly number[];
}

export interface Genre {
  readonly id: number;
  readonly name: string;
}

export interface Station {
  readonly id: number;
  readonly name: string;
  readonly genre: number;
  readonly tracks: number;
  readonly loop: number;
  readonly queued: number;
  readonly now: { readonly track: number; readonly offset: number; readonly queued: boolean };
}

export interface ScheduleEntry {
  readonly track: number;
  readonly title: string;
  readonly start: number;
  readonly end: number;
  readonly offset: number;
  readonly queued: boolean;
  readonly by: string;
}

export interface Schedule {
  readonly station: number;
  readonly now: number;
  readonly entries: readonly ScheduleEntry[];
}

export interface ConcertEvent {
  readonly id: number;
  readonly artist: number;
  readonly title: string;
  readonly venue: string;
  readonly link: string;
  readonly start: number;
  readonly price: number;
  readonly capacity: number;
  readonly sold: number;
  readonly cancelled: boolean;
  readonly fee?: number | undefined;
}

export interface CatalogInfo {
  readonly version: string;
  readonly admin: string;
  readonly artists: number;
  readonly tracks: number;
  readonly albums: number;
  readonly playlists: number;
}

/** Everything the app renders, loaded once and refreshed after writes. */
export interface Catalog {
  readonly tracks: readonly Track[];
  readonly byId: ReadonlyMap<number, Track>;
  readonly artists: ReadonlyMap<number, Artist>;
  readonly albums: readonly Album[];
  readonly playlists: readonly Playlist[];
  readonly genres: readonly Genre[];
  readonly stations: readonly Station[];
  readonly events: readonly ConcertEvent[];
  readonly admin: string;
}

/** One line of the on-chain activity feed (catalog and radio merged). */
export interface Activity {
  readonly kind: "publish" | "like" | "follow" | "tip" | "support" | "playlist" | "album" | "claim" | "queue" | "curator";
  readonly by: string;
  readonly track: number;
  readonly artist?: number | undefined;
  readonly station?: number | undefined;
  readonly amount?: number | undefined;
  readonly at: number;
}

export interface SupportInfo {
  readonly treasury: string;
  readonly total: number;
  readonly supporters: number;
  readonly month: string;
  readonly monthTotal: number;
  readonly goal: number;
  readonly top: readonly { readonly address: string; readonly amount: number }[];
}

export interface Fees {
  readonly serviceFee: number;
  readonly treasury: string;
}

export interface UserInfo {
  readonly address: string;
  readonly likes: number;
  readonly follows: number;
  readonly tipped: number;
  readonly playlists: readonly number[];
  readonly artist: number;
}

/** The app's screens, as a discriminated union. */
export type View =
  | { readonly k: "listen" }
  | { readonly k: "stations" }
  | { readonly k: "library"; readonly genre: number }
  | { readonly k: "search" }
  | { readonly k: "saved" }
  | { readonly k: "concerts" }
  | { readonly k: "community" }
  | { readonly k: "me" }
  | { readonly k: "studio" }
  | { readonly k: "track"; readonly id: number }
  | { readonly k: "artist"; readonly id: number }
  | { readonly k: "album"; readonly id: number }
  | { readonly k: "playlist"; readonly id: number };

export type Navigate = (v: View) => void;
