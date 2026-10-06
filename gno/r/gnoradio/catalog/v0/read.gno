package catalog

import (
	"strings"

	"gno.land/p/nt/avl/v0"
)

// ---- Frozen read API for the other GnoRadio realms (values only) ----

func GenreName(g int) string {
	if g < 1 || g > NumGenres {
		return ""
	}
	return genres[g]
}

func TrackCount() int  { return nTracks }
func ArtistCount() int { return nArtists }

// TrackBrief is what the radio needs; playable is false for an unknown or
// hidden track, or one whose artist is hidden.
func TrackBrief(id int) (artistID, genre int, duration int64, playable_ bool) {
	t := getTrack(id)
	if t == nil {
		return 0, 0, 0, false
	}
	return t.Artist, t.Genre, t.Duration, playable(t)
}

func TrackTitle(id int) string {
	if t := getTrack(id); t != nil {
		return t.Title
	}
	return ""
}

func ArtistName(artistID int) string {
	if a := getArtist(artistID); a != nil {
		return a.Name
	}
	return ""
}

func ArtistOwner(artistID int) address {
	if a := getArtist(artistID); a != nil {
		return a.Owner
	}
	return ""
}

func ArtistOf(owner address) int { return artistOf(owner) }

func ArtistVisible(artistID int) bool { return visibleArtist(getArtist(artistID)) }

// ---- Value getters for the home realm and tools ----

// GetTrack returns a copy of a track; ok is false if unknown.
func GetTrack(id int) (Track, bool) {
	if t := getTrack(id); t != nil {
		return *t, true
	}
	return Track{}, false
}

func GetArtist(id int) (Artist, bool) {
	if a := getArtist(id); a != nil {
		return *a, true
	}
	return Artist{}, false
}

// ArtistByName looks a profile up by its (case-insensitive) name.
func ArtistByName(name string) int {
	if id, ok := names.Get(skeleton(strings.TrimSpace(name))).(int); ok {
		return id
	}
	return 0
}

func GetAlbum(id int) (Album, bool) {
	if a := getAlbum(id); a != nil {
		return *a, true
	}
	return Album{}, false
}

func GetPlaylist(id int) (Playlist, bool) {
	if p := getPlaylist(id); p != nil {
		return *p, true
	}
	return Playlist{}, false
}

func AlbumCount() int    { return nAlbums }
func PlaylistCount() int { return nPlaylists }
func ReportCount() int   { return nReports }

func GetReport(id int) (ReportInfo, bool) {
	if r, ok := reports.Get(key(id)).(*ReportInfo); ok {
		return *r, true
	}
	return ReportInfo{}, false
}

// UserStats returns a listener's public counters and playlists.
func UserStats(addr address) (likes, follows int, tipped int64, lists []int) {
	if u, ok := users.Get(addr.String()).(*User); ok {
		return u.NLikes, u.NFollows, u.Tipped, append([]int(nil), u.Playlists...)
	}
	return 0, 0, 0, nil
}

func HasLiked(addr address, trackID int) bool {
	u, ok := users.Get(addr.String()).(*User)
	return ok && u.Likes.Has(key(trackID))
}

func IsFollowing(addr address, artistID int) bool {
	u, ok := users.Get(addr.String()).(*User)
	return ok && u.Follows.Has(key(artistID))
}

// LikedPage lists a listener's liked track ids, newest key last, paginated.
func LikedPage(addr address, offset, limit int) []int {
	var out []int
	if u, ok := users.Get(addr.String()).(*User); ok {
		u.Likes.IterateByOffset(offset, clampLimit(limit), func(k string, _ any) bool {
			out = append(out, atoiKey(k))
			return false
		})
	}
	return out
}

// TrackPage lists track ids, newest first when newest is true.
func TrackPage(offset, limit int, newest bool) []int {
	return idPage(&tracks, offset, limit, newest)
}

func ArtistPage(offset, limit int) []int   { return idPage(&artists, offset, limit, false) }
func AlbumPage(offset, limit int) []int    { return idPage(&albums, offset, limit, true) }
func PlaylistPage(offset, limit int) []int { return idPage(&playlists, offset, limit, true) }
func ReportPage(offset, limit int) []int   { return idPage(&reports, offset, limit, true) }

func TopLiked() []Rank   { return append([]Rank(nil), topLiked...) }
func TopArtists() []Rank { return append([]Rank(nil), topArtists...) }
func TopFans() []Rank    { return append([]Rank(nil), topFans...) }

func Admin() address            { return admin }
func Frozen() bool              { return frozen }
func Successor() string         { return successor }
func Version() string           { return version }
func RightsTerms() string       { return rightsTerms }
func HostAllowed(h string) bool { return hosts.Has(strings.ToLower(h)) }

func idPage(t *avl.Tree, offset, limit int, newest bool) []int {
	var out []int
	if offset < 0 {
		offset = 0
	}
	cb := func(k string, _ any) bool {
		out = append(out, atoiKey(k))
		return false
	}
	if newest {
		t.ReverseIterateByOffset(offset, clampLimit(limit), cb)
	} else {
		t.IterateByOffset(offset, clampLimit(limit), cb)
	}
	return out
}

func clampLimit(n int) int {
	if n < 1 || n > 100 {
		return 100
	}
	return n
}

func atoiKey(k string) int {
	n := 0
	for _, c := range k {
		n = n*10 + int(c-'0')
	}
	return n
}
