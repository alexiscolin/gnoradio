package catalog

import (
	"strings"
	"testing"

	"gno.land/p/gnoradio/store/v0"
	"gno.land/p/gnoradio/text/v0"
	"gno.land/p/nt/uassert/v0"
	"gno.land/r/gnoradio/data"
)

// Playlists only check the id range and duplicates (no per-track load).
func TestPlaylistIDsRangeOnly(cur realm, t *testing.T) {
	alice, _ := artist(cur, "alice")
	carol := who("carol")
	a, b := publish(cur, alice, "One"), publish(cur, alice, "Two")
	testing.SetRealm(testing.NewUserRealm(boss))
	HideTrack(cross(cur), b, true, "test hide")

	testing.SetRealm(testing.NewUserRealm(carol))
	far := text.Itoa(TrackCount() + 1)
	uassert.AbortsContains(t, cur, "unknown track "+far, func() { PublishPlaylist(cross(cur), "Too far", text.Itoa(a)+","+far) })
	uassert.AbortsContains(t, cur, "duplicate", func() { PublishPlaylist(cross(cur), "Twice", text.Itoa(a)+","+text.Itoa(a)) })
	id := PublishPlaylist(cross(cur), "Mixed", text.Itoa(a)+","+text.Itoa(b)) // a hidden id is accepted, filtered on read
	owner, title, n, hidden, ok := PlaylistBrief(id)
	uassert.True(t, ok)
	uassert.Equal(t, carol, owner)
	uassert.Equal(t, "Mixed", title)
	uassert.Equal(t, 2, n)
	uassert.False(t, hidden)
}

// LikedPage lists the newest tracks first.
func TestLikedPageNewestFirst(cur realm, t *testing.T) {
	alice, _ := artist(cur, "alice")
	carol := who("carol")
	a, b, c := publish(cur, alice, "A"), publish(cur, alice, "B"), publish(cur, alice, "C")
	testing.SetRealm(testing.NewUserRealm(carol))
	Like(cross(cur), b)
	Like(cross(cur), a)
	Like(cross(cur), c)
	got := LikedPage(carol, 0, 10)
	uassert.Equal(t, 3, len(got))
	uassert.Equal(t, c, got[0])
	uassert.Equal(t, a, got[2])
	uassert.Equal(t, `[`+text.Itoa(c)+`,`+text.Itoa(b)+`,`+text.Itoa(a)+`]`, LikesJSON(carol, 0, 10))
}

// Narrow getters.
func TestNarrowGetters(cur realm, t *testing.T) {
	alice, aid := artist(cur, "alice")
	carol := who("carol")
	var ids []int
	for i := 0; i < 5; i++ {
		ids = append(ids, publish(cur, alice, "P "+text.Itoa(i)))
	}
	uassert.Equal(t, 5, ArtistTrackCount(aid))
	page := ArtistTrackPage(aid, 3, 10)
	uassert.Equal(t, 2, len(page))
	uassert.Equal(t, ids[3], page[0])
	uassert.Equal(t, 0, len(ArtistTrackPage(aid, 5, 10)))
	uassert.Equal(t, 0, ArtistTrackCount(ArtistCount()+1))
	n, verified, hidden, ok := ArtistBrief(aid)
	uassert.True(t, ok && strings.HasPrefix(n, "alice") && !verified && !hidden)
	_, _, _, ok = ArtistBrief(ArtistCount() + 1)
	uassert.False(t, ok)

	users := data.Size(cUsers)
	testing.SetRealm(testing.NewUserRealm(carol))
	Like(cross(cur), ids[0])
	uassert.Equal(t, users, data.Size(cUsers)) // a like writes no listener record
	Follow(cross(cur), aid)
	uassert.Equal(t, users+1, data.Size(cUsers))
	likes, follows, tipped, lists := UserStats(carol)
	uassert.True(t, likes == 1 && follows == 1 && tipped == 0 && len(lists) == 0)
}

// Validated text goes out as plain JSON strings, accents and & included.
func TestPlainJSONStrings(cur realm, t *testing.T) {
	alice := who("alice")
	n := name("Léa & Co")
	testing.SetRealm(testing.NewUserRealm(alice))
	RegisterArtist(cross(cur), n, "")
	id := PublishTrack(cross(cur), "Café d'été", 2, "3:30", "cc by", "none", "", ipfs, "", "", "", "", "yes")
	js := TrackJSON(id)
	uassert.True(t, strings.Contains(js, `"title":"Café d'été"`), js)
	uassert.True(t, strings.Contains(js, `"artistName":"`+n+`"`), js)
	uassert.Equal(t, `"x"`, text.Str("x"))
}

// Likes are kept per range of 512 track ids: a like rewrites one short list
// (never the listener's whole history), pages run across ranges newest
// first, and an emptied range is removed.
func TestLikesAcrossRanges(cur realm, t *testing.T) {
	alice, _ := artist(cur, "alice")
	carol := who("carol")
	a := publish(cur, alice, "First")
	// ids past the catalog, in two ranges above a's: only the ranges matter here
	base := (a>>idRange + 2) << idRange
	x1, x2, x3 := base+8, base+88, base+600
	k1, k2 := rangeKey(carol.String(), x1), rangeKey(carol.String(), x3)
	seed(cur, cLikes, k1, store.Pack([]int{x1, x2}))
	seed(cur, cLikes, k2, store.Pack([]int{x3}))
	testing.SetRealm(testing.NewUserRealm(carol))
	Like(cross(cur), a)
	l, _ := data.Get(cLikes, rangeKey(carol.String(), a))
	uassert.Equal(t, store.Pack([]int{a}), l) // only a's range was written
	l, _ = data.Get(cLikes, k1)
	uassert.Equal(t, store.Pack([]int{x1, x2}), l)

	got := LikedPage(carol, 0, 10)
	uassert.Equal(t, 4, len(got))
	uassert.Equal(t, x3, got[0])
	uassert.Equal(t, x2, got[1])
	uassert.Equal(t, x1, got[2])
	uassert.Equal(t, a, got[3])
	got = LikedPage(carol, 2, 1)
	uassert.Equal(t, 1, len(got))
	uassert.Equal(t, x1, got[0])
	likes, _, _, _ := UserStats(carol)
	uassert.Equal(t, 4, likes)

	Unlike(cross(cur), a)
	uassert.False(t, data.Has(cLikes, rangeKey(carol.String(), a)))
	likes, _, _, _ = UserStats(carol)
	uassert.Equal(t, 3, likes)
	uassert.AbortsContains(t, cur, "not liked", func() { Unlike(cross(cur), a) })
}

// The named field indexes follow the record layouts (ArtistVerified gates tips).
func TestRecordFieldIndexes(t *testing.T) {
	a := artistRecord(&Artist{Hidden: true, Owner: boss, Name: "Named", Verified: true})
	uassert.Equal(t, "1", store.Field(a, aHidden))
	uassert.Equal(t, boss.String(), store.Field(a, aOwner))
	uassert.Equal(t, "Named", store.Field(a, aName))
	uassert.Equal(t, "1", store.Field(a, aVerified))
	tr := trackRecord(&Track{Artist: 7, Genre: 3, Duration: 99, Hidden: true, Title: "T", Likes: 5, Early: []address{boss}})
	uassert.Equal(t, "7", store.Field(tr, fArtist))
	uassert.Equal(t, "3", store.Field(tr, fGenre))
	uassert.Equal(t, "99", store.Field(tr, fDuration))
	uassert.Equal(t, "1", store.Field(tr, fHidden))
	uassert.Equal(t, "T", store.Field(tr, fTitle))
	uassert.Equal(t, "5", store.Field(tr, fLikes))
	uassert.Equal(t, boss.String(), store.Field(tr, fEarly))
}

// Chunks: a record is appended or replaced in place, never another's.
func TestChunks(t *testing.T) {
	tx := rd()
	c := "catalog/none" // no such collection: reads are empty, nothing is saved
	tx.addRec(c, 1, "a")
	tx.addRec(c, 2, "b")
	tx.setRec(c, 1, "A")
	uassert.Equal(t, "A", tx.rec(c, 1))
	uassert.Equal(t, "b", tx.rec(c, 2))
	uassert.Equal(t, "", tx.rec(c, 3))
	uassert.Equal(t, "", tx.rec(c, 0))
	tx.addRec(c, chunkSize+1, "z") // the next chunk
	uassert.Equal(t, store.Rec("A", "b"), tx.val(c, store.Pad(0)))
	uassert.Equal(t, store.Rec("z"), tx.val(c, store.Pad(1)))
}

func TestCountFields(t *testing.T) {
	uassert.Equal(t, 0, mTracks)
	uassert.Equal(t, NumGenres, mGenre+NumGenres)
	uassert.Equal(t, NumGenres+1, mArtists)
	uassert.Equal(t, NumGenres+8, mFields)
}

// The radio's one-read getters agree with TrackBrief and the artist record:
// own covers the artist and the collaborators only, PlayableTitle is "" once
// hidden, ArtistPayee reads owner, badge and visibility at once.
func TestRadioGetters(cur realm, t *testing.T) {
	alice, aid := artist(cur, "alice")
	bob, carol := who("bob"), who("carol")
	testing.SetRealm(testing.NewUserRealm(alice))
	id := PublishTrack(cross(cur), "Getter Song", 2, "1:40", "CC-BY", "none", "", ipfs, "", "", "", bob.String()+":30", "yes")
	a, g, d, ok := TrackBrief(id)
	for _, c := range []struct {
		addr address
		own  bool
	}{{alice, true}, {bob, true}, {carol, false}, {"", false}} {
		a2, g2, d2, ok2, own := TrackBriefFor(id, c.addr)
		uassert.Equal(t, a, a2)
		uassert.Equal(t, g, g2)
		uassert.Equal(t, d, d2)
		uassert.Equal(t, ok, ok2)
		uassert.Equal(t, c.own, own)
	}
	uassert.True(t, ok)
	uassert.Equal(t, "Getter Song", PlayableTitle(id))
	_, _, _, ok, own := TrackBriefFor(999999, alice)
	uassert.False(t, ok || own)
	uassert.Equal(t, "", PlayableTitle(999999))
	owner, badge, visible := ArtistPayee(aid)
	uassert.Equal(t, alice, owner)
	uassert.False(t, badge)
	uassert.True(t, visible)
	verified(cur, aid)
	_, badge, _ = ArtistPayee(aid)
	uassert.True(t, badge)
	testing.SetRealm(testing.NewUserRealm(boss))
	HideArtist(cross(cur), aid, true, "test")
	_, _, visible = ArtistPayee(aid)
	uassert.False(t, visible)
	uassert.Equal(t, "", PlayableTitle(id))
	_, _, _, ok, _ = TrackBriefFor(id, alice)
	uassert.False(t, ok)
	HideArtist(cross(cur), aid, false, "")
	HideTrack(cross(cur), id, true, "test")
	uassert.Equal(t, "", PlayableTitle(id))
	_, _, _, ok = TrackBrief(id)
	uassert.False(t, ok)
	_, _, visible = ArtistPayee(0)
	uassert.False(t, visible)
}
