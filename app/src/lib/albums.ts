import type { Album, Track } from "./types";

/** albumGenre is the genre most of an album's tracks have (the lowest id on a tie; 0 with no known track). */
export function albumGenre(al: Pick<Album, "tracks">, byId: ReadonlyMap<number, Pick<Track, "genre">>): number {
  const n = new Map<number, number>();
  for (const id of al.tracks) {
    const g = byId.get(id)?.genre;
    if (g) n.set(g, (n.get(g) ?? 0) + 1);
  }
  let best = 0, most = 0;
  for (const [g, c] of n) if (c > most || (c === most && g < best)) [best, most] = [g, c];
  return best;
}

/** albumsIn lists a genre's albums (every album for genre 0), newest first. */
export function albumsIn<A extends Pick<Album, "id" | "year" | "tracks">>(albums: readonly A[], byId: ReadonlyMap<number, Pick<Track, "genre">>, genre: number): A[] {
  return albums.filter((al) => !genre || albumGenre(al, byId) === genre).sort((a, b) => b.year - a.year || b.id - a.id);
}
