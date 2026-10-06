package tickets

import (
	"strings"
	"testing"

	"gno.land/p/nt/uassert/v0"
	"gno.land/p/nt/urequire/v0"

	"gno.land/r/gnoradio/catalog/v0"
)

func TestServiceFee(cur realm, t *testing.T) {
	reset()
	ensureArtist(cur, t)
	// Under gno test the catalog is initialised without an origin caller, so its
	// treasury is unset: the fee path must refuse rather than lose coins. The
	// treasury forwarding itself is covered by the catalog tests.
	treasury := catalog.Treasury()

	testing.SetRealm(testing.NewUserRealm(carol))
	uassert.AbortsWithMessage(t, cur, "tickets: moderators only", func() { SetServiceFee(cross(cur), 500_000) })
	testing.SetRealm(testing.NewUserRealm(bob))
	uassert.AbortsContains(t, cur, "between 0 and 10 GNOT", func() { SetServiceFee(cross(cur), 11_000_000) })
	SetServiceFee(cross(cur), 500_000)
	uassert.Equal(t, int64(500_000), ServiceFee())
	urequire.True(t, strings.Contains(FeesJSON(), `"serviceFee":500000,"treasury":"`+treasury.String()+`"`), FeesJSON())

	testing.SetRealm(testing.NewUserRealm(alice))
	paidID := CreateEvent(cross(cur), "Fee Party", "Club", "", inHours(48), "2", 10)
	freeID := CreateEvent(cross(cur), "Free Party", "Park", "", inHours(48), "0", 10)
	urequire.True(t, strings.Contains(EventsJSON(0, 10, true), `"fee":500000`))

	// Paid ticket with a fee: refused while the treasury is unset, nothing moves.
	testing.SetRealm(testing.NewUserRealm(carol))
	testing.SetOriginSend(ugnots(2_500_000))
	if !treasury.IsValid() {
		uassert.AbortsContains(t, cur, "treasury is not set", func() { BuyTicket(cross(cur), paidID) })
	}

	// Free tickets never carry the fee.
	testing.SetOriginSend(nil)
	BuyTicket(cross(cur), freeID)

	// Without a fee, the buyer attaches exactly the price, all of it to the artist.
	testing.SetRealm(testing.NewUserRealm(bob))
	SetServiceFee(cross(cur), 0)
	urequire.True(t, strings.Contains(EventsJSON(0, 10, true), `"fee":0`))
	a0 := balance(alice)
	testing.IssueCoins(realmAddr, ugnots(2_000_000))
	testing.SetOriginSend(ugnots(2_000_000))
	testing.SetRealm(testing.NewUserRealm(carol))
	BuyTicket(cross(cur), paidID)
	uassert.Equal(t, a0+2_000_000, balance(alice))
	uassert.Equal(t, int64(0), balance(realmAddr))
	testing.SetOriginSend(nil)

}
