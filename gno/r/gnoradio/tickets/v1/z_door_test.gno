package tickets

// This file runs last: its concerts end and its clock skips would shift the
// time-based counts of the other tests.

import (
	"strings"
	"testing"

	"gno.land/p/nt/uassert/v0"
	catalog "gno.land/r/gnoradio/catalog/v1"
	"gno.land/r/gnoradio/data"
)

// M5: a door QR is built from public data, so CheckIn needs the holder's own
// Present from their wallet within the last 10 minutes. L1: no check-in, and
// no Present, once the concert is over.
func TestPresentThenCheckIn(cur realm, t *testing.T) {
	alice, _ := artist(cur, "Door Alice")
	carol, dave := who("carol"), who("dave")
	testing.SetRealm(testing.NewUserRealm(alice))
	eid := CreateEvent(cross(cur), "Door Night", "Lyon", "", inHours(20), "0", 10)
	testing.SetRealm(testing.NewUserRealm(carol))
	tid := BuyTicket(cross(cur), eid)
	testing.SetRealm(testing.NewUserRealm(dave))
	other := BuyTicket(cross(cur), eid)

	// Not before the door opens, never for someone else's ticket, never by a realm.
	testing.SetRealm(testing.NewUserRealm(carol))
	uassert.AbortsContains(t, cur, "12h before", func() { Present(cross(cur), tid, "4821") })
	testing.SkipHeights(9 * 720) // 9 hours: the door is open
	uassert.AbortsContains(t, cur, "do not hold", func() { Present(cross(cur), other, "4821") })
	uassert.AbortsContains(t, cur, "unknown ticket", func() { Present(cross(cur), TicketCount()+1, "4821") })
	testing.SetRealm(testing.NewCodeRealm("gno.land/r/evil/proxy"))
	uassert.AbortsContains(t, cur, "directly from your wallet", func() { Present(cross(cur), tid, "4821") })

	// The forged QR: the artist scans a ticket its holder never presented.
	testing.SetRealm(testing.NewUserRealm(alice))
	uassert.AbortsContains(t, cur, "present this ticket", func() { CheckIn(cross(cur), tid, "4821") })
	uassert.Equal(t, int64(0), PresentedAt(tid, "4821"))

	testing.SetRealm(testing.NewUserRealm(carol))
	Present(cross(cur), tid, "4821")
	at := PresentedAt(tid, "4821")
	uassert.True(t, at > 0)
	testing.SkipHeights(11 * 12) // 11 minutes: too old
	testing.SetRealm(testing.NewUserRealm(alice))
	uassert.AbortsContains(t, cur, "present this ticket", func() { CheckIn(cross(cur), tid, "4821") })

	// A Present by a former holder does not count for the new one.
	testing.SetRealm(testing.NewUserRealm(carol))
	Present(cross(cur), tid, "4821")
	TransferTicket(cross(cur), dave, tid)
	uassert.Equal(t, int64(0), PresentedAt(tid, "4821"))
	testing.SetRealm(testing.NewUserRealm(alice))
	uassert.AbortsContains(t, cur, "present this ticket", func() { CheckIn(cross(cur), tid, "4821") })

	// Y1: the holder's Present carries the code the door showed them; a
	// stranger with a copied QR is shown another code, which admits nobody.
	testing.SetRealm(testing.NewUserRealm(dave))
	uassert.AbortsContains(t, cur, "4 to 8 digits", func() { Present(cross(cur), tid, "12a4") })
	uassert.AbortsContains(t, cur, "4 to 8 digits", func() { Present(cross(cur), tid, "") })
	Present(cross(cur), tid, "4821")
	uassert.Equal(t, int64(0), PresentedAt(tid, "1111"))
	testing.SetRealm(testing.NewUserRealm(alice))
	uassert.AbortsContains(t, cur, "with this door code", func() { CheckIn(cross(cur), tid, "1111") })
	testing.SkipHeights(9 * 12) // 9 minutes: still fresh
	testing.SetRealm(testing.NewUserRealm(alice))
	CheckIn(cross(cur), tid, "4821")
	tk, _ := TicketInfo(tid)
	uassert.True(t, tk.Attended)
	uassert.Equal(t, int64(0), PresentedAt(tid, "4821")) // used up
	testing.SetRealm(testing.NewUserRealm(dave))
	uassert.AbortsContains(t, cur, "already checked in", func() { Present(cross(cur), tid, "4821") })

	// L1: 12 hours after the start the door is closed.
	Present(cross(cur), other, "4821")
	testing.SkipHeights(24 * 720)
	uassert.AbortsContains(t, cur, "concert is over", func() { Present(cross(cur), other, "4821") })
	testing.SetRealm(testing.NewUserRealm(alice))
	uassert.AbortsContains(t, cur, "concert is over", func() { CheckIn(cross(cur), other, "4821") })
}

// M4: an upper-case recipient is the same account under another string: it
// is refused, so no ticket is stored under a key nobody signs as.
func TestTransferUpperCase(cur realm, t *testing.T) {
	alice, _ := artist(cur, "Case Alice")
	carol, dave := who("carol"), who("dave")
	testing.SetRealm(testing.NewUserRealm(alice))
	eid := CreateEvent(cross(cur), "Case Night", "Lyon", "", inHours(30), "0", 10)
	testing.SetRealm(testing.NewUserRealm(carol))
	tid := BuyTicket(cross(cur), eid)
	for _, to := range []address{address(strings.ToUpper(dave.String())), address(strings.ToUpper(carol.String())),
		address(strings.ToUpper(realmAddr.String()))} {
		uassert.AbortsContains(t, cur, "invalid recipient", func() { TransferTicket(cross(cur), to, tid) })
	}
	testing.SetRealm(testing.NewUserRealm(boss))
	uassert.AbortsContains(t, cur, "not an address", func() { OfferAdmin(cross(cur), address(strings.ToUpper(dave.String()))) })
}

// L35: sales close at the start; a fee with no treasury is not charged;
// hiding an unknown concert fails.
func TestSaleGuards(cur realm, t *testing.T) {
	alice, aid := artist(cur, "Guard Alice")
	verify(cur, aid, true)
	testing.SetRealm(testing.NewUserRealm(alice))
	soon := CreateEvent(cross(cur), "Soon Show", "Club", "", inHours(1), "0", 10)
	paid := CreateEvent(cross(cur), "Paid Show", "Club", "", inHours(48), "1", 10)

	fee(cur, 100_000)
	old := catalog.Treasury()
	testing.SetRealm(testing.NewCodeRealm("gno.land/r/gnoradio/catalog/v1"))
	data.Set(cross(cur), "catalog/config", "treasury", "")
	testing.SetRealm(testing.NewUserRealm(who("carol")))
	uassert.Equal(t, int64(0), ServiceFee()) // nowhere to go: not asked
	testing.SetOriginSend(ugnots(1_100_000))
	uassert.AbortsContains(t, cur, "attach exactly 1 GNOT", func() { BuyTicket(cross(cur), paid) })
	a0 := balance(alice)
	testing.IssueCoins(realmAddr, ugnots(1_000_000))
	testing.SetOriginSend(ugnots(1_000_000))
	BuyTicket(cross(cur), paid)
	uassert.Equal(t, a0+1_000_000, balance(alice))
	testing.SetOriginSend(nil)
	testing.SetRealm(testing.NewCodeRealm("gno.land/r/gnoradio/catalog/v1"))
	data.Set(cross(cur), "catalog/config", "treasury", old.String())
	fee(cur, 0)

	testing.SkipHeights(2 * 720)
	testing.SetRealm(testing.NewUserRealm(who("dave")))
	uassert.AbortsContains(t, cur, "sales are closed", func() { BuyTicket(cross(cur), soon) })

	testing.SetRealm(testing.NewUserRealm(boss))
	uassert.AbortsWithMessage(t, cur, "tickets: unknown concert", func() { HideEvent(cross(cur), EventCount()+1, true, "spam spam") })
}
