// PKGPATH: gno.land/r/test/release
package release

// The admin renounced for good, then a new catalog release takes over: this
// release becomes read-only, says so, and points to its successor. Run apart
// from the unit tests, which need the admin and this release in force.

import (
	"strings"
	"testing"

	"gno.land/p/nt/testutils/v0"
	catalog "gno.land/r/gnoradio/catalog/v1"
	"gno.land/r/gnoradio/data"
)

const v2 = "gno.land/r/gnoradio/catalog/v2"

func check(ok bool, what string) {
	if !ok {
		println("FAIL:", what)
	}
}

func fails(want string, fn func()) {
	r := revive(fn)
	s, _ := r.(string)
	if !strings.Contains(s, want) {
		println("FAIL: want abort", want, "got", s)
	}
}

func main(cur realm) {
	admin, alice := catalog.Admin(), testutils.TestAddress("alice")
	testing.SetRealm(testing.NewUserRealm(alice))
	aid := catalog.RegisterArtist(cross(cur), "Alice", "")
	testing.SetRealm(testing.NewCodeRealm("gno.land/r/gnoradio/radio/v1")) // radio.PublishTrack does this
	id := catalog.PublishFor(cross(cur), alice, "Song", 2, "3:30", "cc by", "none", "", "ipfs://bafybeigdyrzt5sfp7udm7hu76uh7y26nf3efuylqabf3oclgtqy55fbzdi", "", "", "", "", "yes")

	// Renounce: no admin call works any more, for this release or the next
	// (the mirror says renounced).
	testing.SetRealm(testing.NewUserRealm(alice))
	fails("admin only", func() { catalog.RenounceAdmin(cross(cur)) })
	testing.SetRealm(testing.NewUserRealm(admin))
	catalog.RenounceAdmin(cross(cur))
	check(catalog.Admin() == "", "no admin")
	v, ok := data.Get("catalog/config", "admin")
	check(ok && v == "", "mirror says renounced")
	fails("admin only", func() { catalog.HideTrack(cross(cur), id, true, "copyright notice") })
	fails("admin only", func() { catalog.OfferAdmin(cross(cur), alice) })
	fails("nothing offered", func() { catalog.AcceptAdmin(cross(cur)) })

	// Only a proposed realm says Ready.
	fails("only a proposed realm", func() { catalog.Ready(cross(cur)) })

	// catalog/v2 is proposed, says Ready, and takes over after the delay.
	testing.SetRealm(testing.NewUserRealm(data.Owner()))
	data.Propose(cross(cur), "catalog", v2)
	testing.SetRealm(testing.NewCodeRealm(v2))
	data.Ready(cross(cur))
	testing.SkipHeights(data.DELAY/5 + 1)
	check(strings.Contains(catalog.Info(), `"current":"`+v2+`"`), "Info names the successor")
	check(strings.Contains(catalog.Render(""), "retired"), "Render says retired")
	testing.SetRealm(testing.NewUserRealm(testutils.TestAddress("carol")))
	fails("only "+v2+" writes catalog", func() { catalog.Like(cross(cur), id) })
	testing.SetRealm(testing.NewUserRealm(alice))
	fails("only "+v2+" writes catalog", func() { catalog.RegisterArtist(cross(cur), "Alice B", "") })
	// The data stays readable through the old rules.
	check(strings.Contains(catalog.TrackJSON(id), `"title":"Song"`), "reads go on")
	check(catalog.ArtistOf(alice) == aid, "artist kept")
	println("ok")
}

// Output:
// ok
