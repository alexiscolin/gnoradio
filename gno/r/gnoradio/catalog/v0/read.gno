package catalog

import (
	"strings"

	"gno.land/p/gnoradio/store/v0"
	"gno.land/p/gnoradio/text/v0"

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
	a, g, d, hidden, ok := brief(id)
	if !ok {
		return 0, 0, 0, false
	}
	return a, g, d, !hidden && artistVisible(a)
}

func TrackTitle(id int) string {
	if rec, ok := trackRec(id); ok {
		return store.Field(rec, fTitle)
	}
	return ""
}

func ArtistName(artistID int) string { return artistField(artistID, aName) }

func ArtistOwner(artistID int) address { return address(artistField(artistID, aOwner)) }

func ArtistOf(owner address) int { return artistOf(owner) }

func ArtistVisible(artistID int) bool { return artistVisible(artistID) }

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
		return *withLists(a), true
	}
	return Artist{}, false
}

// ArtistByName looks a profile up by its (case-insensitive) name.
func ArtistByName(name string) int {
	v, _ := names.Get(skeleton(strings.TrimSpace(name)))
	return atoi(v)
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

// ReportCount is the number of open (unresolved) reports.
func ReportCount() int { return openReports }

func GetReport(id int) (ReportInfo, bool) {
	if r, ok := reports.Get(text.Key(id)).(*ReportInfo); ok {
		return *r, true
	}
	return ReportInfo{}, false
}

// UserStats returns a listener's public counters and playlists.
// The like count reads one entry per 512 tracks of the catalog.
func UserStats(addr address) (likes, follows int, tipped int64, lists []int) {
	for r := nTracks >> likeRange; r >= 0; r-- {
		l, _ := likeSets.Get(addr.String() + "/" + itoa(r))
		likes += store.Count(l)
	}
	if u := getUser(addr); u != nil {
		return likes, store.Count(u.Follows), u.Tipped, u.Playlists
	}
	return likes, 0, 0, nil
}

// LikedPage lists a listener's liked track ids, newest tracks first,
// paginated. Likes are keyed by track id, so this is the newest music the
// listener liked, not the order of their likes (that needs an index per like,
// which would add to every like's storage deposit). It reads one entry per
// 512 tracks of the catalog, newest first, until the page is full.
func LikedPage(addr address, offset, limit int) []int {
	offset, limit = max0(offset), clampLimit(limit)
	var out []int
	for r := nTracks >> likeRange; r >= 0 && len(out) < limit; r-- {
		l, _ := likeSets.Get(addr.String() + "/" + itoa(r))
		if n := store.Count(l); offset >= n {
			offset -= n
			continue
		}
		out = append(out, store.Page(l, offset, limit-len(out), true)...)
		offset = 0
	}
	return out
}

// ---- Narrow getters: one field without copying a whole struct ----

// ArtistTrackCount is the number of tracks an artist published.
func ArtistTrackCount(artistID int) int {
	if artistID < 1 || artistID > nArtists {
		return 0
	}
	t, _ := lists(artistID)
	return store.Count(t)
}

// ArtistTrackPage lists an artist's track ids in publishing order, paginated.
func ArtistTrackPage(artistID, offset, limit int) []int {
	if artistID < 1 || artistID > nArtists || offset < 0 {
		return nil
	}
	t, _ := lists(artistID)
	return store.Page(t, offset, clampLimit(limit), false)
}

// ArtistBrief returns what a link to an artist needs, without the bio or the
// id lists; ok is false for an unknown artist.
func ArtistBrief(artistID int) (name string, verified, hidden, ok bool) {
	rec, ok := artistRec(artistID)
	if !ok {
		return "", false, false, false
	}
	return store.Field(rec, aName), store.Field(rec, aVerified) != "", store.Field(rec, aHidden) != "", true
}

// PlaylistBrief returns a playlist's header without its track ids.
func PlaylistBrief(id int) (owner address, title string, tracks int, hidden, ok bool) {
	p := getPlaylist(id)
	if p == nil {
		return "", "", 0, false, false
	}
	return p.Owner, p.Title, len(p.Tracks), p.Hidden, true
}

// ---- Migration pages: everything a successor realm needs to copy ----

// UsersPage lists listener addresses in a stable (hash bucket) order, paginated.
func UsersPage(offset, limit int) []string { return users.Keys(max0(offset), clampLimit(limit)) }

// LikesPage lists the likes entries ("address/range", stable order); a
// listener who only liked has no UsersPage entry. LikedPage reads them.
func LikesPage(offset, limit int) []string { return likeSets.Keys(max0(offset), clampLimit(limit)) }

// TippedPage lists the track ids a listener tipped (each counted once in the
// track's supporters), paginated.
func TippedPage(addr address, offset, limit int) []int {
	if u := getUser(addr); u != nil {
		return store.Page(u.tipped, max0(offset), clampLimit(limit), false)
	}
	return nil
}

// SupportersPage lists who supported GnoRadio and their lifetime total, in
// a stable order (not sorted).
func SupportersPage(offset, limit int) (addrs []string, totals []int64) {
	if offset < 0 {
		offset = 0
	}
	for _, k := range supporterTotal.Keys(offset, clampLimit(limit)) {
		v, _ := supporterTotal.Get(k)
		addrs = append(addrs, k)
		totals = append(totals, atoi64(v))
	}
	return addrs, totals
}

// FollowsPage lists the artist ids a listener follows, paginated.
func FollowsPage(addr address, offset, limit int) []int {
	if u := getUser(addr); u != nil {
		return store.Page(u.Follows, max0(offset), clampLimit(limit), false)
	}
	return nil
}

// GenrePage lists the track ids of a genre (hidden ones included), newest first.
func GenrePage(genre, offset, limit int) []int {
	if genre < 1 || genre > NumGenres {
		return nil
	}
	return byGenre[genre].Page(offset, clampLimit(limit), true)
}

// GenreCount is the number of tracks filed under a genre.
func GenreCount(genre int) int {
	if genre < 1 || genre > NumGenres {
		return 0
	}
	return byGenre[genre].Len()
}

// TrackPage lists track ids, newest first when newest is true.
// Ids are dense (1..count), so these pages are arithmetic.
func TrackPage(offset, limit int, newest bool) []int { return seqPage(nTracks, offset, limit, newest) }
func ArtistPage(offset, limit int) []int             { return seqPage(nArtists, offset, limit, false) }
func AlbumPage(offset, limit int) []int              { return seqPage(nAlbums, offset, limit, true) }
func PlaylistPage(offset, limit int) []int           { return seqPage(nPlaylists, offset, limit, true) }
func ReportPage(offset, limit int) []int             { return idPage(&reports, offset, limit, true) }

func seqPage(n, offset, limit int, newest bool) []int {
	var out []int
	for k := max0(offset); k < n && len(out) < clampLimit(limit); k++ {
		if newest {
			out = append(out, n-k)
		} else {
			out = append(out, k+1)
		}
	}
	return out
}

func max0(n int) int {
	if n < 0 {
		return 0
	}
	return n
}

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
