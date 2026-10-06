package catalog

import "strings"

// JSON exports for the GnoRadio app and indexers (vm/qeval). Every string
// passed validText / validName / URL checks, so none holds a quote or a
// backslash and no escaping is needed.

func q(s string) string { return `"` + s + `"` }

func boolStr(v bool) string {
	if v {
		return "true"
	}
	return "false"
}

func Info() string {
	return `{"version":` + q(version) + `,"artists":` + itoa(nArtists) + `,"tracks":` + itoa(nTracks) +
		`,"albums":` + itoa(nAlbums) + `,"playlists":` + itoa(nPlaylists) + `,"listeners":` + itoa(users.Size()) +
		`,"genres":` + itoa(NumGenres) + `,"now":` + itoa64(now()) + `,"frozen":` + boolStr(frozen) +
		`,"successor":` + q(successor) + `,"admin":` + q(admin.String()) + `}`
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

func trackJSON(t *Track) string {
	a := getArtist(t.Artist)
	var b strings.Builder
	b.WriteString(`{"id":` + itoa(t.ID) + `,"artist":` + itoa(t.Artist) + `,"artistName":` + q(a.Name) +
		`,"claimed":` + boolStr(a.Owner != "") + `,"origin":` + q(t.Origin) + `,"title":` + q(t.Title) +
		`,"genre":` + itoa(t.Genre) + `,"duration":` + itoa64(t.Duration) + `,"license":` + q(t.License) +
		`,"cmo":` + q(t.CMO) + `,"credits":` + q(t.Credits) + `,"audio":` + q(t.Audio) + `,"audioSha256":` + q(t.AudioSHA) +
		`,"cover":` + q(t.Cover) + `,"coverSha256":` + q(t.CoverSHA) + `,"source":` + q(t.SourceURL) +
		`,"attribution":` + q(t.Attribution) + `,"album":` + itoa(t.Album) + `,"created":` + itoa64(t.Created) +
		`,"likes":` + itoa(t.Likes) + `,"tips":` + itoa64(t.Tips) + `,"supporters":` + itoa(t.Supporters) + `,"splits":[`)
	for i, s := range t.Splits {
		if i > 0 {
			b.WriteString(",")
		}
		b.WriteString(`{"to":` + q(s.To.String()) + `,"pct":` + itoa64(s.Pct) + `}`)
	}
	b.WriteString(`]}`)
	return b.String()
}

// TrackJSON returns one playable track.
func TrackJSON(id int) string { return trackJSON(mustTrack(id)) }

// TracksJSON pages through playable tracks (newest first), at most 50.
func TracksJSON(offset, limit int) string {
	if limit < 1 || limit > 50 {
		limit = 50
	}
	var b strings.Builder
	b.WriteString(`{"total":` + itoa(nTracks) + `,"tracks":[`)
	n := 0
	for _, id := range TrackPage(offset, limit, true) {
		if t := getTrack(id); playable(t) {
			if n > 0 {
				b.WriteString(",")
			}
			b.WriteString(trackJSON(t))
			n++
		}
	}
	b.WriteString(`]}`)
	return b.String()
}

func ArtistJSON(id int) string {
	a := mustArtist(id)
	return `{"id":` + itoa(a.ID) + `,"name":` + q(a.Name) + `,"kind":` + q(a.Kind) + `,"owner":` + q(a.Owner.String()) +
		`,"bio":` + q(a.Bio) + `,"source":` + q(a.Source) + `,"joined":` + itoa64(a.Joined) + `,"tips":` + itoa64(a.Tips) +
		`,"followers":` + itoa(a.Followers) + `,"verified":` + boolStr(a.Verified) +
		`,"tracks":` + ints(a.Tracks) + `,"albums":` + ints(a.Albums) + `}`
}

func AlbumJSON(id int) string {
	al := getAlbum(id)
	if al == nil || al.Hidden || !visibleArtist(getArtist(al.Artist)) {
		panic("catalog: unknown album")
	}
	return `{"id":` + itoa(al.ID) + `,"artist":` + itoa(al.Artist) + `,"title":` + q(al.Title) + `,"cover":` + q(al.Cover) +
		`,"coverSha256":` + q(al.CoverSHA) + `,"year":` + itoa(al.Year) + `,"tracks":` + ints(al.Tracks) + `}`
}

func PlaylistJSON(id int) string {
	p := getPlaylist(id)
	if p == nil || p.Hidden {
		panic("catalog: unknown playlist")
	}
	return `{"id":` + itoa(p.ID) + `,"owner":` + q(p.Owner.String()) + `,"title":` + q(p.Title) +
		`,"updated":` + itoa64(p.Updated) + `,"tracks":` + ints(p.Tracks) + `}`
}

// UserJSON returns a listener's public counters (likes are paged with LikesJSON).
func UserJSON(addr address) string {
	likes, follows, tipped, lists := UserStats(addr)
	return `{"address":` + q(addr.String()) + `,"likes":` + itoa(likes) + `,"follows":` + itoa(follows) +
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
		b.WriteString(`{"id":` + itoa(g) + `,"name":` + q(genres[g]) + `}`)
	}
	b.WriteString("]")
	return b.String()
}
