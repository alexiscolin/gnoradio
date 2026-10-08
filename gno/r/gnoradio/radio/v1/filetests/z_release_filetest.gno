// PKGPATH: gno.land/r/test/release
package release

// The admin renounced for good, then a new radio release takes over: this
// release becomes read-only and says which realm took over; the stations
// keep playing from the same data. Run apart from the unit tests, which
// need the admin and this release in force.

import (
	"strings"
	"testing"

	"gno.land/p/nt/testutils/v0"
	catalog "gno.land/r/gnoradio/catalog/v1"
	"gno.land/r/gnoradio/data"
	radio "gno.land/r/gnoradio/radio/v1"
)

const v2 = "gno.land/r/gnoradio/radio/v2"

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
	admin, alice, carol := radio.Admin(), testutils.TestAddress("alice"), testutils.TestAddress("carol")
	testing.SetRealm(testing.NewUserRealm(alice))
	catalog.RegisterArtist(cross(cur), "Alice", "")
	a := radio.PublishTrack(cross(cur), "Song", 2, "3:30", "cc by", "none", "", "ipfs://bafybeigdyrzt5sfp7udm7hu76uh7y26nf3efuylqabf3oclgtqy55fbzdi", "", "", "", "", "yes")
	b := radio.PublishTrack(cross(cur), "Other", 2, "2:30", "cc by", "none", "", "ipfs://bafybeigdyrzt5sfp7udm7hu76uh7y26nf3efuylqabf3oclgtqy55fbzdi", "", "", "", "", "yes")
	radio.Sync(cross(cur), 10)
	testing.SetRealm(testing.NewUserRealm(carol))
	radio.Queue(cross(cur), 2, b)

	// Renounce: no admin call works any more, for this release or the next
	// (the mirror says renounced).
	testing.SetRealm(testing.NewUserRealm(alice))
	fails("admin only", func() { radio.RenounceAdmin(cross(cur)) })
	testing.SetRealm(testing.NewUserRealm(admin))
	radio.RenounceAdmin(cross(cur))
	check(radio.Admin() == "", "no admin")
	v, ok := data.Get("radio/config", "admin")
	check(ok && v == "", "mirror says renounced")
	fails("admin only", func() { radio.DropSlot(cross(cur), 2, a) })
	fails("admin only", func() { radio.OfferAdmin(cross(cur), alice) })
	fails("nothing offered", func() { radio.AcceptAdmin(cross(cur)) })

	// Only a proposed realm says Ready.
	fails("only a proposed realm", func() { radio.Ready(cross(cur)) })

	// radio/v2 is proposed, says Ready, and takes over after the delay.
	check(!strings.Contains(radio.Render(""), "retired"), "in force")
	testing.SetRealm(testing.NewUserRealm(data.Owner()))
	data.Propose(cross(cur), "radio", v2)
	testing.SetRealm(testing.NewCodeRealm(v2))
	data.Ready(cross(cur))
	testing.SkipHeights(data.DELAY/5 + 1)
	check(strings.Contains(radio.Render(""), "the radio is now `"+v2+"`"), "Render says retired")
	testing.SetRealm(testing.NewUserRealm(alice))
	fails("only "+v2+" writes radio", func() { radio.Queue(cross(cur), 2, a) })
	// a track v2 published: the old Sync would ingest it, and may not write
	testing.SetRealm(testing.NewCodeRealm(v2))
	catalog.PublishFor(cross(cur), alice, "Later", 2, "2:30", "cc by", "none", "", "ipfs://bafybeigdyrzt5sfp7udm7hu76uh7y26nf3efuylqabf3oclgtqy55fbzdi", "", "", "", "", "yes")
	testing.SetRealm(testing.NewUserRealm(alice))
	fails("only "+v2+" writes radio", func() { radio.Sync(cross(cur), 10) })
	// Tips through the old radio are refused by the catalog: it is no longer
	// the radio writer.
	testing.SetRealm(testing.NewCodeRealm("gno.land/r/gnoradio/radio/v1"))
	fails("only the GnoRadio radio realm", func() { catalog.RadioTip(cross(cur), a, 0, alice, carol, "", 1) })
	// The data stays readable through the old rules: the stations play on.
	check(strings.Contains(radio.StationsJSON(), `"name":"Main"`), "reads go on")
	tracks, _, _ := radio.StationInfo(2)
	check(tracks == 2, "rotation kept")
	println("ok")
}

// Output:
// ok
