package tickets

import (
	"chain"
	"strings"
	"testing"

	"gno.land/p/gnoradio/store/v0"
	"gno.land/p/nt/uassert/v0"
	catalog "gno.land/r/gnoradio/catalog/v1"
	"gno.land/r/gnoradio/data"
	"gno.land/r/gnoradio/tickets/nft"
)

// Threat model rows of docs/ARCHITECTURE-v1.md section 8 that tickets owns.

// paidShow makes a verified artist with a paid concert (2 GNOT) and returns
// the artist's wallet, the artist id and the concert id.
func paidShow(cur realm) (address, int, int) {
	w, aid := artist(cur, "Threat Alice")
	verify(cur, aid, true)
	testing.SetRealm(testing.NewUserRealm(w))
	return w, aid, CreateEvent(cross(cur), "Threat Show", "Club", "", inHours(48), "2", 100)
}

// Payment bypass through a realm: BuyTicket takes coins only from a wallet's
// direct call (a MsgRun ephemeral realm has a pkgpath like any realm).
func TestPayRefusesRealms(cur realm, t *testing.T) {
	_, _, id := paidShow(cur)
	testing.SetOriginSend(ugnots(2 * ugnot))
	testing.SetRealm(testing.NewCodeRealm("gno.land/r/evil/proxy"))
	uassert.AbortsContains(t, cur, "directly from your wallet", func() { BuyTicket(cross(cur), id) })
	testing.SetOriginSend(nil)
	for _, fn := range []func(){
		func() { CreateEvent(cross(cur), "Proxy", "Here", "", inHours(48), "0", 10) },
		func() { CancelEvent(cross(cur), id) },
		func() { TransferTicket(cross(cur), who("x"), 1) },
		func() { CheckIn(cross(cur), 1, "4821") },
	} {
		uassert.AbortsContains(t, cur, "directly from your wallet", fn)
	}
}

// Fee and price mismatch: only the exact price plus fee, in one ugnot coin.
func TestExactAmount(cur realm, t *testing.T) {
	fee(cur, 300_000)
	_, _, id := paidShow(cur)
	testing.SetRealm(testing.NewUserRealm(who("carol")))
	for _, c := range []chain.Coins{
		ugnots(2 * ugnot),         // the price without the fee
		ugnots(2*ugnot + 300_001), // too much
		ugnots(300_000),           // the fee alone
		{{Denom: "uatom", Amount: 2_300_000}},
		{{Denom: denom, Amount: 2_000_000}, {Denom: "uatom", Amount: 300_000}},
	} {
		testing.SetOriginSend(c)
		uassert.AbortsContains(t, cur, "attach", func() { BuyTicket(cross(cur), id) })
	}
	testing.SetOriginSend(nil)
	uassert.AbortsContains(t, cur, "attach", func() { BuyTicket(cross(cur), id) })
	fee(cur, 0)
}

// Rules realms end every transaction holding nothing; a cancelled concert
// leaves the payments with the artist, who refunds directly ("Payments went
// straight to the artist: contact them for a refund").
func TestRulesHoldNothingAndRefundWording(cur realm, t *testing.T) {
	fee(cur, 250_000)
	treasury := catalog.Treasury()
	owner, _, id := paidShow(cur)
	carol := who("carol")
	a0, t0 := balance(owner), balance(treasury)
	testing.SetRealm(testing.NewUserRealm(carol))
	testing.IssueCoins(realmAddr, ugnots(2_250_000)) // what the wallet's call brings
	testing.SetOriginSend(ugnots(2_250_000))
	BuyTicket(cross(cur), id)
	testing.SetOriginSend(nil)
	uassert.Equal(t, int64(0), balance(realmAddr))
	uassert.Equal(t, a0+2_000_000, balance(owner))
	uassert.Equal(t, t0+250_000, balance(treasury))

	testing.SetRealm(testing.NewUserRealm(owner))
	CancelEvent(cross(cur), id)
	uassert.Equal(t, int64(0), balance(realmAddr)) // nothing to refund from here
	uassert.Equal(t, a0+2_000_000, balance(owner))
	uassert.True(t, strings.Contains(EventsJSON(0, 1, false), `"cancelled":true`))
	fee(cur, 0)
}

// Forged mints and moves: nobody but the tickets writer drives the NFT
// realm, not even a wallet holding the ticket.
func TestNFTOnlyByWriter(cur realm, t *testing.T) {
	alice, _ := artist(cur, "Mint Alice")
	carol, mallory := who("carol"), who("mallory")
	testing.SetRealm(testing.NewUserRealm(alice))
	id := CreateEvent(cross(cur), "Mint Show", "Club", "", inHours(48), "0", 10)
	testing.SetRealm(testing.NewUserRealm(carol))
	tid := BuyTicket(cross(cur), id)

	testing.SetRealm(testing.NewUserRealm(mallory))
	uassert.AbortsContains(t, cur, "only "+self+" mints", func() { nft.Mint(cross(cur), mallory, tid+1000) })
	testing.SetRealm(testing.NewUserRealm(carol))
	uassert.AbortsContains(t, cur, "only "+self+" mints", func() { nft.Transfer(cross(cur), carol, mallory, tid) })
	testing.SetRealm(testing.NewCodeRealm("gno.land/r/gnoradio/tickets/v0"))
	uassert.AbortsContains(t, cur, "only "+self+" mints", func() { nft.Mint(cross(cur), mallory, tid+1000) })
	uassert.Equal(t, carol, TicketOwner(tid))

	// A ticket record a wallet or realm writes itself is refused by data.
	testing.SetRealm(testing.NewUserRealm(mallory))
	uassert.AbortsContains(t, cur, "only "+self+" writes tickets", func() {
		data.Set(cross(cur), cTickets, store.Pad(0), store.Rec(ticketRecord(&Ticket{Event: id, Serial: 1})))
	})

	// Transfer by a non-holder, check-in by another concert's artist.
	testing.SetRealm(testing.NewUserRealm(mallory))
	uassert.AbortsContains(t, cur, "do not hold", func() { TransferTicket(cross(cur), who("y"), tid) })
	other, _ := artist(cur, "Other Alice")
	testing.SetRealm(testing.NewUserRealm(other))
	uassert.AbortsContains(t, cur, "only the concert's artist", func() { CheckIn(cross(cur), tid, "4821") })
	uassert.AbortsContains(t, cur, "unknown ticket", func() { CheckIn(cross(cur), TicketCount()+1, "4821") })
}

// Gifts never go to GnoRadio realms (lost for good), and a wallet's list is
// capped, so nobody grows it past the data realm's value limit; gifts stop
// well before the cap, so nobody can block another wallet's purchases.
func TestGiftGuards(cur realm, t *testing.T) {
	alice, _ := artist(cur, "Gift Alice")
	carol, full := who("carol"), who("full")
	testing.SetRealm(testing.NewUserRealm(alice))
	id := CreateEvent(cross(cur), "Gift Show", "Club", "", inHours(48), "0", 10)
	testing.SetRealm(testing.NewUserRealm(carol))
	tid := BuyTicket(cross(cur), id)
	for _, to := range []address{"", realmAddr, chain.PackageAddress("gno.land/r/gnoradio/tickets/nft"),
		chain.PackageAddress("gno.land/r/gnoradio/data"), chain.PackageAddress("gno.land/r/gnoradio/catalog/v1")} {
		uassert.AbortsContains(t, cur, "invalid recipient", func() { TransferTicket(cross(cur), to, tid) })
	}
	held := func(n int) string { // n tickets nobody bought here
		ids := make([]int, n)
		for i := range ids {
			ids[i] = 5_000_000 + i
		}
		return store.Pack(ids)
	}
	// A flood of gifts stops at maxGifted: its target can still buy.
	testing.SetRealm(testing.NewCodeRealm(self))
	data.Set(cross(cur), cOwned, full.String(), held(maxGifted))
	testing.SetRealm(testing.NewUserRealm(carol))
	uassert.AbortsContains(t, cur, "takes no more gifts", func() { TransferTicket(cross(cur), full, tid) })
	testing.SetRealm(testing.NewUserRealm(full))
	BuyTicket(cross(cur), id)
	testing.SetRealm(testing.NewCodeRealm(self))
	data.Set(cross(cur), cOwned, full.String(), held(maxOwned))
	testing.SetRealm(testing.NewUserRealm(alice))
	id2 := CreateEvent(cross(cur), "Gift Show Two", "Club", "", inHours(49), "0", 10)
	testing.SetRealm(testing.NewUserRealm(full))
	uassert.AbortsContains(t, cur, "holds 1000 tickets", func() { BuyTicket(cross(cur), id2) })
	testing.SetRealm(testing.NewUserRealm(carol))
	testing.SetOriginSend(ugnots(1))
	uassert.AbortsContains(t, cur, "takes no coins", func() { TransferTicket(cross(cur), who("d"), tid) })
	testing.SetOriginSend(nil)
}

// A paused tickets role sells, gifts and checks in nothing; reads go on.
func TestPaused(cur realm, t *testing.T) {
	alice, _ := artist(cur, "Pause Alice")
	carol := who("carol")
	testing.SetRealm(testing.NewUserRealm(alice))
	id := CreateEvent(cross(cur), "Pause Show", "Club", "", inHours(48), "0", 10)
	testing.SetRealm(testing.NewUserRealm(carol))
	tid := BuyTicket(cross(cur), id)
	testing.SetRealm(testing.NewUserRealm(dataOwner))
	data.Pause(cross(cur), "tickets", true)
	testing.SetRealm(testing.NewUserRealm(who("e")))
	uassert.AbortsContains(t, cur, "tickets is paused", func() { BuyTicket(cross(cur), id) })
	testing.SetRealm(testing.NewUserRealm(carol))
	uassert.AbortsContains(t, cur, "tickets is paused", func() { TransferTicket(cross(cur), who("d"), tid) })
	testing.SetRealm(testing.NewUserRealm(alice))
	uassert.AbortsContains(t, cur, "tickets is paused", func() {
		CreateEvent(cross(cur), "Later", "Paris", "", inHours(72), "0", 10)
	})
	uassert.Equal(t, carol, TicketOwner(tid))
	_, ok := EventInfo(id)
	uassert.True(t, ok)
	testing.SetRealm(testing.NewUserRealm(dataOwner))
	data.Pause(cross(cur), "tickets", false)
}

// The admin passes in two steps, every change mirrored to the data realm
// for the next release; the mirror is the authority.
func TestAdminTwoStep(cur realm, t *testing.T) {
	bob, carol := who("bob"), who("carol")
	testing.SetRealm(testing.NewUserRealm(carol))
	uassert.AbortsWithMessage(t, cur, "tickets: admin only", func() { OfferAdmin(cross(cur), carol) })
	testing.SetRealm(testing.NewUserRealm(boss))
	OfferAdmin(cross(cur), bob)
	uassert.Equal(t, boss, Admin())
	testing.SetRealm(testing.NewUserRealm(carol))
	uassert.AbortsContains(t, cur, "nothing offered to you", func() { AcceptAdmin(cross(cur)) })
	testing.SetRealm(testing.NewUserRealm(bob))
	testing.SetOriginSend(ugnots(1))
	uassert.AbortsContains(t, cur, "takes no coins", func() { AcceptAdmin(cross(cur)) })
	testing.SetOriginSend(nil)
	AcceptAdmin(cross(cur))
	uassert.Equal(t, bob, Admin())
	v, _ := data.Get(cConfig, "admin")
	uassert.Equal(t, bob.String(), v)
	testing.SetRealm(testing.NewUserRealm(boss))
	uassert.AbortsWithMessage(t, cur, "tickets: admin only", func() { SetServiceFee(cross(cur), 1) })

	// The previous release changed the mirror: it counts here at once.
	testing.SetRealm(testing.NewCodeRealm(self))
	data.Set(cross(cur), cConfig, "admin", carol.String())
	testing.SetRealm(testing.NewUserRealm(bob))
	uassert.AbortsWithMessage(t, cur, "tickets: admin only", func() { SetServiceFee(cross(cur), 1) })
	testing.SetRealm(testing.NewUserRealm(carol))
	OfferAdmin(cross(cur), boss)
	testing.SetRealm(testing.NewUserRealm(boss))
	AcceptAdmin(cross(cur))
	uassert.Equal(t, boss, Admin())
}

// Renounce is for good: no admin call works and the mirror says so. Runs
// last in this file, and puts the dev admin back as a release would not.
func TestRenounceAdmin(cur realm, t *testing.T) {
	testing.SetRealm(testing.NewUserRealm(boss))
	RenounceAdmin(cross(cur))
	uassert.Equal(t, address(""), Admin())
	uassert.AbortsWithMessage(t, cur, "tickets: admin only", func() { SetServiceFee(cross(cur), 0) })
	uassert.AbortsWithMessage(t, cur, "tickets: admin only", func() { HideEvent(cross(cur), 1, true, "spam spam") })
	testing.SetRealm(testing.NewCodeRealm(self))
	data.Set(cross(cur), cConfig, "admin", boss.String())
}
