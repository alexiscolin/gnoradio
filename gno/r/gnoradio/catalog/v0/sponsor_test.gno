package catalog

import (
	"chain"
	"strings"
	"testing"

	"gno.land/p/gnoradio/store/v0"
	"gno.land/p/nt/testutils/v0"
	"gno.land/p/nt/uassert/v0"
	"gno.land/p/nt/urequire/v0"
)

var (
	fan1 = testutils.TestAddress("fan1")
	fan2 = testutils.TestAddress("fan2")
	// heldBase is the realm's balance outside the budgets when a test starts
	// (other tests leave coins they issued).
	heldBase int64
)

// sponsorSetup gives alice a verified track (bob 30% collaborator) and a
// fresh budget table.
func sponsorSetup(cur realm) int {
	id := promoTrack(cur)
	budgets, walletDay, promoHeld = store.NewMap(16), store.NewMap(16), 0
	heldBase = balance(realmAddr)
	return id
}

// fund sends n ugnot to FundPromo as who, the way a wallet does.
func fund(cur realm, who address, n int64) {
	testing.IssueCoins(realmAddr, ugnots(n))
	testing.SetOriginSend(ugnots(n))
	testing.SetRealm(testing.NewUserRealm(who))
	FundPromo(cross(cur))
	testing.SetOriginSend(nil)
}

// reserve, payPick and unreserve call the catalog as the radio realm.
func reserve(cur realm, id int, who address, end int64) int64 {
	testing.SetRealm(testing.NewCodeRealm(radioRealm))
	return PromoReserve(cross(cur), id, who, end)
}

func payPick(cur realm, id int, who address, end, amt int64) {
	testing.SetRealm(testing.NewCodeRealm(radioRealm))
	PromoClaim(cross(cur), id, who, end, amt)
}

func unreserve(cur realm, id int, who address, end, amt, reserved int64) {
	testing.SetRealm(testing.NewCodeRealm(radioRealm))
	PromoRelease(cross(cur), id, who, end, amt, reserved)
}

// accounted: the realm's coins beyond heldBase are exactly the budgets.
func accounted(t *testing.T) {
	t.Helper()
	uassert.Equal(t, heldBase+promoHeld, balance(realmAddr))
	sum := int64(0)
	keys, _ := PromoPage(0, 100)
	for _, k := range keys {
		b, _ := getBudget(atoi(k))
		sum += b.Balance
	}
	uassert.Equal(t, promoHeld, sum)
}

func TestFundPromo(cur realm, t *testing.T) {
	sponsorSetup(cur)
	// Guards: coins only from a wallet call, in ugnot, within bounds, from a verified owner.
	testing.IssueCoins(realmAddr, ugnots(ugnot))
	testing.SetOriginSend(ugnots(ugnot))
	testing.SetRealm(testing.NewCodeRealm("gno.land/r/evil/proxy"))
	uassert.AbortsContains(t, cur, "directly from your wallet", func() { FundPromo(cross(cur)) })
	testing.SetRealm(testing.NewUserRealm(carol))
	uassert.AbortsContains(t, cur, "create your artist profile", func() { FundPromo(cross(cur)) })
	testing.SetOriginSend(chain.Coins{{Denom: "uatom", Amount: ugnot}})
	testing.SetRealm(testing.NewUserRealm(alice))
	uassert.AbortsContains(t, cur, "attach an amount in ugnot", func() { FundPromo(cross(cur)) })
	testing.SetOriginSend(ugnots(10))
	uassert.AbortsContains(t, cur, "0.1 to 1000000 GNOT", func() { FundPromo(cross(cur)) })
	testing.SetOriginSend(nil)
	heldBase = balance(realmAddr) // the stray GNOT issued above is not a budget

	testing.SetRealm(testing.NewUserRealm(dave))
	RegisterArtist(cross(cur), "Unverified Dave", "")
	testing.IssueCoins(realmAddr, ugnots(ugnot))
	heldBase += ugnot
	testing.SetOriginSend(ugnots(ugnot))
	uassert.AbortsContains(t, cur, "verify your profile first", func() { FundPromo(cross(cur)) })
	testing.SetOriginSend(nil)

	fund(cur, alice, 2*ugnot)
	uassert.Equal(t, int64(defaultPickPay), PromoOffer(1))
	fund(cur, alice, ugnot)
	js := PromoJSON(1)
	urequire.True(t, strings.Contains(js, `"balance":3000000,"reserved":0,"free":3000000,"pay":30000,"perDay":0,"today":0,"funded":3000000,"paid":0,"picks":0,"offer":30000`), js)
	urequire.True(t, strings.Contains(ArtistJSON(1), `"sponsor":30000`), ArtistJSON(1))
	accounted(t)
}

func TestSetPromoPay(cur realm, t *testing.T) {
	sponsorSetup(cur)
	testing.SetRealm(testing.NewUserRealm(alice))
	uassert.AbortsContains(t, cur, "0.01 to 0.05 GNOT", func() { SetPromoPay(cross(cur), 50_001, 0) })
	uassert.AbortsContains(t, cur, "0.01 to 0.05 GNOT", func() { SetPromoPay(cross(cur), 9_999, 0) })
	uassert.AbortsContains(t, cur, "daily limit", func() { SetPromoPay(cross(cur), 20_000, 101) })
	testing.SetRealm(testing.NewUserRealm(carol))
	uassert.AbortsContains(t, cur, "create your artist profile", func() { SetPromoPay(cross(cur), 20_000, 0) })
	fund(cur, alice, ugnot)
	testing.SetRealm(testing.NewUserRealm(alice))
	SetPromoPay(cross(cur), 50_000, 2)
	uassert.Equal(t, int64(50_000), PromoOffer(1))
	SetPromoPay(cross(cur), 0, 0) // paused
	uassert.Equal(t, int64(0), PromoOffer(1))
}

// A reservation leaves the free balance, is paid once the radio says the pick
// aired, and lapses back to the budget after 7 days.
func TestSponsoredPickMoney(cur realm, t *testing.T) {
	id := sponsorSetup(cur)
	fund(cur, alice, 100_000)
	end := now() + 300

	testing.SetRealm(testing.NewUserRealm(carol))
	uassert.AbortsContains(t, cur, "only the GnoRadio radio realm", func() { PromoReserve(cross(cur), id, carol, end) })
	uassert.AbortsContains(t, cur, "only the GnoRadio radio realm", func() { PromoClaim(cross(cur), id, carol, end, 30_000) })
	uassert.AbortsContains(t, cur, "only the GnoRadio radio realm", func() { PromoRelease(cross(cur), id, carol, end, 30_000, 0) })

	// Never the artist, a collaborator or a GnoRadio realm.
	testing.SetRealm(testing.NewCodeRealm(radioRealm))
	uassert.AbortsContains(t, cur, "collaborators", func() { PromoReserve(cross(cur), id, alice, end) })
	testing.SetRealm(testing.NewCodeRealm(radioRealm))
	uassert.AbortsContains(t, cur, "collaborators", func() { PromoReserve(cross(cur), id, bob, end) })
	testing.SetRealm(testing.NewCodeRealm(radioRealm))
	uassert.AbortsContains(t, cur, "collaborators", func() { PromoReserve(cross(cur), id, chain.PackageAddress(radioRealm), end) })

	got := reserve(cur, id, carol, end)
	uassert.Equal(t, int64(30_000), got)
	b, _ := getBudget(1)
	uassert.Equal(t, int64(70_000), b.free(now()/daySecs))
	// The reserved part cannot be withdrawn.
	testing.SetRealm(testing.NewUserRealm(alice))
	a0 := balance(alice)
	WithdrawPromo(cross(cur), 1)
	uassert.Equal(t, int64(70_000), balance(alice)-a0)
	uassert.AbortsContains(t, cur, "nothing of yours", func() { WithdrawPromo(cross(cur), 1) })
	accounted(t)

	uassert.True(t, PromoClaimable(id, end, 30_000))
	uassert.False(t, PromoClaimable(id, end, 30_001))
	c0 := balance(carol)
	payPick(cur, id, carol, end, 30_000)
	uassert.Equal(t, int64(30_000), balance(carol)-c0)
	// Once only: the reservation is gone.
	uassert.False(t, PromoClaimable(id, end, 30_000))
	testing.SetRealm(testing.NewCodeRealm(radioRealm))
	uassert.AbortsContains(t, cur, "cancelled", func() { PromoClaim(cross(cur), id, carol, end, 30_000) })
	js := PromoJSON(1)
	urequire.True(t, strings.Contains(js, `"balance":0,"reserved":0,"free":0`), js)
	urequire.True(t, strings.Contains(js, `"paid":30000,"picks":1,"offer":0`), js)
	accounted(t)

	// Empty budget: no reservation.
	testing.SetRealm(testing.NewCodeRealm(radioRealm))
	uassert.AbortsContains(t, cur, "budget is empty", func() { PromoReserve(cross(cur), id, fan1, end) })

	// A release returns the reservation at once; an unclaimed one lapses after 7 days.
	fund(cur, alice, 100_000)
	reserve(cur, id, fan1, end)
	unreserve(cur, id, fan1, end, 30_000, 0)
	b, _ = getBudget(1)
	uassert.Equal(t, int64(100_000), b.free(now()/daySecs))
	reserve(cur, id, fan2, end)
	b, _ = getBudget(1)
	uassert.Equal(t, int64(70_000), b.free(now()/daySecs))
	testing.SkipHeights((claimDays*daySecs + daySecs) / 5)
	b, _ = getBudget(1)
	uassert.Equal(t, int64(100_000), b.free(now()/daySecs))
	uassert.False(t, PromoClaimable(id, end, 30_000)) // lapsed
	testing.SetRealm(testing.NewCodeRealm(radioRealm))
	uassert.AbortsContains(t, cur, "within 7 days", func() { PromoClaim(cross(cur), id, fan2, end, 30_000) })
	accounted(t)
}

// Per listener: one sponsored pick per artist a day, three a day in all; per
// artist: the daily limit the artist chose.
func TestSponsoredPickCaps(cur realm, t *testing.T) {
	id := sponsorSetup(cur)
	fund(cur, alice, ugnot)
	end := now() + 300
	reserve(cur, id, carol, end)
	testing.SetRealm(testing.NewCodeRealm(radioRealm))
	uassert.AbortsContains(t, cur, "one sponsored pick per artist a day", func() { PromoReserve(cross(cur), id, carol, end) })
	// Three other artists for the wallet cap.
	var ids []int
	for i, n := range []string{"Cap One", "Cap Two", "Cap Three"} {
		who := testutils.TestAddress("capartist" + itoa(i))
		testing.SetRealm(testing.NewUserRealm(who))
		aid := RegisterArtist(cross(cur), n, "")
		tid := publish(cur, n+" Song")
		verified(cur, aid)
		fund(cur, who, ugnot)
		ids = append(ids, tid)
	}
	reserve(cur, ids[0], carol, end)
	reserve(cur, ids[1], carol, end)
	testing.SetRealm(testing.NewCodeRealm(radioRealm))
	uassert.AbortsContains(t, cur, "three sponsored picks a day", func() { PromoReserve(cross(cur), ids[2], carol, end) })
	// The next day the caps start again.
	testing.SkipHeights(daySecs / 5)
	reserve(cur, ids[2], carol, now()+300)

	// The artist's own daily limit.
	testing.SetRealm(testing.NewUserRealm(alice))
	SetPromoPay(cross(cur), 20_000, 1)
	reserve(cur, id, fan1, now()+300)
	uassert.Equal(t, int64(0), PromoOffer(1))
	testing.SetRealm(testing.NewCodeRealm(radioRealm))
	uassert.AbortsContains(t, cur, "taken, pick it normally", func() { PromoReserve(cross(cur), id, fan2, now()+300) })
	accounted(t)
}

// Hidden or unverified: no new sponsored pick, the funder still withdraws,
// even while GnoRadio is frozen, and nobody else can.
func TestPromoHiddenAndFrozen(cur realm, t *testing.T) {
	id := sponsorSetup(cur)
	fund(cur, alice, ugnot)
	testing.SetRealm(testing.NewUserRealm(boss))
	HideArtist(cross(cur), 1, true, "test")
	Freeze(cross(cur), true)
	uassert.Equal(t, int64(0), PromoOffer(1))
	testing.SetRealm(testing.NewCodeRealm(radioRealm))
	uassert.AbortsContains(t, cur, "paused for an upgrade", func() { PromoReserve(cross(cur), id, carol, now()+300) })
	testing.SetRealm(testing.NewUserRealm(boss))
	Freeze(cross(cur), false)
	HideArtist(cross(cur), 1, false, "")
	Verify(cross(cur), 1, false)
	testing.SetRealm(testing.NewCodeRealm(radioRealm))
	uassert.AbortsContains(t, cur, "does not sponsor", func() { PromoReserve(cross(cur), id, carol, now()+300) })
	testing.SetRealm(testing.NewUserRealm(boss))
	Freeze(cross(cur), true)
	testing.SetRealm(testing.NewUserRealm(boss))
	uassert.AbortsContains(t, cur, "nothing of yours", func() { WithdrawPromo(cross(cur), 1) })
	testing.SetRealm(testing.NewUserRealm(alice))
	a0 := balance(alice)
	WithdrawPromo(cross(cur), 1)
	uassert.Equal(t, int64(ugnot), balance(alice)-a0)
	testing.SetRealm(testing.NewUserRealm(boss))
	Freeze(cross(cur), false)
	accounted(t)
}

// A profile that changes hands: the old funder keeps their money; the new
// owner's first funding refunds them, reservations included (cancelled).
func TestPromoOwnershipChange(cur realm, t *testing.T) {
	sponsorSetup(cur)
	testing.SetRealm(testing.NewUserRealm(boss))
	aid := CreateArtist(cross(cur), OriginCurated, "Handed Over", "", "")
	tid := ImportTrack(cross(cur), aid, "Handed Song", 5, "2:00", "CC0", "", ia, sha, "", "", "https://archive.org/details/h", "Handed Over")
	AssignArtist(cross(cur), aid, fan1)
	fund(cur, fan1, ugnot)
	end := now() + 300
	reserve(cur, tid, carol, end)

	testing.SetRealm(testing.NewUserRealm(boss))
	ResetOwner(cross(cur), aid)
	uassert.Equal(t, int64(0), PromoOffer(aid))
	AssignArtist(cross(cur), aid, fan2)
	// The old funder's budget no longer sponsors the new owner's tracks.
	uassert.Equal(t, int64(0), PromoOffer(aid))
	testing.SetRealm(testing.NewUserRealm(fan2))
	uassert.AbortsContains(t, cur, "nothing of yours", func() { WithdrawPromo(cross(cur), aid) })

	f0 := balance(fan1)
	fund(cur, fan2, 500_000)
	uassert.Equal(t, int64(ugnot), balance(fan1)-f0)
	testing.SetRealm(testing.NewCodeRealm(radioRealm))
	uassert.AbortsContains(t, cur, "cancelled", func() { PromoClaim(cross(cur), tid, carol, end, 30_000) })
	uassert.Equal(t, int64(30_000), PromoOffer(aid))
	accounted(t)
}

// A tip can never spend the budgets' coins.
func TestTipCannotSpendBudgets(cur realm, t *testing.T) {
	id := sponsorSetup(cur)
	fund(cur, alice, ugnot)
	testing.SetRealm(testing.NewCodeRealm(radioRealm))
	uassert.AbortsContains(t, cur, "did not arrive", func() { RadioTip(cross(cur), id, 0, carol, "", "", ugnot) })
	accounted(t)
}

// A pick released before it aired gives back the daily counts it took, the
// artist's and the picker's; one that partly aired keeps them.
func TestPromoReleaseGivesBackCounts(cur realm, t *testing.T) {
	id := sponsorSetup(cur)
	fund(cur, alice, ugnot)
	SetPromoPay(cross(cur), 30_000, 1)
	end := now() + 300
	reserve(cur, id, fan1, end)
	uassert.Equal(t, int64(0), PromoOffer(1)) // the artist's one a day is taken
	unreserve(cur, id, fan1, end, 30_000, now())
	uassert.Equal(t, int64(30_000), PromoOffer(1))
	reserve(cur, id, fan1, end) // the picker's one per artist a day is back too
	unreserve(cur, id, fan1, end, 30_000, 0)
	uassert.Equal(t, int64(0), PromoOffer(1))
	testing.SetRealm(testing.NewCodeRealm(radioRealm))
	uassert.AbortsContains(t, cur, "taken, pick it normally", func() { PromoReserve(cross(cur), id, fan2, end) })
	// Released the next day: yesterday's reservation gives back no count of today's.
	yesterday := now()
	end2 := now() + daySecs
	testing.SkipHeights(daySecs / 5)
	reserve(cur, id, fan2, end2)
	unreserve(cur, id, fan2, end2, 0, yesterday)
	uassert.Equal(t, int64(0), PromoOffer(1))
	accounted(t)
}
