package catalog

import (
	"chain"
	"chain/runtime"
	"testing"

	"gno.land/p/nt/uassert/v0"
)

// Y2: five open reports per reporter; resolving one frees a slot.
func TestReportCapAndResolve(cur realm, t *testing.T) {
	alice, _ := artist(cur, "alice")
	carol := who("carol")
	id := publish(cur, alice, "Song")
	open := ReportCount()
	testing.SetRealm(testing.NewUserRealm(carol))
	for i := 0; i < maxUserReports; i++ {
		Report(cross(cur), "track", id, "broken link")
	}
	uassert.AbortsContains(t, cur, "open reports", func() { Report(cross(cur), "track", id, "broken link") })
	rid := ReportPage(0, 1)[0]
	uassert.AbortsWithMessage(t, cur, "catalog: admin only", func() { ResolveReport(cross(cur), rid) })

	testing.SetRealm(testing.NewUserRealm(boss))
	ResolveReport(cross(cur), rid)
	uassert.Equal(t, open+maxUserReports-1, ReportCount())
	_, ok := GetReport(rid)
	uassert.False(t, ok)
	uassert.AbortsContains(t, cur, "unknown report", func() { ResolveReport(cross(cur), rid) })

	testing.SetRealm(testing.NewUserRealm(carol))
	Report(cross(cur), "track", id, "broken link")
	uassert.Equal(t, rid+1, ReportPage(0, 1)[0])
}

// Y3: renaming frees the old name, look-alikes collide, hidden artists are stuck.
func TestNameSkeletonAndRename(cur realm, t *testing.T) {
	uassert.Equal(t, "beyonce", skeleton("BEYONCÉ"))
	uassert.Equal(t, "beyonce", skeleton("Ｂｅｙｏｎｃｅ"))
	uassert.False(t, validName("Ｂｅｙｏｎｃｅ"))
	uassert.False(t, validName("Bеyonce")) // Cyrillic e
	uassert.False(t, validName("A×B"))
	uassert.True(t, validName("Beyoncé & Ñu"))

	alice, bob, carol, dave := who("alice"), who("bob"), who("carol"), who("dave")
	testing.SetRealm(testing.NewUserRealm(alice))
	RegisterArtist(cross(cur), "Beyonce", "")
	testing.SetRealm(testing.NewUserRealm(bob))
	uassert.AbortsContains(t, cur, "already taken", func() { RegisterArtist(cross(cur), "BEYONCÉ", "") })
	bobName := name("Bob")
	RegisterArtist(cross(cur), bobName, "")

	testing.SetRealm(testing.NewUserRealm(alice))
	RegisterArtist(cross(cur), name("Alice"), "")
	uassert.Equal(t, 0, ArtistByName("Beyonce"))
	testing.SetRealm(testing.NewUserRealm(carol))
	c := RegisterArtist(cross(cur), "Beyoncé", "")
	uassert.Equal(t, c, ArtistByName("BEYONCE"))

	testing.SetRealm(testing.NewUserRealm(boss))
	HideArtist(cross(cur), c, true, "impersonation")
	testing.SetRealm(testing.NewUserRealm(carol))
	uassert.AbortsContains(t, cur, "hidden artist cannot", func() { RegisterArtist(cross(cur), name("Carol"), "") })
	RegisterArtist(cross(cur), "BEYONCÉ", "") // same name, new spelling: allowed

	testing.SetRealm(testing.NewUserRealm(boss))
	uassert.AbortsContains(t, cur, "visible artist", func() { ReleaseName(cross(cur), bobName) })
	uassert.AbortsContains(t, cur, "not reserved", func() { ReleaseName(cross(cur), "nobody at all") })
	ReleaseName(cross(cur), "beyonce")
	testing.SetRealm(testing.NewUserRealm(dave))
	RegisterArtist(cross(cur), "Beyonce", "")
}

// Y4: like, unlike, like again does not take a second early badge.
func TestEarlyBadgeNoDuplicate(cur realm, t *testing.T) {
	alice, _ := artist(cur, "alice")
	carol := who("carol")
	id := publish(cur, alice, "Song")
	testing.SetRealm(testing.NewUserRealm(carol))
	Like(cross(cur), id)
	Unlike(cross(cur), id)
	Like(cross(cur), id)
	uassert.Equal(t, 1, len(getTrack(rd(), id).Early))
}

// Y7: the treasury cannot be a GnoRadio realm: this one, any writer, the
// data realm or the ticket NFT realm.
func TestTreasuryNotARealm(cur realm, t *testing.T) {
	dave := who("dave")
	testing.SetRealm(testing.NewUserRealm(boss))
	for _, p := range []string{"gno.land/r/gnoradio/catalog/v1", "gno.land/r/gnoradio/radio/v1", "gno.land/r/gnoradio/tickets/v1",
		"gno.land/r/gnoradio/home/v1", "gno.land/r/gnoradio/data", "gno.land/r/gnoradio/tickets/nft"} {
		uassert.AbortsContains(t, cur, "cannot be a GnoRadio realm", func() { SetTreasury(cross(cur), chain.PackageAddress(p)) })
	}
	old := Treasury()
	SetTreasury(cross(cur), dave)
	uassert.Equal(t, dave, Treasury())
	SetTreasury(cross(cur), old)
}

// Names, titles and bios refuse slurs but not strong words (real works).
func TestSlurs(cur realm, t *testing.T) {
	alice := who("alice")
	testing.SetRealm(testing.NewUserRealm(alice))
	uassert.AbortsContains(t, cur, "name holds a slur", func() { RegisterArtist(cross(cur), "Heil Hitler", "") })
	uassert.AbortsContains(t, cur, "bio holds a slur", func() { RegisterArtist(cross(cur), name("Alice"), "f4ggots out") })
	RegisterArtist(cross(cur), "Sex Pistols", "Bitches Brew and Fuck tha Police")
	uassert.AbortsContains(t, cur, "title holds a slur", func() {
		PublishTrack(cross(cur), "Nigger Kills", 2, "3:30", "cc by", "none", "", ipfs, "", "", "", "", "yes")
	})
	PublishTrack(cross(cur), "Anarchy in the UK", 2, "3:30", "cc by", "none", "", ipfs, "", "", "", "", "yes")
}

// Tracks are added and edited only through the radio writer, which puts them
// on the air: a wallet, another realm, a MsgRun or a retired radio cannot
// call PublishFor, ImportFor or EditFor (a MsgRun runs as a gno.land/e/ realm:
// not the radio writer either), so none can publish for another
// address either.
func TestTrackWritesRadioOnly(cur realm, t *testing.T) {
	alice, aid := artist(cur, "alice")
	id := publish(cur, alice, "Song")
	for _, r := range []runtime.Realm{testing.NewUserRealm(alice), testing.NewUserRealm(boss),
		testing.NewCodeRealm("gno.land/r/evil/proxy"),
		testing.NewCodeRealm("gno.land/r/gnoradio/radio/v0"), testing.NewCodeRealm(radioPath() + "/evil")} {
		testing.SetRealm(r)
		uassert.AbortsContains(t, cur, "only the GnoRadio radio realm", func() {
			PublishFor(cross(cur), alice, "Forged", 2, "3:30", "cc by", "none", "", ipfs, "", "", "", "", "yes")
		})
		uassert.AbortsContains(t, cur, "only the GnoRadio radio realm", func() {
			ImportFor(cross(cur), boss, aid, "Forged", 2, "3:30", "CC-BY-4.0", "", ipfs, "", "", "", "https://example.org/x", "Someone")
		})
		uassert.AbortsContains(t, cur, "only the GnoRadio radio realm", func() {
			EditFor(cross(cur), alice, id, "Forged", 2, "3:30", "", ipfs, "", "", "")
		})
	}
	// The radio names who signed: only the admin imports.
	testing.SetRealm(testing.NewUserRealm(alice))
	uassert.AbortsContains(t, cur, "admin only", func() {
		ImportTrack(cross(cur), aid, "Forged", 2, "3:30", "CC-BY-4.0", "", ipfs, "", "", "", "https://example.org/x", "Someone")
	})
	uassert.Equal(t, "Song", mustTrack(rd(), id).Title)
}
