package catalog

import (
	"chain"
	"chain/banker"
	"strings"
)

// Like records a public like. The first listeners to like a track earn its
// early-listener badge. (Saving a track privately is done in the app, free.)
func Like(cur realm, trackID int) {
	caller := userCaller(cur)
	noPayment()
	notFrozen()
	t := mustTrack(trackID)
	if getArtist(t.Artist).Owner == caller {
		panic("catalog: you cannot like your own track")
	}
	u := user(caller)
	if u.Likes.Has(key(trackID)) {
		panic("catalog: already liked")
	}
	u.Likes.Set(key(trackID), true)
	u.NLikes++
	t.Likes++
	if len(t.Early) < earlyBadges && !hasAddr(t.Early, caller) {
		t.Early = append(t.Early, caller)
	}
	topLiked = updateTop(topLiked, itoa(t.ID), int64(t.Likes))
	recordActivity("like", caller, t.ID, t.Artist, 0)
	emitEvent("Liked", "track", itoa(trackID), "by", caller.String())
}

func Unlike(cur realm, trackID int) {
	caller := userCaller(cur)
	noPayment()
	u := user(caller)
	if _, ok := u.Likes.Remove(key(trackID)); !ok {
		panic("catalog: not liked")
	}
	u.NLikes--
	if t := getTrack(trackID); t != nil && t.Likes > 0 {
		t.Likes--
		topLiked = updateTop(topLiked, itoa(t.ID), int64(t.Likes))
	}
	emitEvent("Unliked", "track", itoa(trackID), "by", caller.String())
}

// Tip forwards the attached ugnot to the track's artist and collaborators,
// split as declared at publish time, in this same transaction. Unclaimed
// (curated / Audius) artists cannot receive tips until they claim their profile.
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
	if a.Owner == "" {
		panic("catalog: this artist has not claimed their profile yet")
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
	if !u.tipped.Has(key(trackID)) {
		u.tipped.Set(key(trackID), true)
		t.Supporters++
	}
	t.Tips += amt
	a.Tips += amt
	u.Tipped += amt
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
	nAlbums++
	al := &Album{ID: nAlbums, Artist: a.ID, Title: title, Cover: cover, CoverSHA: coverSHA, Year: year, Tracks: ids, Created: now()}
	albums.Set(key(al.ID), al)
	for _, id := range ids {
		getTrack(id).Album = al.ID
	}
	a.Albums = appendCapped(a.Albums, al.ID, maxPerArtist, "albums per artist")
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
	playlists.Set(key(p.ID), p)
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
	emitEvent("PlaylistUpdated", "id", itoa(p.ID), "tracks", itoa(len(p.Tracks)))
}

func checkedIDs(s string) []int {
	ids := parseIDs(s, maxListTracks)
	seen := map[int]bool{}
	for _, id := range ids {
		if seen[id] {
			panic("catalog: duplicate track " + itoa(id))
		}
		seen[id] = true
		mustTrack(id)
	}
	return ids
}

func hasAddr(list []address, a address) bool {
	for _, x := range list {
		if x == a {
			return true
		}
	}
	return false
}
