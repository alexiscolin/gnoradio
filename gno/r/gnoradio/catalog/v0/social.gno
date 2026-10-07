package catalog

import (
	"chain"
	"chain/banker"
	"strings"

	"gno.land/p/gnoradio/store/v0"
)

// Like records a public like. The first listeners to like a track earn its
// early-listener badge. (Saving a track privately is done in the app, free.)
func Like(cur realm, trackID int) {
	caller := userCaller(cur)
	noPayment()
	notFrozen()
	// Likes and the early badges are updated in place: the most frequent write
	// never decodes the whole track.
	rec, ok := trackRec(trackID)
	artistID := 0
	if ok {
		artistID = atoi(store.Field(rec, fArtist))
	}
	if !ok || store.Field(rec, fHidden) != "" || !artistVisible(artistID) {
		panic("catalog: unknown track")
	}
	if ArtistOwner(artistID) == caller {
		panic("catalog: you cannot like your own track")
	}
	u := user(caller)
	likes, added := store.Add(u.Likes, trackID)
	if !added {
		panic("catalog: already liked")
	}
	u.Likes = likes
	putUser(caller, u)
	n := atoi(store.Field(rec, fLikes)) + 1
	rec = store.With(rec, fLikes, itoa(n))
	if early := store.Field(rec, fEarly); !hasEarly(early, caller) && (len(early)+1)/(len(caller)+1) < earlyBadges {
		if early != "" {
			early += ","
		}
		rec = store.With(rec, fEarly, early+caller.String())
	}
	tracks.Set(trackID-1, rec)
	topLiked = updateTop(topLiked, itoa(trackID), int64(n))
	recordActivity("like", caller, trackID, artistID, 0)
	emitEvent("Liked", "track", itoa(trackID), "by", caller.String())
}

// hasEarly reports whether a comma-joined address list holds a (addresses
// share one length, so this compares slices instead of scanning bytes).
func hasEarly(list string, a address) bool {
	w := len(a) + 1
	for p := 0; p+len(a) <= len(list); p += w {
		if list[p:p+len(a)] == a.String() {
			return true
		}
	}
	return false
}

func Unlike(cur realm, trackID int) {
	caller := userCaller(cur)
	noPayment()
	notFrozen()
	u := user(caller)
	likes, ok := store.Remove(u.Likes, trackID)
	if !ok {
		panic("catalog: not liked")
	}
	u.Likes = likes
	putUser(caller, u)
	if rec, ok := trackRec(trackID); ok {
		if n := atoi(store.Field(rec, fLikes)); n > 0 {
			tracks.Set(trackID-1, store.With(rec, fLikes, itoa(n-1)))
			topLiked = updateTop(topLiked, itoa(trackID), int64(n-1))
		}
	}
	emitEvent("Unliked", "track", itoa(trackID), "by", caller.String())
}

// Tip forwards the attached ugnot to the track's artist and collaborators,
// split as declared at publish time, in this same transaction. Only verified
// artists receive tips (verify.gno), so a tip never reaches an impersonator.
func Tip(cur realm, trackID int) { tip(cur, trackID, 0) }

// TipWithSupport is Tip plus an optional contribution to GnoRadio: of the
// attached total T, the artist side receives T*100/(100+supportPct) (split as
// in Tip) and the rest goes to the GnoRadio treasury. supportPct is 0..50.
func TipWithSupport(cur realm, trackID int, supportPct int) { tip(cur, trackID, supportPct) }

func tip(cur realm, trackID int, supportPct int) {
	caller := userCaller(cur)
	notFrozen()
	if supportPct < 0 || supportPct > maxSupportPct {
		panic("catalog: supportPct must be between 0 and 50")
	}
	t := mustTrack(trackID)
	a := getArtist(t.Artist)
	if a.Owner == "" || !a.Verified {
		panic("catalog: this artist has not verified their profile yet")
	}
	if a.Owner == caller {
		panic("catalog: you cannot tip your own track")
	}
	total := paid()
	if total > maxTip+maxTip/2 {
		panic("catalog: a tip is between 0.1 and 1000000 GNOT")
	}
	amt := total * 100 / int64(100+supportPct)
	platform := total - amt
	if amt < minTip || amt > maxTip {
		panic("catalog: a tip is between 0.1 and 1000000 GNOT")
	}

	bk := banker.NewBanker(banker.BankerTypeRealmSend, cur)
	self := cur.Address()
	rest := amt
	var paidTo strings.Builder
	for _, s := range t.Splits {
		share := amt * s.Pct / 100
		if share > 0 {
			bk.SendCoins(self, s.To, chain.Coins{{Denom: denom, Amount: share}})
			rest -= share
			paidTo.WriteString(s.To.String() + ":" + itoa64(share) + ",")
		}
	}
	bk.SendCoins(self, a.Owner, chain.Coins{{Denom: denom, Amount: rest}})
	paidTo.WriteString(a.Owner.String() + ":" + itoa64(rest))
	if platform > 0 {
		bk.SendCoins(self, treasury, chain.Coins{{Denom: denom, Amount: platform}})
		recordSupport(caller, platform)
	}

	u := user(caller)
	if tipped, first := store.Add(u.tipped, trackID); first {
		u.tipped = tipped
		t.Supporters++
	}
	t.Tips += amt
	a.Tips += amt
	u.Tipped += amt
	putTrack(t)
	putArtist(a)
	putUser(caller, u)
	topArtists = updateTop(topArtists, itoa(a.ID), a.Tips)
	topFans = updateTop(topFans, caller.String(), u.Tipped)
	recordActivity("tip", caller, t.ID, a.ID, amt)
	emitEvent("Tipped", "track", itoa(trackID), "by", caller.String(), "amount", itoa64(amt), "paid", paidTo.String(), "support", itoa64(platform))
}

// ---- Albums ----

// CreateAlbum groups tracks of one artist. The artist (or the admin for an
// unclaimed artist) creates it; trackIDs is "12,13,14" in play order.
func CreateAlbum(cur realm, artistID int, title, cover, coverSHA string, year int, trackIDs string) int {
	caller := userCaller(cur)
	noPayment()
	notFrozen()
	a := mustArtist(artistID)
	if !mayEdit(caller, a) {
		panic("catalog: only the artist can create its albums")
	}
	title, cover, coverSHA = strings.TrimSpace(title), strings.TrimSpace(cover), strings.ToLower(strings.TrimSpace(coverSHA))
	mustText("title", title, 1, 64)
	if cover != "" {
		mustMedia("cover", cover, coverSHA, false)
	}
	if year < 1900 || year > 2100 {
		panic("catalog: year must be between 1900 and 2100")
	}
	ids := parseIDs(trackIDs, maxAlbumTracks)
	for _, id := range ids {
		t := mustTrack(id)
		if t.Artist != a.ID || t.Album != 0 {
			panic("catalog: track " + itoa(id) + " is not this artist's or already in an album")
		}
	}
	artistTracks, albumIDs := lists(a.ID)
	if store.Count(albumIDs) >= maxPerArtist {
		panic("catalog: albums per artist limit reached")
	}
	nAlbums++
	al := &Album{ID: nAlbums, Artist: a.ID, Title: title, Cover: cover, CoverSHA: coverSHA, Year: year, Tracks: ids, Created: now()}
	albums.Append(albumRecord(al))
	for _, id := range ids {
		t := getTrack(id)
		t.Album = al.ID
		putTrack(t)
	}
	setLists(a.ID, artistTracks, albumIDs+store.Enc(al.ID))
	recordActivity("album", caller, al.ID, a.ID, 0)
	emitEvent("AlbumCreated", "id", itoa(al.ID), "artist", itoa(a.ID), "title", title)
	return al.ID
}

// ---- Playlists ----

// PublishPlaylist makes a public playlist in one signature; trackIDs is
// "12,40,7". Private playlists live in the app and cost nothing.
func PublishPlaylist(cur realm, title, trackIDs string) int {
	caller := userCaller(cur)
	noPayment()
	notFrozen()
	title = strings.TrimSpace(title)
	mustText("title", title, 1, 64)
	ids := checkedIDs(trackIDs)
	u := user(caller)
	nPlaylists++
	p := &Playlist{ID: nPlaylists, Owner: caller, Title: title, Tracks: ids, Updated: now()}
	u.Playlists = appendCapped(u.Playlists, p.ID, maxUserLists, "playlists per listener")
	putUser(caller, u)
	playlists.Append(playlistRecord(p))
	recordActivity("playlist", caller, p.ID, 0, 0)
	emitEvent("PlaylistPublished", "id", itoa(p.ID), "owner", caller.String(), "tracks", itoa(len(ids)))
	return p.ID
}

// UpdatePlaylist replaces a playlist's title and tracks. Owner only.
func UpdatePlaylist(cur realm, playlistID int, title, trackIDs string) {
	caller := userCaller(cur)
	noPayment()
	notFrozen()
	p := getPlaylist(playlistID)
	if p == nil || p.Hidden || p.Owner != caller {
		panic("catalog: not your playlist")
	}
	title = strings.TrimSpace(title)
	mustText("title", title, 1, 64)
	p.Title, p.Tracks, p.Updated = title, checkedIDs(trackIDs), now()
	putPlaylist(p)
	emitEvent("PlaylistUpdated", "id", itoa(p.ID), "tracks", itoa(len(p.Tracks)))
}

// checkedIDs parses a playlist's track ids. Only the id range and duplicates
// are checked: loading every track cost about 1M gas per id, and hidden or
// removed tracks are skipped when the playlist is read.
func checkedIDs(s string) []int {
	ids := parseIDs(s, maxListTracks)
	for _, id := range ids {
		if id > nTracks {
			panic("catalog: unknown track " + itoa(id))
		}
	}
	return ids
}
