package tickets

import (
	"strings"
	"testing"

	"gno.land/p/nt/uassert/v0"
	"gno.land/p/nt/urequire/v0"
)

// Ported from tickets v0 (seams replaced by the catalog's real Verify and
// HideArtist).

func TestCreateAndBuy(cur realm, t *testing.T) {
	fee(cur, 0)
	alice, aid := artist(cur, "Tickets Alice")
	verify(cur, aid, true)
	carol := who("carol")
	testing.SetRealm(testing.NewUserRealm(alice))
	eid := CreateEvent(cross(cur), "Release Party", "La Station, Paris", "https://live.example.org/watch?v=abc_1", inHours(72), "2.5", 2)
	uassert.AbortsContains(t, cur, "in the future", func() {
		CreateEvent(cross(cur), "Past", "Here", "", inHours(-1), "0", 10)
	})
	uassert.AbortsContains(t, cur, "https://", func() {
		CreateEvent(cross(cur), "Bad", "Here", "javascript:x", inHours(72), "0", 10)
	})
	uassert.AbortsContains(t, cur, "price must be", func() {
		CreateEvent(cross(cur), "Cheap", "Here", "", inHours(72), "0.01", 10)
	})
	uassert.AbortsContains(t, cur, "capacity must be", func() {
		CreateEvent(cross(cur), "Huge", "Here", "", inHours(72), "0", 10001)
	})
	uassert.AbortsContains(t, cur, "start must look like", func() {
		CreateEvent(cross(cur), "When", "Here", "", "tomorrow", "0", 10)
	})
	uassert.AbortsContains(t, cur, "venue holds a slur", func() {
		CreateEvent(cross(cur), "Party", "Heil Hitler Hall", "", inHours(72), "0", 10)
	})
	uassert.AbortsContains(t, cur, "title must be", func() {
		CreateEvent(cross(cur), "<b>", "Here", "", inHours(72), "0", 10)
	})
	testing.SetOriginSend(ugnots(1))
	uassert.AbortsContains(t, cur, "takes no coins", func() {
		CreateEvent(cross(cur), "Paid", "Here", "", inHours(72), "0", 10)
	})
	testing.SetOriginSend(nil)

	testing.SetRealm(testing.NewUserRealm(carol))
	uassert.AbortsContains(t, cur, "artist profile first", func() {
		CreateEvent(cross(cur), "Nope", "Here", "", inHours(72), "0", 10)
	})

	before := balance(alice)
	testing.IssueCoins(realmAddr, ugnots(2_500_000))
	testing.SetOriginSend(ugnots(2_500_000))
	testing.SetRealm(testing.NewUserRealm(carol))
	tid := BuyTicket(cross(cur), eid)
	uassert.Equal(t, carol, TicketOwner(tid))
	uassert.Equal(t, before+2_500_000, balance(alice))
	uassert.Equal(t, int64(0), balance(realmAddr))

	testing.SetOriginSend(ugnots(1))
	uassert.AbortsContains(t, cur, "attach exactly 2.5 GNOT", func() { BuyTicket(cross(cur), eid) })
	testing.SetRealm(testing.NewCodeRealm("gno.land/r/evil/proxy"))
	uassert.AbortsContains(t, cur, "directly from your wallet", func() { BuyTicket(cross(cur), eid) })
	testing.SetOriginSend(nil)

	e, ok := EventInfo(eid)
	urequire.True(t, ok)
	uassert.Equal(t, 1, e.Sold)
	urequire.True(t, strings.Contains(EventsJSON(0, 50, true), `"title":"Release Party"`))

	// Paid tickets of an unverified artist are refused, like tips.
	verify(cur, aid, false)
	testing.SetRealm(testing.NewUserRealm(carol))
	testing.SetOriginSend(ugnots(2_500_000))
	uassert.AbortsContains(t, cur, "not verified", func() { BuyTicket(cross(cur), eid) })
	testing.SetOriginSend(nil)
}

func TestFreeLimitAndSoldOut(cur realm, t *testing.T) {
	alice, _ := artist(cur, "Free Alice")
	carol, dave, bob := who("carol"), who("dave"), who("bob")
	testing.SetRealm(testing.NewUserRealm(alice))
	eid := CreateEvent(cross(cur), "Free Show", "Online", "", inHours(48), "0", 2)

	testing.SetRealm(testing.NewUserRealm(carol))
	BuyTicket(cross(cur), eid)
	uassert.AbortsContains(t, cur, "ticket limit", func() { BuyTicket(cross(cur), eid) })
	testing.SetOriginSend(ugnots(1))
	testing.SetRealm(testing.NewUserRealm(dave))
	uassert.AbortsContains(t, cur, "takes no coins", func() { BuyTicket(cross(cur), eid) })
	testing.SetOriginSend(nil)
	BuyTicket(cross(cur), eid)
	testing.SetRealm(testing.NewUserRealm(bob))
	uassert.AbortsContains(t, cur, "sold out", func() { BuyTicket(cross(cur), eid) })
}

// Paid: up to 4 per wallet, serials count up.
func TestPaidLimit(cur realm, t *testing.T) {
	fee(cur, 0)
	alice, aid := artist(cur, "Paid Alice")
	verify(cur, aid, true)
	carol := who("carol")
	testing.SetRealm(testing.NewUserRealm(alice))
	eid := CreateEvent(cross(cur), "Paid Show", "Club", "", inHours(48), "1", 10)
	testing.SetRealm(testing.NewUserRealm(carol))
	for i := 1; i <= maxPerBuyer; i++ {
		testing.IssueCoins(realmAddr, ugnots(ugnot))
		testing.SetOriginSend(ugnots(ugnot))
		tk, _ := TicketInfo(BuyTicket(cross(cur), eid))
		uassert.Equal(t, i, tk.Serial)
	}
	uassert.AbortsContains(t, cur, "1 free or 4 paid per wallet", func() { BuyTicket(cross(cur), eid) })
	testing.SetOriginSend(nil)
	uassert.Equal(t, 4, len(TicketsOf(carol, 0, 10)))
	uassert.Equal(t, int64(0), balance(realmAddr))
}

func TestGiftAndCheckIn(cur realm, t *testing.T) {
	alice, _ := artist(cur, "Club Alice")
	carol, dave, bob := who("carol"), who("dave"), who("bob")
	testing.SetRealm(testing.NewUserRealm(alice))
	eid := CreateEvent(cross(cur), "Club Night", "Lyon", "", inHours(72), "0", 10)

	testing.SetRealm(testing.NewUserRealm(carol))
	tid := BuyTicket(cross(cur), eid)
	uassert.AbortsContains(t, cur, "invalid recipient", func() { TransferTicket(cross(cur), carol, tid) })
	uassert.AbortsContains(t, cur, "invalid recipient", func() { TransferTicket(cross(cur), realmAddr, tid) })
	TransferTicket(cross(cur), dave, tid)
	uassert.Equal(t, dave, TicketOwner(tid))
	uassert.Equal(t, 0, len(TicketsOf(carol, 0, 10)))
	uassert.Equal(t, 1, len(TicketsOf(dave, 0, 10)))
	uassert.AbortsContains(t, cur, "do not hold", func() { TransferTicket(cross(cur), bob, tid) })

	testing.SetRealm(testing.NewUserRealm(dave))
	uassert.AbortsContains(t, cur, "only the concert's artist", func() { CheckIn(cross(cur), tid, "4821") })
	testing.SetRealm(testing.NewUserRealm(alice))
	uassert.AbortsContains(t, cur, "12h before", func() { CheckIn(cross(cur), tid, "4821") })
	testing.SkipHeights(int64(62 * 3600 / 5))
	testing.SetRealm(testing.NewUserRealm(dave))
	Present(cross(cur), tid, "4821")
	testing.SetRealm(testing.NewUserRealm(alice))
	CheckIn(cross(cur), tid, "4821")
	tk, _ := TicketInfo(tid)
	urequire.True(t, tk.Attended)
	uassert.Equal(t, 1, Attended(dave))
	uassert.AbortsContains(t, cur, "already checked in", func() { CheckIn(cross(cur), tid, "4821") })
	testing.SetRealm(testing.NewUserRealm(dave))
	uassert.AbortsContains(t, cur, "can no longer be gifted", func() { TransferTicket(cross(cur), bob, tid) })

	urequire.True(t, strings.Contains(TicketSVG(tid), "data:image/svg+xml"))
	urequire.True(t, strings.Contains(TicketsOfJSON(dave), `"attended":true`))
}

func TestCancelAndModeration(cur realm, t *testing.T) {
	alice, _ := artist(cur, "Maybe Alice")
	carol := who("carol")
	testing.SetRealm(testing.NewUserRealm(alice))
	maybe := CreateEvent(cross(cur), "Maybe Show", "Paris", "", inHours(72), "0", 10)
	scam := CreateEvent(cross(cur), "Scam Show", "Nowhere", "", inHours(24), "0", 10)

	testing.SetRealm(testing.NewUserRealm(carol))
	uassert.AbortsContains(t, cur, "only the artist", func() { CancelEvent(cross(cur), maybe) })
	testing.SetRealm(testing.NewUserRealm(alice))
	CancelEvent(cross(cur), maybe)
	testing.SetRealm(testing.NewUserRealm(carol))
	uassert.AbortsContains(t, cur, "cancelled", func() { BuyTicket(cross(cur), maybe) })
	e, _ := EventInfo(maybe)
	uassert.True(t, e.Cancelled)

	uassert.AbortsWithMessage(t, cur, "tickets: admin only", func() { HideEvent(cross(cur), scam, true, "spam") })
	testing.SetRealm(testing.NewUserRealm(boss))
	uassert.AbortsContains(t, cur, "reason must be", func() { HideEvent(cross(cur), scam, true, "") })
	HideEvent(cross(cur), scam, true, "fake concert")
	_, ok := EventInfo(scam)
	uassert.False(t, ok)
	uassert.Equal(t, "Removed by moderation: fake concert", HiddenNote(scam))
	uassert.Equal(t, "", EventSVG(scam))
	for _, u := range Upcoming(50) {
		uassert.True(t, u.ID != scam && u.ID != maybe)
	}
	HideEvent(cross(cur), scam, false, "ignored")
	uassert.Equal(t, "", HiddenNote(scam))
	_, ok = EventInfo(scam)
	uassert.True(t, ok)
}
