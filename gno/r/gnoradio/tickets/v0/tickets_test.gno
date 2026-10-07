package tickets

import (
	"chain"
	"chain/banker"
	"strings"
	"testing"
	"time"

	"gno.land/p/nt/avl/v0"
	"gno.land/p/nt/testutils/v0"
	"gno.land/p/nt/uassert/v0"
	"gno.land/p/nt/urequire/v0"

	"gno.land/r/gnoradio/catalog/v0"
)

var (
	alice = testutils.TestAddress("tk_alice")
	bob   = testutils.TestAddress("tk_bob")
	carol = testutils.TestAddress("tk_carol")
	dave  = testutils.TestAddress("tk_dave")
)

var realmAddr = chain.PackageAddress("gno.land/r/gnoradio/tickets/v0")

func reset() {
	events, byArtist, artistEvents, tickets = avl.Tree{}, avl.Tree{}, avl.Tree{}, avl.Tree{}
	upcoming, artistAhead = avl.Tree{}, avl.Tree{}
	owned, attended = avl.Tree{}, avl.Tree{}
	nEvents, nTickets = 0, 0
	ticketTok, ticketLed = nil, nil
	frozen = false
	admin = bob
	artistVerified = func(int) bool { return true }
}

func ugnots(n int64) chain.Coins { return chain.Coins{{Denom: denom, Amount: n}} }

func balance(addr address) int64 {
	return banker.NewReadonlyBanker().GetCoins(addr).AmountOf(denom)
}

func inHours(h int) string {
	return time.Now().Add(time.Duration(h) * time.Hour).UTC().Format("2006-01-02 15:04")
}

// ensureArtist registers alice as an artist once (catalog state persists
// across tests in the same run).
func ensureArtist(cur realm, t *testing.T) {
	if catalog.ArtistOf(alice) != 0 {
		return
	}
	testing.SetRealm(testing.NewUserRealm(alice))
	catalog.RegisterArtist(cross(cur), "Tickets Alice", "")
	urequire.True(t, catalog.ArtistOf(alice) != 0)
}

func TestCreateAndBuy(cur realm, t *testing.T) {
	reset()
	ensureArtist(cur, t)
	testing.SetRealm(testing.NewUserRealm(alice))
	eid := CreateEvent(cross(cur), "Release Party", "La Station, Paris", "https://live.example.org/watch?v=abc_1", inHours(72), "2.5", 2)
	uassert.Equal(t, 1, eid)
	uassert.AbortsContains(t, cur, "in the future", func() {
		CreateEvent(cross(cur), "Past", "Here", "", inHours(-1), "0", 10)
	})
	uassert.AbortsContains(t, cur, "https://", func() {
		CreateEvent(cross(cur), "Bad", "Here", "javascript:x", inHours(72), "0", 10)
	})
	uassert.AbortsContains(t, cur, "price must be", func() {
		CreateEvent(cross(cur), "Cheap", "Here", "", inHours(72), "0.01", 10)
	})
	uassert.AbortsContains(t, cur, "venue holds a slur", func() {
		CreateEvent(cross(cur), "Party", "Heil Hitler Hall", "", inHours(72), "0", 10)
	})

	testing.SetRealm(testing.NewUserRealm(carol))
	uassert.AbortsContains(t, cur, "artist profile first", func() {
		CreateEvent(cross(cur), "Nope", "Here", "", inHours(72), "0", 10)
	})

	before := balance(alice)
	testing.IssueCoins(realmAddr, ugnots(2_500_000))
	testing.SetOriginSend(ugnots(2_500_000))
	testing.SetRealm(testing.NewUserRealm(carol))
	tid := BuyTicket(cross(cur), 1)
	uassert.Equal(t, 1, tid)
	uassert.Equal(t, carol, TicketOwner(1))
	uassert.Equal(t, before+2_500_000, balance(alice))
	uassert.Equal(t, int64(0), balance(realmAddr))

	testing.SetOriginSend(ugnots(1))
	uassert.AbortsContains(t, cur, "attach exactly", func() { BuyTicket(cross(cur), 1) })
	testing.SetRealm(testing.NewCodeRealm("gno.land/r/evil/proxy"))
	uassert.AbortsContains(t, cur, "directly from your wallet", func() { BuyTicket(cross(cur), 1) })
	testing.SetOriginSend(nil)

	e, ok := EventInfo(1)
	urequire.True(t, ok)
	uassert.Equal(t, 1, e.Sold)
	urequire.True(t, strings.Contains(EventsJSON(0, 10, true), `"title":"Release Party"`))

	// Paid tickets of an unverified artist are refused, like tips.
	artistVerified = catalog.ArtistVerified
	testing.SetRealm(testing.NewUserRealm(carol))
	testing.SetOriginSend(ugnots(2_500_000))
	uassert.AbortsContains(t, cur, "not verified", func() { BuyTicket(cross(cur), 1) })
	testing.SetOriginSend(nil)
	artistVerified = func(int) bool { return true }
}

func TestFreeLimitAndSoldOut(cur realm, t *testing.T) {
	reset()
	ensureArtist(cur, t)
	testing.SetRealm(testing.NewUserRealm(alice))
	CreateEvent(cross(cur), "Free Show", "Online", "", inHours(48), "0", 2)

	testing.SetRealm(testing.NewUserRealm(carol))
	BuyTicket(cross(cur), 1)
	uassert.AbortsContains(t, cur, "ticket limit", func() { BuyTicket(cross(cur), 1) })
	testing.SetOriginSend(ugnots(1))
	testing.SetRealm(testing.NewUserRealm(dave))
	uassert.AbortsContains(t, cur, "takes no coins", func() { BuyTicket(cross(cur), 1) })
	testing.SetOriginSend(nil)
	BuyTicket(cross(cur), 1)
	testing.SetRealm(testing.NewUserRealm(bob))
	uassert.AbortsContains(t, cur, "sold out", func() { BuyTicket(cross(cur), 1) })
}

func TestGiftAndCheckIn(cur realm, t *testing.T) {
	reset()
	ensureArtist(cur, t)
	testing.SetRealm(testing.NewUserRealm(alice))
	CreateEvent(cross(cur), "Club Night", "Lyon", "", inHours(72), "0", 10)

	testing.SetRealm(testing.NewUserRealm(carol))
	BuyTicket(cross(cur), 1)
	TransferTicket(cross(cur), dave, 1)
	uassert.Equal(t, dave, TicketOwner(1))
	uassert.Equal(t, 0, len(TicketsOf(carol, 0, 10)))
	uassert.Equal(t, 1, len(TicketsOf(dave, 0, 10)))
	uassert.AbortsContains(t, cur, "do not hold", func() { TransferTicket(cross(cur), bob, 1) })

	testing.SetRealm(testing.NewUserRealm(dave))
	uassert.AbortsContains(t, cur, "only the concert's artist", func() { CheckIn(cross(cur), 1) })
	testing.SetRealm(testing.NewUserRealm(alice))
	uassert.AbortsContains(t, cur, "12h before", func() { CheckIn(cross(cur), 1) })
	testing.SkipHeights(int64(62 * 3600 / 5))
	CheckIn(cross(cur), 1)
	tk, _ := TicketInfo(1)
	urequire.True(t, tk.Attended)
	uassert.Equal(t, 1, Attended(dave))
	uassert.AbortsContains(t, cur, "already checked in", func() { CheckIn(cross(cur), 1) })
	testing.SetRealm(testing.NewUserRealm(dave))
	uassert.AbortsContains(t, cur, "can no longer be gifted", func() { TransferTicket(cross(cur), bob, 1) })

	urequire.True(t, strings.Contains(TicketSVG(1), "data:image/svg+xml"))
	urequire.True(t, strings.HasPrefix(TokenURI("1"), "data:application/json;base64,"))
	urequire.True(t, strings.Contains(TicketsOfJSON(dave), `"attended":true`))
}

func TestCancelAndModeration(cur realm, t *testing.T) {
	reset()
	ensureArtist(cur, t)
	testing.SetRealm(testing.NewUserRealm(alice))
	CreateEvent(cross(cur), "Maybe Show", "Paris", "", inHours(72), "0", 10)
	CreateEvent(cross(cur), "Scam Show", "Nowhere", "", inHours(24), "0", 10)

	testing.SetRealm(testing.NewUserRealm(carol))
	uassert.AbortsContains(t, cur, "only the artist", func() { CancelEvent(cross(cur), 1) })
	testing.SetRealm(testing.NewUserRealm(alice))
	CancelEvent(cross(cur), 1)
	testing.SetRealm(testing.NewUserRealm(carol))
	uassert.AbortsContains(t, cur, "cancelled", func() { BuyTicket(cross(cur), 1) })

	uassert.Equal(t, 1, len(Upcoming(10)))
	uassert.AbortsWithMessage(t, cur, "tickets: moderators only", func() { HideEvent(cross(cur), 2, true) })
	testing.SetRealm(testing.NewUserRealm(bob))
	HideEvent(cross(cur), 2, true)
	_, ok := EventInfo(2)
	uassert.False(t, ok)
	uassert.Equal(t, "", EventSVG(2))
	uassert.Equal(t, 0, len(Upcoming(10)))

	Freeze(cross(cur), true)
	testing.SetRealm(testing.NewUserRealm(alice))
	uassert.AbortsContains(t, cur, "paused", func() {
		CreateEvent(cross(cur), "Later", "Paris", "", inHours(72), "0", 10)
	})
}
