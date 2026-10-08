package catalog

import (
	"strings"
	"testing"

	"gno.land/p/gnoradio/text/v0"
	"gno.land/p/nt/uassert/v0"
)

// The batched readers return a whole page in one query and skip hidden items.
func TestBatchedReaders(cur realm, t *testing.T) {
	an, bn, cn := name("Batch Alice"), name("Batch Bob"), name("Batch Carol")
	testing.SetRealm(testing.NewUserRealm(who("alice")))
	a := RegisterArtist(cross(cur), an, "")
	testing.SetRealm(testing.NewUserRealm(who("bob")))
	b := RegisterArtist(cross(cur), bn, "")
	testing.SetRealm(testing.NewUserRealm(who("carol")))
	c := RegisterArtist(cross(cur), cn, "")
	testing.SetRealm(testing.NewUserRealm(boss))
	HideArtist(cross(cur), b, true, "test hide")

	n := ArtistCount()
	all := ArtistsJSON(a-1, 3)
	uassert.True(t, strings.HasPrefix(all, `{"total":`+text.Itoa(n)+`,"artists":[`))
	uassert.True(t, strings.Contains(all, `"`+an+`"`))
	uassert.False(t, strings.Contains(all, `"`+bn+`"`))
	uassert.True(t, strings.Contains(all, `"`+cn+`"`))

	page := ArtistsJSON(c-1, 1) // only c
	uassert.False(t, strings.Contains(page, `"`+an+`"`))
	uassert.True(t, strings.Contains(page, `"`+cn+`"`))
	uassert.Equal(t, `{"total":`+text.Itoa(n)+`,"artists":[]}`, ArtistsJSON(n+10, 5))
	uassert.True(t, strings.HasPrefix(PlaylistsJSON(PlaylistCount(), 1000), `{"total":`+text.Itoa(PlaylistCount())+`,"playlists":[]}`))
}

// A name needs a letter or digit: punctuation alone would reserve an empty key.
func TestNameNeedsALetter(t *testing.T) {
	uassert.False(t, validName("--"))
	uassert.False(t, validName(". ."))
	uassert.True(t, validName("A-ha"))
	uassert.True(t, validName("Simon & Garfunkel"))
}
