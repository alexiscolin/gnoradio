import { describe, expect, it } from "vitest";
import { albumGenre, albumsIn } from "./albums";

const byId = new Map([[1, { genre: 3 }], [2, { genre: 3 }], [3, { genre: 9 }], [4, { genre: 9 }], [5, { genre: 14 }]]);

describe("albums by genre", () => {
  it("puts an album in the genre most of its tracks have, even without a majority", () => {
    expect(albumGenre({ tracks: [1, 2, 3] }, byId)).toBe(3);
    expect(albumGenre({ tracks: [1, 3, 5] }, byId)).toBe(3); // a three-way tie: the lowest id
    expect(albumGenre({ tracks: [3, 4, 1, 5] }, byId)).toBe(9);
    expect(albumGenre({ tracks: [99] }, byId)).toBe(0);
  });
  it("lists a genre's albums newest first, and every album for genre 0", () => {
    const albums = [{ id: 1, year: 2010, tracks: [1, 2] }, { id: 2, year: 2015, tracks: [3, 4] }, { id: 3, year: 2015, tracks: [1, 5, 2] }];
    expect(albumsIn(albums, byId, 3).map((a) => a.id)).toEqual([3, 1]);
    expect(albumsIn(albums, byId, 9).map((a) => a.id)).toEqual([2]);
    expect(albumsIn(albums, byId, 0).map((a) => a.id)).toEqual([3, 2, 1]);
  });
});
