package catalog

import (
	"strings"
	"testing"

	"gno.land/p/gnoradio/store/v0"
	"gno.land/p/gnoradio/text/v0"

	"gno.land/p/nt/uassert/v0"
)

// Playlists only check the id range and duplicates (no per-track load).
func TestPlaylistIDsRangeOnly(cur realm, t *testing.T) {
	reset()
	testing.SetRealm(testing.NewUserRealm(alice))
	RegisterArtist(cross(cur), "Range Alice", "")
	a, b := publish(cur, "One"), publish(cur, "Two")
	testing.SetRealm(testing.NewUserRealm(boss))
	HideTrack(cross(cur), b, true, "test hide")

	testing.SetRealm(testing.NewUserRealm(carol))
	uassert.AbortsContains(t, cur, "unknown track 3", func() { PublishPlaylist(cross(cur), "Too far", itoa(a)+",3") })
	uassert.AbortsContains(t, cur, "duplicate", func() { PublishPlaylist(cross(cur), "Twice", itoa(a)+","+itoa(a)) })
	id := PublishPlaylist(cross(cur), "Mixed", itoa(a)+","+itoa(b)) // a hidden id is accepted, filtered on read
	owner, title, n, hidden, ok := PlaylistBrief(id)
	uassert.True(t, ok)
	uassert.Equal(t, carol, owner)
	uassert.Equal(t, "Mixed", title)
	uassert.Equal(t, 2, n)
	uassert.False(t, hidden)
}

// LikedPage lists the newest tracks first.
func TestLikedPageNewestFirst(cur realm, t *testing.T) {
	reset()
	testing.SetRealm(testing.NewUserRealm(alice))
	RegisterArtist(cross(cur), "Likes Alice", "")
	a, b, c := publish(cur, "A"), publish(cur, "B"), publish(cur, "C")
	testing.SetRealm(testing.NewUserRealm(carol))
	Like(cross(cur), b)
	Like(cross(cur), a)
	Like(cross(cur), c)
	got := LikedPage(carol, 0, 10)
	uassert.Equal(t, 3, len(got))
	uassert.Equal(t, c, got[0])
	uassert.Equal(t, a, got[2])
}

// Narrow getters and migration pages.
func TestNarrowGettersAndPages(cur realm, t *testing.T) {
	reset()
	testing.SetRealm(testing.NewUserRealm(alice))
	aid := RegisterArtist(cross(cur), "Pages Alice", "")
	var ids []int
	for i := 0; i < 5; i++ {
		ids = append(ids, publish(cur, "P "+itoa(i)))
	}
	uassert.Equal(t, 5, ArtistTrackCount(aid))
	page := ArtistTrackPage(aid, 3, 10)
	uassert.Equal(t, 2, len(page))
	uassert.Equal(t, ids[3], page[0])
	uassert.Equal(t, 0, len(ArtistTrackPage(aid, 5, 10)))
	uassert.Equal(t, 0, ArtistTrackCount(999))
	name, verified, hidden, ok := ArtistBrief(aid)
	uassert.True(t, ok && name == "Pages Alice" && !verified && !hidden)
	_, _, _, ok = ArtistBrief(999)
	uassert.False(t, ok)

	testing.SetRealm(testing.NewUserRealm(carol))
	Like(cross(cur), ids[0])
	uassert.Equal(t, 0, len(UsersPage(0, 10))) // a like writes no listener record
	uassert.Equal(t, carol.String()+"/0", LikesPage(0, 10)[0])
	Follow(cross(cur), aid)
	uassert.Equal(t, 1, len(UsersPage(0, 10)))

	supporterTotal = store.NewMap(16)
	supporterTotal.Set(carol.String(), "7")
	addrs, totals := SupportersPage(0, 10)
	uassert.Equal(t, 1, len(addrs))
	uassert.Equal(t, carol.String(), addrs[0])
	uassert.Equal(t, int64(7), totals[0])
}

// Validated text goes out as plain JSON strings, accents and & included.
func TestPlainJSONStrings(cur realm, t *testing.T) {
	reset()
	testing.SetRealm(testing.NewUserRealm(alice))
	RegisterArtist(cross(cur), "Léa & Co", "")
	id := PublishTrack(cross(cur), "Café d'été", 2, "3:30", "cc by", "none", "", ipfs, "", "", "", "", "yes")
	js := TrackJSON(id)
	uassert.True(t, strings.Contains(js, `"title":"Café d'été"`), js)
	uassert.True(t, strings.Contains(js, `"artistName":"Léa & Co"`), js)
	uassert.Equal(t, `"x"`, text.Str("x"))
}

// Likes are kept per range of 512 track ids: a like rewrites one short list
// (never the listener's whole history), pages run across ranges newest
// first, and an emptied range is removed.
func TestLikesAcrossRanges(cur realm, t *testing.T) {
	reset()
	testing.SetRealm(testing.NewUserRealm(alice))
	RegisterArtist(cross(cur), "Ranges Alice", "")
	a := publish(cur, "First")
	nTracks = 1200 // ids up to 1200 pass the range check; only a is a real track
	k1, k2 := likeKey(carol, 600), likeKey(carol, 1100)
	likeSets.Set(k1, store.Pack([]int{520, 600}))
	likeSets.Set(k2, store.Pack([]int{1100}))
	testing.SetRealm(testing.NewUserRealm(carol))
	Like(cross(cur), a)
	l, _ := likeSets.Get(likeKey(carol, a))
	uassert.Equal(t, store.Pack([]int{a}), l) // only range 0 was written
	l, _ = likeSets.Get(k1)
	uassert.Equal(t, store.Pack([]int{520, 600}), l)

	got := LikedPage(carol, 0, 10)
	uassert.Equal(t, 4, len(got))
	uassert.Equal(t, 1100, got[0])
	uassert.Equal(t, 600, got[1])
	uassert.Equal(t, 520, got[2])
	uassert.Equal(t, a, got[3])
	got = LikedPage(carol, 2, 1)
	uassert.Equal(t, 1, len(got))
	uassert.Equal(t, 520, got[0])
	likes, _, _, _ := UserStats(carol)
	uassert.Equal(t, 4, likes)

	Unlike(cross(cur), a)
	uassert.False(t, likeSets.Has(likeKey(carol, a)))
	likes, _, _, _ = UserStats(carol)
	uassert.Equal(t, 3, likes)
	uassert.AbortsContains(t, cur, "not liked", func() { Unlike(cross(cur), a) })
}

// The named field indexes follow the record layouts (ArtistVerified gates tips).
func TestRecordFieldIndexes(t *testing.T) {
	a := artistRecord(&Artist{Hidden: true, Owner: alice, Name: "Named", Verified: true})
	uassert.Equal(t, "1", store.Field(a, aHidden))
	uassert.Equal(t, alice.String(), store.Field(a, aOwner))
	uassert.Equal(t, "Named", store.Field(a, aName))
	uassert.Equal(t, "1", store.Field(a, aVerified))
	tr := trackRecord(&Track{Artist: 7, Genre: 3, Duration: 99, Hidden: true, Title: "T", Likes: 5, Early: []address{bob}})
	uassert.Equal(t, "7", store.Field(tr, fArtist))
	uassert.Equal(t, "3", store.Field(tr, fGenre))
	uassert.Equal(t, "99", store.Field(tr, fDuration))
	uassert.Equal(t, "1", store.Field(tr, fHidden))
	uassert.Equal(t, "T", store.Field(tr, fTitle))
	uassert.Equal(t, "5", store.Field(tr, fLikes))
	uassert.Equal(t, bob.String(), store.Field(tr, fEarly))
}
