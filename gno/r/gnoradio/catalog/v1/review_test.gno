package catalog

import (
	"strings"
	"testing"

	"gno.land/p/gnoradio/text/v0"
	"gno.land/p/nt/uassert/v0"
	"gno.land/r/gnoradio/data"
)

// A pause of the catalog role in the data realm stops every write, undo
// actions and reports included, and no read. (It replaces v0's Freeze.)
func TestPauseCoversEveryWrite(cur realm, t *testing.T) {
	alice, aid := artist(cur, "alice")
	carol := who("carol")
	id := publish(cur, alice, "Ice")
	testing.SetRealm(testing.NewUserRealm(carol))
	Like(cross(cur), id)
	Follow(cross(cur), aid)

	pause(cur, true)
	testing.SetRealm(testing.NewUserRealm(carol))
	uassert.AbortsContains(t, cur, "catalog is paused", func() { Unlike(cross(cur), id) })
	uassert.AbortsContains(t, cur, "catalog is paused", func() { Unfollow(cross(cur), aid) })
	uassert.AbortsContains(t, cur, "catalog is paused", func() { Report(cross(cur), "track", id, "broken link") })
	uassert.AbortsContains(t, cur, "catalog is paused", func() { RegisterArtist(cross(cur), name("Carol"), "") })
	testing.SetRealm(testing.NewUserRealm(boss))
	uassert.AbortsContains(t, cur, "catalog is paused", func() { HideTrack(cross(cur), id, true, "copyright notice") })
	uassert.True(t, strings.Contains(TrackJSON(id), `"likes":1`))
	uassert.Equal(t, id, LikedPage(carol, 0, 1)[0])

	pause(cur, false)
	testing.SetRealm(testing.NewUserRealm(carol))
	Unlike(cross(cur), id)
	Unfollow(cross(cur), aid)
	uassert.False(t, strings.Contains(data.Writers(), `"paused":true`))
}

// JSON strings are escaped even if a validator is loosened one day.
func TestJSONEscaping(t *testing.T) {
	// text.Str() writes JSON without escaping, so the validators must refuse these.
	for _, bad := range []string{`a"b`, `a\b`, "a\nb", "a\x01b"} {
		uassert.False(t, text.Valid(bad, 0, 100))
		uassert.False(t, validName(bad))
	}
}

// Spacing, punctuation and look-alike characters cannot fake a name.
func TestSkeletonConfusables(cur realm, t *testing.T) {
	uassert.False(t, validName("Daft  Punk"))
	uassert.False(t, validName(" Daft Punk"))
	uassert.False(t, validName("Daft Punk "))
	uassert.True(t, validName("Daft Punk"))
	same := skeleton("Daft Punk")
	for _, s := range []string{"DAFT PUNK", "DaftPunk", "Daft-Punk", "Daft.Punk", "Daft Punk&"} {
		uassert.Equal(t, same, skeleton(s), s)
	}
	uassert.Equal(t, skeleton("Lil Nas"), skeleton("1il Nas"))
	uassert.Equal(t, skeleton("Lil Nas"), skeleton("LIL NAS"))
	uassert.Equal(t, skeleton("Bjorn"), skeleton("Bjom"))
	uassert.Equal(t, skeleton("Kool"), skeleton("K00l"))

	testing.SetRealm(testing.NewUserRealm(who("alice")))
	RegisterArtist(cross(cur), "Daft Punk", "")
	testing.SetRealm(testing.NewUserRealm(who("bob")))
	uassert.AbortsContains(t, cur, "already taken", func() { RegisterArtist(cross(cur), "Daft-Punk", "") })
	uassert.AbortsContains(t, cur, "already taken", func() { RegisterArtist(cross(cur), "DAFT PUNK", "") })
}

func TestRenderPointsHome(t *testing.T) {
	uassert.True(t, strings.Contains(Render(""), "(/r/gnoradio/home/v1)"))
	uassert.False(t, strings.Contains(Render(""), "retired"))
}
