// PKGPATH: gno.land/r/test/release
package release

// A new tickets release takes over: this one refuses writes, says it is
// retired, keeps its reads and still reports the admin from the data
// realm's mirror. Run apart from the unit tests, which need this release.

import (
	"strings"
	"testing"

	"gno.land/p/nt/testutils/v0"
	catalog "gno.land/r/gnoradio/catalog/v1"
	"gno.land/r/gnoradio/data"
	tickets "gno.land/r/gnoradio/tickets/v1"
)

const v2 = "gno.land/r/gnoradio/tickets/v2"

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
	admin, alice := tickets.Admin(), testutils.TestAddress("alice")
	testing.SetRealm(testing.NewUserRealm(alice))
	catalog.RegisterArtist(cross(cur), "Alice", "")
	id := tickets.CreateEvent(cross(cur), "Release Night", "Somewhere", "", "2027-03-01 20:00", "0", 10)

	fails("only a proposed realm", func() { tickets.Ready(cross(cur)) })
	testing.SetRealm(testing.NewUserRealm(data.Owner()))
	data.Propose(cross(cur), "tickets", v2)
	testing.SetRealm(testing.NewCodeRealm(v2))
	data.Ready(cross(cur))
	testing.SkipHeights(data.DELAY/5 + 1)

	check(strings.Contains(tickets.Render(""), "retired"), "Render says retired")
	testing.SetRealm(testing.NewUserRealm(alice))
	fails("only "+v2+" writes tickets", func() {
		tickets.CreateEvent(cross(cur), "After", "Somewhere", "", "2027-03-02 20:00", "0", 10)
	})
	fails("only "+v2+" writes tickets", func() { tickets.CancelEvent(cross(cur), id) })
	e, ok := tickets.EventInfo(id)
	check(ok && e.Title == "Release Night", "reads go on")
	check(tickets.Admin() == admin, "admin read from the mirror")
	println("ok")
}

// Output:
// ok
