// PKGPATH: gno.land/r/gnoradio/gas
package gas

// Gas and deposit of one tickets v1 action (main) on 20 artists with
// 10 concerts each and 1000 free tickets, seeded by init through the same
// public calls as the measured baseline. Gas counts init too: compare with
// z_gas_v1_noop_large (main minus noop). Storage is main's alone.

import (
	"strconv"
	"testing"
	"time"

	"gno.land/p/nt/testutils/v0"
	catalog "gno.land/r/gnoradio/catalog/v1"
	tickets "gno.land/r/gnoradio/tickets/v1"
)

func artist(i int) address { return testutils.TestAddress("artist" + strconv.Itoa(i)) }
func fan(i int) address    { return testutils.TestAddress("fan" + strconv.Itoa(i)) }

func at(h int) string {
	return time.Now().Add(time.Duration(h) * time.Hour).UTC().Format("2006-01-02 15:04")
}

func init(cur realm) {
	for a := 0; a < 20; a++ {
		testing.SetRealm(testing.NewUserRealm(artist(a)))
		catalog.RegisterArtist(cross(cur), "Seed Artist "+strconv.Itoa(a), "")
		for e := 0; e < 10; e++ {
			tickets.CreateEvent(cross(cur), "Seed Show", "Seed Club", "", at(6+a+e*24), "0", 100)
		}
	}
	for f := 0; f < 1000; f++ {
		testing.SetRealm(testing.NewUserRealm(fan(f)))
		tickets.BuyTicket(cross(cur), 1+f%200)
	}
	testing.SetRealm(testing.NewUserRealm(testutils.TestAddress("newbie")))
	catalog.RegisterArtist(cross(cur), "New Artist", "")
}

func main(cur realm) {
	testing.SetRealm(testing.NewUserRealm(testutils.TestAddress("newfan")))
	tickets.BuyTicket(cross(cur), 1)
}

// Gas:
// 6476293991

// Storage:
// gno.land/r/gnoradio/catalog/v1: 0
// gno.land/r/gnoradio/data: 928
// gno.land/r/gnoradio/gas: 0
// gno.land/r/gnoradio/tickets/nft: 4155
// gno.land/r/gnoradio/tickets/v1: 0
