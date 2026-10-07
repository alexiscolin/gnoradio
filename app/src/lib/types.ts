// Domain types: the chain data types are derived from the runtime guards in
// schemas.ts; only app-side types are declared here.
import type { Album, Artist, ConcertEvent, Genre, Playlist, Station, Track } from "./schemas";

export type {
  Activity, Album, Artist, CatalogInfo, ConcertEvent, Fees, Genre, Origin, OwnedTicket, Playlist, Schedule, ScheduleEntry, Split,
  Station, SupportInfo, Track, UserInfo,
} from "./schemas";

/** Everything the app renders, loaded once and refreshed after writes. */
export interface Catalog {
  readonly tracks: readonly Track[];
  readonly byId: ReadonlyMap<number, Track>;
  readonly artists: ReadonlyMap<number, Artist>;
  readonly albums: readonly Album[];
  readonly playlists: readonly Playlist[];
  readonly genres: readonly Genre[];
  readonly stations: readonly Station[];
  /** pending counts catalog tracks not yet synced into the stations. */
  readonly pending: number;
  readonly events: readonly ConcertEvent[];
  readonly admin: string;
}

/** The app's screens, as a discriminated union. */
export type View =
  | { readonly k: "listen" }
  | { readonly k: "stations"; readonly live?: number }
  | { readonly k: "library"; readonly genre: number }
  | { readonly k: "concerts" }
  | { readonly k: "community" }
  | { readonly k: "me" }
  | { readonly k: "studio" }
  | { readonly k: "contribute"; readonly path?: ContribPath }
  | { readonly k: "about" }
  | { readonly k: "track"; readonly id: number }
  | { readonly k: "artist"; readonly id: number }
  | { readonly k: "album"; readonly id: number }
  | { readonly k: "playlist"; readonly id: number };

/** The four ways to contribute, each with its own URL (/contribute/artist…). */
export type ContribPath = "listener" | "artist" | "claim" | "report";

export type Navigate = (v: View) => void;
