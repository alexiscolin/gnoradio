package catalog

import (
	"strconv"
	"strings"

	"gno.land/p/gnoradio/store/v0"
	"gno.land/p/gnoradio/text/v0"
)

// JSON exports for the GnoRadio app and indexers (vm/qeval).

func Info() string {
	return `{"version":` + text.Str(version) + `,"artists":` + itoa(nArtists) + `,"tracks":` + itoa(nTracks) +
		`,"albums":` + itoa(nAlbums) + `,"playlists":` + itoa(nPlaylists) + `,"listeners":` + itoa(users.Len()) +
		`,"genres":` + itoa(NumGenres) + `,"now":` + itoa64(now()) + `,"frozen":` + strconv.FormatBool(frozen) +
		`,"successor":` + text.Str(successor) + `,"admin":` + text.Str(admin.String()) + `}`
}

func ints(xs []int) string {
	var b strings.Builder
	b.WriteString("[")
	for i, x := range xs {
		if i > 0 {
			b.WriteString(",")
		}
		b.WriteString(itoa(x))
	}
	b.WriteString("]")
	return b.String()
}

func trackJSON(t *Track) string { return trackJSONWith(t, getArtist(t.Artist)) }

func trackJSONWith(t *Track, a *Artist) string {
	var b strings.Builder
	b.WriteString(`{"id":` + itoa(t.ID) + `,"artist":` + itoa(t.Artist) + `,"artistName":` + text.Str(a.Name) +
		`,"claimed":` + strconv.FormatBool(a.Owner != "") + `,"origin":` + text.Str(t.Origin) + `,"title":` + text.Str(t.Title) +
		`,"genre":` + itoa(t.Genre) + `,"duration":` + itoa64(t.Duration) + `,"license":` + text.Str(t.License) +
		`,"cmo":` + text.Str(t.CMO) + `,"credits":` + text.Str(t.Credits) + `,"audio":` + text.Str(t.Audio) + `,"audioSha256":` + text.Str(t.AudioSHA) +
		`,"cover":` + text.Str(t.Cover) + `,"coverSha256":` + text.Str(t.CoverSHA) + `,"source":` + text.Str(t.SourceURL) +
		`,"attribution":` + text.Str(t.Attribution) + `,"album":` + itoa(t.Album) + `,"created":` + itoa64(t.Created) +
		`,"likes":` + itoa(t.Likes) + `,"tips":` + itoa64(t.Tips) + `,"supporters":` + itoa(t.Supporters) + `,"splits":[`)
	for i, s := range t.Splits {
		if i > 0 {
			b.WriteString(",")
		}
		b.WriteString(`{"to":` + text.Str(s.To.String()) + `,"pct":` + itoa64(s.Pct) + `}`)
	}
	b.WriteString(`]}`)
	return b.String()
}

// TrackJSON returns one playable track.
func TrackJSON(id int) string { return trackJSON(mustTrack(id)) }

// TracksJSON pages through playable tracks (newest first), at most 100.
func TracksJSON(offset, limit int) string {
	if limit < 1 || limit > maxBatch {
		limit = maxBatch
	}
	var b strings.Builder
	b.WriteString(`{"total":` + itoa(nTracks) + `,"tracks":[`)
	n := 0
	heads := map[int]*Artist{} // an artist is decoded once per page
	for _, id := range TrackPage(offset, limit, true) {
		t := getTrack(id)
		if t == nil || t.Hidden {
			continue
		}
		a, ok := heads[t.Artist]
		if !ok {
			a = getArtist(t.Artist)
			heads[t.Artist] = a
		}
		if !visibleArtist(a) {
			continue
		}
		if n > 0 {
			b.WriteString(",")
		}
		b.WriteString(trackJSONWith(t, a))
		n++
	}
	b.WriteString(`]}`)
	return b.String()
}

func ArtistJSON(id int) string { return artistJSON(mustArtist(id)) }

func artistJSON(a *Artist) string {
	trackIDs, albumIDs := lists(a.ID)
	return `{"id":` + itoa(a.ID) + `,"name":` + text.Str(a.Name) + `,"kind":` + text.Str(a.Kind) + `,"owner":` + text.Str(a.Owner.String()) +
		`,"bio":` + text.Str(a.Bio) + `,"source":` + text.Str(a.Source) + `,"joined":` + itoa64(a.Joined) + `,"tips":` + itoa64(a.Tips) +
		`,"followers":` + itoa(a.Followers) + `,"verified":` + strconv.FormatBool(a.Verified) +
		`,"tracks":` + store.JSON(trackIDs) + `,"albums":` + store.JSON(albumIDs) + `}`
}

func AlbumJSON(id int) string {
	al := getAlbum(id)
	if !visibleAlbum(al) {
		panic("catalog: unknown album")
	}
	return albumJSON(al)
}

func visibleAlbum(al *Album) bool {
	return al != nil && !al.Hidden && visibleArtist(getArtist(al.Artist))
}

func albumJSON(al *Album) string {
	return `{"id":` + itoa(al.ID) + `,"artist":` + itoa(al.Artist) + `,"title":` + text.Str(al.Title) + `,"cover":` + text.Str(al.Cover) +
		`,"coverSha256":` + text.Str(al.CoverSHA) + `,"year":` + itoa(al.Year) + `,"tracks":` + store.JSON(al.list) + `}`
}

func PlaylistJSON(id int) string {
	p := getPlaylist(id)
	if p == nil || p.Hidden {
		panic("catalog: unknown playlist")
	}
	return playlistJSON(p)
}

func playlistJSON(p *Playlist) string {
	return `{"id":` + itoa(p.ID) + `,"owner":` + text.Str(p.Owner.String()) + `,"title":` + text.Str(p.Title) +
		`,"updated":` + itoa64(p.Updated) + `,"tracks":` + store.JSON(p.list) + `}`
}

// UserJSON returns a listener's public counters (likes are paged with LikesJSON).
func UserJSON(addr address) string {
	likes, follows, tipped, lists := UserStats(addr)
	return `{"address":` + text.Str(addr.String()) + `,"likes":` + itoa(likes) + `,"follows":` + itoa(follows) +
		`,"tipped":` + itoa64(tipped) + `,"playlists":` + ints(lists) + `,"artist":` + itoa(artistOf(addr)) + `}`
}

func LikesJSON(addr address, offset, limit int) string { return ints(LikedPage(addr, offset, limit)) }

func GenresJSON() string {
	var b strings.Builder
	b.WriteString("[")
	for g := 1; g <= NumGenres; g++ {
		if g > 1 {
			b.WriteString(",")
		}
		b.WriteString(`{"id":` + itoa(g) + `,"name":` + text.Str(genres[g]) + `}`)
	}
	b.WriteString("]")
	return b.String()
}

// maxBatch caps the batched readers, so one query stays far below the qeval budget.
const maxBatch = 100

// batch writes {"total":n,"<key>":[...]} for ids offset+1..offset+limit, skipping
// hidden items; one query replaces up to 100 single reads.
func batch(key string, total, offset, limit int, one func(id int) string) string {
	if limit < 1 || limit > maxBatch {
		limit = maxBatch
	}
	if offset < 0 {
		offset = 0
	}
	var b strings.Builder
	b.WriteString(`{"total":` + itoa(total) + `,"` + key + `":[`)
	n := 0
	for id := offset + 1; id <= total && id <= offset+limit; id++ {
		if s := one(id); s != "" {
			if n > 0 {
				b.WriteString(",")
			}
			b.WriteString(s)
			n++
		}
	}
	b.WriteString(`]}`)
	return b.String()
}

// ArtistsJSON returns visible artists with ids offset+1..offset+limit (at most 100).
func ArtistsJSON(offset, limit int) string {
	return batch("artists", nArtists, offset, limit, func(id int) string {
		if a := getArtist(id); visibleArtist(a) {
			return artistJSON(a)
		}
		return ""
	})
}

// AlbumsJSON returns visible albums with ids offset+1..offset+limit (at most 100).
func AlbumsJSON(offset, limit int) string {
	return batch("albums", nAlbums, offset, limit, func(id int) string {
		if al := getAlbum(id); visibleAlbum(al) {
			return albumJSON(al)
		}
		return ""
	})
}

// PlaylistsJSON returns visible playlists with ids offset+1..offset+limit (at most 100).
func PlaylistsJSON(offset, limit int) string {
	return batch("playlists", nPlaylists, offset, limit, func(id int) string {
		if p := getPlaylist(id); p != nil && !p.Hidden {
			return playlistJSON(p)
		}
		return ""
	})
}
