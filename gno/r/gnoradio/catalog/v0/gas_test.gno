package catalog

import (
	"strings"
	"testing"

	"gno.land/p/gnoradio/text/v0"

	"gno.land/p/nt/avl/v0"
	"gno.land/p/nt/uassert/v0"
)

// Playlists only check the id range and duplicates (no per-track load).
func TestPlaylistIDsRangeOnly(cur realm, t *testing.T) {
	reset()
	testing.SetRealm(testing.NewUserRealm(alice))
	RegisterArtist(cross(cur), "Range Alice", "")
	a, b := publish(cur, "One"), publish(cur, "Two")
	testing.SetRealm(testing.NewUserRealm(boss))
	HideTrack(cross(cur), b, true)

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

	testing.SetRealm(testing.NewUserRealm(carol))
	Like(cross(cur), ids[0])
	users := UsersPage(0, 10)
	uassert.True(t, len(users) >= 1)

	supporterTotal = avl.Tree{}
	supporterTotal.Set(carol.String(), int64(7))
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
