package catalog

import (
	"strconv"
	"strings"

	"gno.land/p/gnoradio/store/v0"
)

// Records are store.Rec values: fields behind a length header, so reading a
// field never scans the record. Hot fields come first. Id lists use store's
// JSON-ready width and go straight into the JSON exports.

func atoi(s string) int {
	n, _ := strconv.Atoi(s)
	return n
}

func atoi64(s string) int64 {
	n, _ := strconv.ParseInt(s, 10, 64)
	return n
}

func flag(b bool) string {
	if b {
		return "1"
	}
	return ""
}

// ---- tracks: artist, genre, duration, hidden first (what the radio reads) ----

// Track record fields that are read or updated alone.
const (
	fArtist = 0
	fHidden = 3
	fTitle  = 5
	fLikes  = 18
	fEarly  = 21
)

func trackRec(id int) (string, bool) { return tracks.Get(id - 1) }

func getTrack(id int) *Track {
	rec, ok := trackRec(id)
	if !ok {
		return nil
	}
	f := store.Fields(rec)
	t := &Track{
		ID: id, Artist: atoi(f[0]), Genre: atoi(f[1]), Duration: atoi64(f[2]), Hidden: f[3] != "",
		Origin: f[4], Title: f[5], License: f[6], CMO: f[7], Credits: f[8], Audio: f[9], AudioSHA: f[10],
		Cover: f[11], CoverSHA: f[12], SourceURL: f[13], Attribution: f[14], Album: atoi(f[16]),
		Created: atoi64(f[17]), Likes: atoi(f[18]), Tips: atoi64(f[19]), Supporters: atoi(f[20]),
	}
	if f[15] != "" {
		for _, p := range strings.Split(f[15], ",") {
			to, pct, _ := strings.Cut(p, ":")
			t.Splits = append(t.Splits, Split{To: address(to), Pct: atoi64(pct)})
		}
	}
	if f[21] != "" {
		for _, a := range strings.Split(f[21], ",") {
			t.Early = append(t.Early, address(a))
		}
	}
	return t
}

func trackRecord(t *Track) string {
	var splits, early []string
	for _, s := range t.Splits {
		splits = append(splits, s.To.String()+":"+itoa64(s.Pct))
	}
	for _, a := range t.Early {
		early = append(early, a.String())
	}
	return store.Rec(itoa(t.Artist), itoa(t.Genre), itoa64(t.Duration), flag(t.Hidden), t.Origin, t.Title,
		t.License, t.CMO, t.Credits, t.Audio, t.AudioSHA, t.Cover, t.CoverSHA, t.SourceURL, t.Attribution,
		strings.Join(splits, ","), itoa(t.Album), itoa64(t.Created), itoa(t.Likes), itoa64(t.Tips),
		itoa(t.Supporters), strings.Join(early, ","))
}

func putTrack(t *Track) { tracks.Set(t.ID-1, trackRecord(t)) }

// brief reads only what playback needs, without decoding the whole track.
func brief(id int) (artist, genre int, dur int64, hidden, ok bool) {
	rec, ok := trackRec(id)
	if !ok {
		return 0, 0, 0, false, false
	}
	return atoi(store.Field(rec, 0)), atoi(store.Field(rec, 1)), atoi64(store.Field(rec, 2)), store.Field(rec, 3) != "", true
}

// ---- artists: a small head record (hidden first), the id lists apart ----

func artistRec(id int) (string, bool) { return artists.Get(id - 1) }

// getArtist returns an artist's head; Tracks and Albums stay empty (see withLists).
func getArtist(id int) *Artist {
	rec, ok := artistRec(id)
	if !ok {
		return nil
	}
	f := store.Fields(rec)
	return &Artist{
		ID: id, Hidden: f[0] != "", Owner: address(f[1]), Kind: f[2], Name: f[3], Bio: f[4], Source: f[5],
		Joined: atoi64(f[6]), Tips: atoi64(f[7]), Followers: atoi(f[8]), Verified: f[9] != "",
	}
}

func artistRecord(a *Artist) string {
	return store.Rec(flag(a.Hidden), a.Owner.String(), a.Kind, a.Name, a.Bio, a.Source, itoa64(a.Joined),
		itoa64(a.Tips), itoa(a.Followers), flag(a.Verified))
}

func putArtist(a *Artist) { artists.Set(a.ID-1, artistRecord(a)) }

// artistVisible and artistField read one field of the head.
func artistVisible(id int) bool {
	rec, ok := artistRec(id)
	return ok && store.Field(rec, 0) == ""
}

func artistField(id, i int) string {
	rec, _ := artistRec(id)
	if rec == "" {
		return ""
	}
	return store.Field(rec, i)
}

// lists returns an artist's track and album id lists.
func lists(artistID int) (trackIDs, albumIDs string) {
	rec, ok := artistLists.Get(artistID - 1)
	if !ok {
		return "", ""
	}
	f := store.Fields(rec)
	return f[0], f[1]
}

func setLists(artistID int, trackIDs, albumIDs string) {
	artistLists.Set(artistID-1, store.Rec(trackIDs, albumIDs))
}

// withLists fills an artist head's Tracks and Albums.
func withLists(a *Artist) *Artist {
	t, al := lists(a.ID)
	a.Tracks, a.Albums = store.Ints(t), store.Ints(al)
	return a
}

// ---- albums and playlists ----

func getAlbum(id int) *Album {
	rec, ok := albums.Get(id - 1)
	if !ok {
		return nil
	}
	f := store.Fields(rec)
	return &Album{ID: id, Artist: atoi(f[0]), Title: f[1], Cover: f[2], CoverSHA: f[3], Year: atoi(f[4]),
		Created: atoi64(f[5]), Hidden: f[6] != "", Tracks: store.Ints(f[7]), list: f[7]}
}

func albumRecord(al *Album) string {
	return store.Rec(itoa(al.Artist), al.Title, al.Cover, al.CoverSHA, itoa(al.Year), itoa64(al.Created),
		flag(al.Hidden), store.Pack(al.Tracks))
}

func putAlbum(al *Album) { albums.Set(al.ID-1, albumRecord(al)) }

func getPlaylist(id int) *Playlist {
	rec, ok := playlists.Get(id - 1)
	if !ok {
		return nil
	}
	f := store.Fields(rec)
	return &Playlist{ID: id, Owner: address(f[0]), Title: f[1], Updated: atoi64(f[2]), Hidden: f[3] != "",
		Tracks: store.Ints(f[4]), list: f[4]}
}

func playlistRecord(p *Playlist) string {
	return store.Rec(p.Owner.String(), p.Title, itoa64(p.Updated), flag(p.Hidden), store.Pack(p.Tracks))
}

func putPlaylist(p *Playlist) { playlists.Set(p.ID-1, playlistRecord(p)) }

// ---- listeners ----

func getUser(addr address) *User {
	i, ok := users.Get(addr.String())
	if !ok {
		return nil
	}
	rec, _ := userRecs.Get(atoi(i))
	f := store.Fields(rec)
	return &User{Likes: f[0], Follows: f[1], Tipped: atoi64(f[2]), tipped: f[3], Playlists: store.Ints(f[4]),
		Reports: atoi(f[5])}
}

// putUser saves a listener; the address index is written only for a new listener.
func putUser(addr address, u *User) {
	rec := store.Rec(u.Likes, u.Follows, itoa64(u.Tipped), u.tipped, store.Pack(u.Playlists), itoa(u.Reports))
	if i, ok := users.Get(addr.String()); ok {
		userRecs.Set(atoi(i), rec)
		return
	}
	users.Set(addr.String(), itoa(userRecs.Append(rec)))
}
