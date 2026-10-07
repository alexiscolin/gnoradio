package catalog

import (
	"strings"
	"testing"

	"gno.land/p/nt/uassert/v0"
)

// The batched readers return a whole page in one query and skip hidden items.
func TestBatchedReaders(cur realm, t *testing.T) {
	reset()
	testing.SetRealm(testing.NewUserRealm(alice))
	RegisterArtist(cross(cur), "Batch Alice", "")
	testing.SetRealm(testing.NewUserRealm(bob))
	RegisterArtist(cross(cur), "Batch Bob", "")
	testing.SetRealm(testing.NewUserRealm(carol))
	RegisterArtist(cross(cur), "Batch Carol", "")
	testing.SetRealm(testing.NewUserRealm(boss))
	HideArtist(cross(cur), 2, true, "test hide")

	all := ArtistsJSON(0, 100)
	uassert.True(t, strings.HasPrefix(all, `{"total":3,"artists":[`))
	uassert.True(t, strings.Contains(all, `"Batch Alice"`))
	uassert.False(t, strings.Contains(all, `"Batch Bob"`))
	uassert.True(t, strings.Contains(all, `"Batch Carol"`))

	page := ArtistsJSON(2, 1) // only id 3
	uassert.False(t, strings.Contains(page, `"Batch Alice"`))
	uassert.True(t, strings.Contains(page, `"Batch Carol"`))
	uassert.Equal(t, `{"total":3,"artists":[]}`, ArtistsJSON(10, 5))
	uassert.Equal(t, `{"total":0,"playlists":[]}`, PlaylistsJSON(0, 1000))
}

// A name needs a letter or digit: punctuation alone would reserve an empty key.
func TestNameNeedsALetter(cur realm, t *testing.T) {
	uassert.False(t, validName("--"))
	uassert.False(t, validName(". ."))
	uassert.True(t, validName("A-ha"))
	uassert.True(t, validName("Simon & Garfunkel"))
}
