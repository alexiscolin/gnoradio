package catalog

import (
	"chain"
	"strings"
	"testing"

	"gno.land/p/nt/uassert/v0"
	"gno.land/p/nt/urequire/v0"
	"gno.land/r/gnoradio/data"
)

// fund sends n ugnot to FundPromo as who, the way a wallet does.
func fund(cur realm, who address, n int64) {
	syncVault()
	testing.IssueCoins(realmAddr, ugnots(n))
	testing.SetOriginSend(ugnots(n))
	testing.SetRealm(testing.NewUserRealm(who))
	FundPromo(cross(cur))
	testing.SetOriginSend(nil)
}

// reserve, payPick and unreserve call the catalog as the radio realm.
func reserve(cur realm, id int, who address, end int64) int64 {
	testing.SetRealm(testing.NewCodeRealm(radioPath()))
	amt, _ := PromoReserve(cross(cur), id, who, end)
	return amt
}

// gen is the funding generation of track id's artist's budget now.
func gen(id int) int {
	t := rd()
	artistID, _, _, _, _ := brief(t, id)
	b, _ := getBudget(t, artistID)
	return b.Gen
}

func payPick(cur realm, id int, who address, end, amt int64) {
	syncVault()
	testing.SetRealm(testing.NewCodeRealm(radioPath()))
	PromoClaim(cross(cur), id, who, end, amt, gen(id))
}

func unreserve(cur realm, id int, who address, end, amt, reserved int64) {
	testing.SetRealm(testing.NewCodeRealm(radioPath()))
	PromoRelease(cross(cur), id, who, end, amt, reserved, gen(id))
}

// accounted: this realm holds nothing, the vault holds what it owes.
func accounted(t *testing.T) {
	t.Helper()
	uassert.Equal(t, int64(0), balance(realmAddr))
	uassert.True(t, balance(dataAddr) >= data.VaultTotal())
}

func free(artistID int) int64 {
	_, _, f := data.VaultInfo(acct(artistID))
	return f
}

// withdraw takes what the funder may from an artist's vault account.
func withdraw(cur realm, funder address, artistID int) {
	syncVault()
	testing.SetRealm(testing.NewUserRealm(funder))
	data.VaultWithdraw(cross(cur), acct(artistID))
}

func TestFundPromo(cur realm, t *testing.T) {
	alice, _, aid, _ := promoTrack(cur)
	carol, dave := who("carol"), who("dave")
	// Guards: coins only from a wallet call, in ugnot, within bounds, from a verified owner.
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

	testing.SetRealm(testing.NewUserRealm(dave))
	RegisterArtist(cross(cur), name("Unverified Dave"), "")
	testing.SetOriginSend(ugnots(ugnot))
	uassert.AbortsContains(t, cur, "verify your profile first", func() { FundPromo(cross(cur)) })
	testing.SetOriginSend(nil)

	// A first budget below one refund could never pay a pick.
	syncVault()
	testing.SetRealm(testing.NewUserRealm(alice))
	testing.SetOriginSend(ugnots(defaultPickPay - 1))
	uassert.AbortsContains(t, cur, "fund at least one pick", func() { FundPromo(cross(cur)) })
	testing.SetOriginSend(nil)
	fund(cur, alice, 2*ugnot)
	uassert.Equal(t, int64(defaultPickPay), PromoOffer(aid))
	// The default refund covers what a sponsored pick costs the listener
	// (radio/v1 gas filetests, 100 ugnot a byte): the pick's fee at 80M gas
	// and its 1,206-byte deposit, the collect's fee at 40M less the 513
	// bytes it frees.
	uassert.True(t, defaultPickPay >= 80_000+1_206*100+40_000-513*100)
	fund(cur, alice, ugnot)
	js := PromoJSON(aid)
	urequire.True(t, strings.Contains(js, `"funder":"`+alice.String()+`","balance":3000000,"reserved":0,"free":3000000,"pay":200000,"perDay":10,"today":0,"funded":3000000,"paid":0,"picks":0,"offer":200000`), js)
	urequire.True(t, strings.Contains(ArtistJSON(aid), `"sponsor":200000`), ArtistJSON(aid))
	accounted(t)
}

func TestSetPromoPay(cur realm, t *testing.T) {
	alice, _, aid, _ := promoTrack(cur)
	testing.SetRealm(testing.NewUserRealm(alice))
	uassert.AbortsContains(t, cur, "0.01 to 0.5 GNOT", func() { SetPromoPay(cross(cur), 500_001, 0) })
	uassert.AbortsContains(t, cur, "0.01 to 0.5 GNOT", func() { SetPromoPay(cross(cur), 9_999, 0) })
	uassert.AbortsContains(t, cur, "daily limit", func() { SetPromoPay(cross(cur), 20_000, 101) })
	testing.SetRealm(testing.NewUserRealm(who("carol")))
	uassert.AbortsContains(t, cur, "create your artist profile", func() { SetPromoPay(cross(cur), 20_000, 0) })
	fund(cur, alice, ugnot)
	testing.SetRealm(testing.NewUserRealm(alice))
	SetPromoPay(cross(cur), 500_000, 2)
	uassert.Equal(t, int64(500_000), PromoOffer(aid))
	SetPromoPay(cross(cur), 10_000, 2)
	uassert.Equal(t, int64(10_000), PromoOffer(aid))
	SetPromoPay(cross(cur), 0, 0) // paused
	uassert.Equal(t, int64(0), PromoOffer(aid))
}

// A reservation leaves the free balance, is paid once the radio says the pick
// aired, and lapses back to the budget after 7 days.
func TestSponsoredPickMoney(cur realm, t *testing.T) {
	alice, bob, aid, id := promoTrack(cur)
	carol, fan1, fan2 := who("carol"), who("fan1"), who("fan2")
	testing.SetRealm(testing.NewUserRealm(alice))
	SetPromoPay(cross(cur), 30_000, 0)
	fund(cur, alice, 100_000)
	end := now() + 300

	testing.SetRealm(testing.NewUserRealm(carol))
	uassert.AbortsContains(t, cur, "only the GnoRadio radio realm", func() { PromoReserve(cross(cur), id, carol, end) })
	uassert.AbortsContains(t, cur, "only the GnoRadio radio realm", func() { PromoClaim(cross(cur), id, carol, end, 30_000, 0) })
	uassert.AbortsContains(t, cur, "only the GnoRadio radio realm", func() { PromoRelease(cross(cur), id, carol, end, 30_000, 0, 0) })

	// Never the artist, a collaborator or a GnoRadio realm.
	testing.SetRealm(testing.NewCodeRealm(radioPath()))
	uassert.AbortsContains(t, cur, "collaborators", func() { PromoReserve(cross(cur), id, alice, end) })
	uassert.AbortsContains(t, cur, "collaborators", func() { PromoReserve(cross(cur), id, bob, end) })
	uassert.AbortsContains(t, cur, "collaborators", func() { PromoReserve(cross(cur), id, chain.PackageAddress(radioPath()), end) })
	uassert.AbortsContains(t, cur, "collaborators", func() { PromoReserve(cross(cur), id, dataAddr, end) })

	got := reserve(cur, id, carol, end)
	uassert.Equal(t, int64(30_000), got)
	uassert.Equal(t, int64(70_000), free(aid))
	// The reserved part cannot be withdrawn.
	withdraw(cur, alice, aid)
	uassert.Equal(t, int64(70_000), balance(alice))
	uassert.AbortsContains(t, cur, "nothing of yours", func() { withdraw(cur, alice, aid) })
	accounted(t)

	uassert.True(t, PromoClaimable(id, end, 30_000, 0))
	uassert.False(t, PromoClaimable(id, end, 30_001, 0))
	payPick(cur, id, carol, end, 30_000)
	uassert.Equal(t, int64(30_000), balance(carol))
	// Once only: the reservation is gone.
	uassert.False(t, PromoClaimable(id, end, 30_000, 0))
	testing.SetRealm(testing.NewCodeRealm(radioPath()))
	uassert.AbortsContains(t, cur, "cancelled", func() { PromoClaim(cross(cur), id, carol, end, 30_000, 0) })
	js := PromoJSON(aid)
	urequire.True(t, strings.Contains(js, `"balance":0,"reserved":0,"free":0`), js)
	urequire.True(t, strings.Contains(js, `"paid":30000,"picks":1,"offer":0`), js)
	accounted(t)

	// Empty budget: no reservation.
	testing.SetRealm(testing.NewCodeRealm(radioPath()))
	uassert.AbortsContains(t, cur, "budget is empty", func() { PromoReserve(cross(cur), id, fan1, end) })

	// A release returns the reservation at once; an unclaimed one lapses after 7 days.
	fund(cur, alice, 100_000)
	reserve(cur, id, fan1, end)
	unreserve(cur, id, fan1, end, 30_000, 0)
	uassert.Equal(t, int64(100_000), free(aid))
	reserve(cur, id, fan2, end)
	uassert.Equal(t, int64(70_000), free(aid))
	testing.SkipHeights((claimDays*daySecs + daySecs) / 5)
	uassert.Equal(t, int64(100_000), free(aid))
	uassert.False(t, PromoClaimable(id, end, 30_000, 0)) // lapsed
	testing.SetRealm(testing.NewCodeRealm(radioPath()))
	uassert.AbortsContains(t, cur, "within 7 days", func() { PromoClaim(cross(cur), id, fan2, end, 30_000, 0) })
	accounted(t)
}

// A catalog pause longer than the claim window voids no refund: the
// window runs on the vault's clock, which a pause stops.
func TestPauseKeepsRefunds(cur realm, t *testing.T) {
	alice, _, _, id := promoTrack(cur)
	carol := who("carol")
	fund(cur, alice, ugnot)
	end := now() + 300
	amt := reserve(cur, id, carol, end)
	pause(cur, true)
	testing.SkipHeights((claimDays*daySecs + 2*daySecs) / 5)
	pause(cur, false)
	uassert.True(t, PromoClaimable(id, end, amt, gen(id)))
	payPick(cur, id, carol, end, amt)
	uassert.Equal(t, amt, balance(carol))
	accounted(t)
}

// Per listener: one sponsored pick per artist a day, three a day in all; per
// artist: the daily limit the artist chose.
func TestSponsoredPickCaps(cur realm, t *testing.T) {
	alice, _, aid, id := promoTrack(cur)
	carol, fan1, fan2 := who("carol"), who("fan1"), who("fan2")
	fund(cur, alice, ugnot)
	end := now() + 300
	reserve(cur, id, carol, end)
	testing.SetRealm(testing.NewCodeRealm(radioPath()))
	uassert.AbortsContains(t, cur, "one sponsored pick per artist a day", func() { PromoReserve(cross(cur), id, carol, end) })
	// Three other artists for the wallet cap.
	var ids []int
	for i := 0; i < 3; i++ {
		w, a := artist(cur, "cap")
		ids = append(ids, publish(cur, w, "Cap Song"))
		verified(cur, a)
		fund(cur, w, ugnot)
	}
	reserve(cur, ids[0], carol, end)
	reserve(cur, ids[1], carol, end)
	testing.SetRealm(testing.NewCodeRealm(radioPath()))
	uassert.AbortsContains(t, cur, "three sponsored picks a day", func() { PromoReserve(cross(cur), ids[2], carol, end) })
	// The next day the caps start again.
	testing.SkipHeights(daySecs / 5)
	reserve(cur, ids[2], carol, now()+300)

	// The artist's own daily limit.
	testing.SetRealm(testing.NewUserRealm(alice))
	SetPromoPay(cross(cur), 20_000, 1)
	reserve(cur, id, fan1, now()+300)
	uassert.Equal(t, int64(0), PromoOffer(aid))
	testing.SetRealm(testing.NewCodeRealm(radioPath()))
	uassert.AbortsContains(t, cur, "taken, pick it normally", func() { PromoReserve(cross(cur), id, fan2, now()+300) })
	accounted(t)
}

// A pause stops new sponsored picks; hidden or unverified: none either. The
// funder still withdraws, even while the catalog is paused, and nobody else can.
func TestPromoHiddenAndPaused(cur realm, t *testing.T) {
	alice, _, aid, id := promoTrack(cur)
	carol := who("carol")
	fund(cur, alice, ugnot)
	pause(cur, true)
	testing.SetRealm(testing.NewCodeRealm(radioPath()))
	uassert.AbortsContains(t, cur, "catalog is paused", func() { PromoReserve(cross(cur), id, carol, now()+300) })
	pause(cur, false)
	testing.SetRealm(testing.NewUserRealm(boss))
	HideArtist(cross(cur), aid, true, "test")
	uassert.Equal(t, int64(0), PromoOffer(aid))
	testing.SetRealm(testing.NewCodeRealm(radioPath()))
	uassert.AbortsContains(t, cur, "catalog: unknown track", func() { PromoReserve(cross(cur), id, carol, now()+300) })
	testing.SetRealm(testing.NewUserRealm(boss))
	HideArtist(cross(cur), aid, false, "")
	Verify(cross(cur), aid, false)
	testing.SetRealm(testing.NewCodeRealm(radioPath()))
	uassert.AbortsContains(t, cur, "does not sponsor", func() { PromoReserve(cross(cur), id, carol, now()+300) })
	pause(cur, true)
	uassert.AbortsContains(t, cur, "nothing of yours", func() { withdraw(cur, boss, aid) })
	withdraw(cur, alice, aid)
	uassert.Equal(t, int64(ugnot), balance(alice))
	pause(cur, false)
	accounted(t)
}

// A profile that changes hands: the old funder keeps their money; the new
// owner's first funding refunds them, reservations included (cancelled).
func TestPromoOwnershipChange(cur realm, t *testing.T) {
	carol, fan1, fan2 := who("carol"), who("fan1"), who("fan2")
	testing.SetRealm(testing.NewUserRealm(boss))
	aid := CreateArtist(cross(cur), OriginCurated, name("Handed Over"), "", "")
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
	uassert.AbortsContains(t, cur, "nothing of yours", func() { withdraw(cur, fan2, aid) })

	f0 := balance(fan1)
	fund(cur, fan2, 500_000)
	uassert.Equal(t, int64(ugnot), balance(fan1)-f0)
	testing.SetRealm(testing.NewCodeRealm(radioPath()))
	uassert.AbortsContains(t, cur, "cancelled", func() { PromoClaim(cross(cur), tid, carol, end, 30_000, 0) })
	uassert.Equal(t, int64(defaultPickPay), PromoOffer(aid))
	accounted(t)
}

// Audit: a budget that goes back to an earlier funder within the 7 days
// starts a new funding generation. A reservation of the first funding is
// void: it is neither paid from nor released into the hold a later
// listener's reservation for the same day put in the vault.
func TestPromoBackToSameFunder(cur realm, t *testing.T) {
	carol, fan1, fan2, fan3 := who("carol"), who("fan1"), who("fan2"), who("fan3")
	testing.SetRealm(testing.NewUserRealm(boss))
	aid := CreateArtist(cross(cur), OriginCurated, name("Round Trip"), "", "")
	tid := ImportTrack(cross(cur), aid, "Round Song", 5, "2:00", "CC0", "", ia, sha, "", "", "https://archive.org/details/r", "Round Trip")
	AssignArtist(cross(cur), aid, fan1)
	fund(cur, fan1, ugnot)
	end := now() + 300
	reserve(cur, tid, carol, end)
	uassert.Equal(t, 0, gen(tid))

	for _, owner := range []address{fan2, fan1} { // there and back
		testing.SetRealm(testing.NewUserRealm(boss))
		ResetOwner(cross(cur), aid)
		AssignArtist(cross(cur), aid, owner)
		fund(cur, owner, ugnot)
	}
	uassert.Equal(t, 2, gen(tid))
	reserve(cur, tid, fan3, end) // the same lapse day as carol's
	acct := acct(aid)
	uassert.Equal(t, int64(defaultPickPay), data.VaultHeld(acct, lapseDay(end)))

	// The funder is the same as at carol's reservation, the day's hold is
	// there, but carol's generation is gone.
	uassert.False(t, PromoClaimable(tid, end, defaultPickPay, 0))
	testing.SetRealm(testing.NewCodeRealm(radioPath()))
	uassert.AbortsContains(t, cur, "cancelled", func() { PromoClaim(cross(cur), tid, carol, end, defaultPickPay, 0) })
	PromoRelease(cross(cur), tid, carol, end, defaultPickPay, 0, 0)
	uassert.Equal(t, int64(defaultPickPay), data.VaultHeld(acct, lapseDay(end)))
	uassert.True(t, PromoClaimable(tid, end, defaultPickPay, 2))
	payPick(cur, tid, fan3, end, defaultPickPay)
	uassert.Equal(t, int64(0), data.VaultHeld(acct, lapseDay(end)))
	accounted(t)
}

// A tip can never spend the budgets' coins: they are in the vault.
func TestTipCannotSpendBudgets(cur realm, t *testing.T) {
	alice, _, _, id := promoTrack(cur)
	fund(cur, alice, ugnot)
	testing.SetRealm(testing.NewCodeRealm(radioPath()))
	uassert.AbortsContains(t, cur, "did not arrive", func() { RadioTip(cross(cur), id, 0, who("carol"), "", "", ugnot) })
	accounted(t)
}

// A pick released before it aired gives back the daily counts it took, the
// artist's and the picker's; one that partly aired keeps them.
func TestPromoReleaseGivesBackCounts(cur realm, t *testing.T) {
	alice, _, aid, id := promoTrack(cur)
	fan1, fan2 := who("fan1"), who("fan2")
	fund(cur, alice, ugnot)
	testing.SetRealm(testing.NewUserRealm(alice))
	SetPromoPay(cross(cur), 30_000, 1)
	end := now() + 300
	reserve(cur, id, fan1, end)
	uassert.Equal(t, int64(0), PromoOffer(aid)) // the artist's one a day is taken
	unreserve(cur, id, fan1, end, 30_000, now())
	uassert.Equal(t, int64(30_000), PromoOffer(aid))
	reserve(cur, id, fan1, end) // the picker's one per artist a day is back too
	unreserve(cur, id, fan1, end, 30_000, 0)
	uassert.Equal(t, int64(0), PromoOffer(aid))
	testing.SetRealm(testing.NewCodeRealm(radioPath()))
	uassert.AbortsContains(t, cur, "taken, pick it normally", func() { PromoReserve(cross(cur), id, fan2, end) })
	// Released the next day: yesterday's reservation gives back no count of today's.
	yesterday := now()
	end2 := now() + daySecs
	testing.SkipHeights(daySecs / 5)
	reserve(cur, id, fan2, end2)
	unreserve(cur, id, fan2, end2, 0, yesterday)
	uassert.Equal(t, int64(0), PromoOffer(aid))
	accounted(t)
}

// A budget refunds at most defaultPerDay picks a day unless its artist sets
// another limit (0 keeps the default): a farming script drains it slowly.
func TestDefaultDailyCap(cur realm, t *testing.T) {
	alice, _, aid, id := promoTrack(cur)
	fund(cur, alice, 3*ugnot) // 15 refunds
	for i := 0; i < defaultPerDay; i++ {
		reserve(cur, id, who("farm"), now()+300)
	}
	uassert.Equal(t, int64(0), PromoOffer(aid))
	testing.SetRealm(testing.NewCodeRealm(radioPath()))
	uassert.AbortsContains(t, cur, "taken, pick it normally", func() { PromoReserve(cross(cur), id, who("farm"), now()+300) })
	testing.SetRealm(testing.NewUserRealm(alice))
	SetPromoPay(cross(cur), defaultPickPay, 0)
	uassert.True(t, strings.Contains(PromoJSON(aid), `"perDay":10,`))
	SetPromoPay(cross(cur), defaultPickPay, 11)
	reserve(cur, id, who("farm"), now()+300)
	accounted(t)
}
