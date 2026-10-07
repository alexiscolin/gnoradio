package catalog

import (
	"chain"
	"testing"

	"gno.land/p/nt/uassert/v0"
)

// Y2: five open reports per reporter; resolving one frees a slot.
func TestReportCapAndResolve(cur realm, t *testing.T) {
	reset()
	testing.SetRealm(testing.NewUserRealm(alice))
	RegisterArtist(cross(cur), "Alice", "")
	id := publish(cur, "Song")
	testing.SetRealm(testing.NewUserRealm(carol))
	for i := 0; i < maxUserReports; i++ {
		Report(cross(cur), "track", id, "broken link")
	}
	uassert.AbortsContains(t, cur, "open reports", func() { Report(cross(cur), "track", id, "broken link") })
	uassert.AbortsWithMessage(t, cur, "catalog: admin only", func() { ResolveReport(cross(cur), 1) })

	testing.SetRealm(testing.NewUserRealm(boss))
	ResolveReport(cross(cur), 1)
	uassert.Equal(t, maxUserReports-1, openReports)
	_, ok := GetReport(1)
	uassert.False(t, ok)
	uassert.AbortsContains(t, cur, "unknown report", func() { ResolveReport(cross(cur), 1) })

	testing.SetRealm(testing.NewUserRealm(carol))
	Report(cross(cur), "track", id, "broken link")
	uassert.Equal(t, 6, nReports)
}

// Y3: renaming frees the old name, look-alikes collide, hidden artists are stuck.
func TestNameSkeletonAndRename(cur realm, t *testing.T) {
	reset()
	uassert.Equal(t, "beyonce", skeleton("BEYONCÉ"))
	uassert.Equal(t, "beyonce", skeleton("Ｂｅｙｏｎｃｅ"))
	uassert.False(t, validName("Ｂｅｙｏｎｃｅ"))
	uassert.False(t, validName("Bеyonce")) // Cyrillic e
	uassert.False(t, validName("A×B"))
	uassert.True(t, validName("Beyoncé & Ñu"))

	testing.SetRealm(testing.NewUserRealm(alice))
	RegisterArtist(cross(cur), "Beyonce", "")
	testing.SetRealm(testing.NewUserRealm(bob))
	uassert.AbortsContains(t, cur, "already taken", func() { RegisterArtist(cross(cur), "BEYONCÉ", "") })
	RegisterArtist(cross(cur), "Bob", "")

	testing.SetRealm(testing.NewUserRealm(alice))
	RegisterArtist(cross(cur), "Alice", "")
	uassert.Equal(t, 0, ArtistByName("Beyonce"))
	testing.SetRealm(testing.NewUserRealm(carol))
	uassert.Equal(t, 3, RegisterArtist(cross(cur), "Beyoncé", ""))
	uassert.Equal(t, 3, ArtistByName("BEYONCE"))

	testing.SetRealm(testing.NewUserRealm(boss))
	HideArtist(cross(cur), 3, true)
	testing.SetRealm(testing.NewUserRealm(carol))
	uassert.AbortsContains(t, cur, "hidden artist cannot", func() { RegisterArtist(cross(cur), "Carol", "") })
	RegisterArtist(cross(cur), "BEYONCÉ", "") // same name, new spelling: allowed

	testing.SetRealm(testing.NewUserRealm(boss))
	uassert.AbortsContains(t, cur, "visible artist", func() { ReleaseName(cross(cur), "bob") })
	uassert.AbortsContains(t, cur, "not reserved", func() { ReleaseName(cross(cur), "nobody") })
	ReleaseName(cross(cur), "beyonce")
	testing.SetRealm(testing.NewUserRealm(dave))
	RegisterArtist(cross(cur), "Beyonce", "")
}

// Y4: like, unlike, like again does not take a second early badge.
func TestEarlyBadgeNoDuplicate(cur realm, t *testing.T) {
	reset()
	testing.SetRealm(testing.NewUserRealm(alice))
	RegisterArtist(cross(cur), "Alice", "")
	id := publish(cur, "Song")
	testing.SetRealm(testing.NewUserRealm(carol))
	Like(cross(cur), id)
	Unlike(cross(cur), id)
	Like(cross(cur), id)
	uassert.Equal(t, 1, len(getTrack(id).Early))
}

// Y7: the treasury cannot be a GnoRadio realm.
func TestTreasuryNotARealm(cur realm, t *testing.T) {
	reset()
	testing.SetRealm(testing.NewUserRealm(boss))
	for _, a := range []address{realmAddr, chain.PackageAddress("gno.land/r/gnoradio/radio/v0"),
		chain.PackageAddress("gno.land/r/gnoradio/tickets/v0"), chain.PackageAddress("gno.land/r/gnoradio/home/v0")} {
		uassert.AbortsContains(t, cur, "cannot be a GnoRadio realm", func() { SetTreasury(cross(cur), a) })
	}
	SetTreasury(cross(cur), dave)
	uassert.Equal(t, dave, Treasury())
}

// Names, titles and bios refuse slurs but not strong words (real works).
func TestSlurs(cur realm, t *testing.T) {
	reset()
	testing.SetRealm(testing.NewUserRealm(alice))
	uassert.AbortsContains(t, cur, "name holds a slur", func() { RegisterArtist(cross(cur), "Heil Hitler", "") })
	uassert.AbortsContains(t, cur, "bio holds a slur", func() { RegisterArtist(cross(cur), "Alice", "f4ggots out") })
	RegisterArtist(cross(cur), "Sex Pistols", "Bitches Brew and Fuck tha Police")
	uassert.AbortsContains(t, cur, "title holds a slur", func() { publish(cur, "Nigger Kills") })
	publish(cur, "Anarchy in the UK")
}
