package catalog

import (
	"chain"
	"strings"
	"testing"

	"gno.land/p/gnoradio/text/v0"
	"gno.land/p/nt/uassert/v0"
	"gno.land/r/gnoradio/data"
)

func TestPromoShareSetting(cur realm, t *testing.T) {
	alice, _, aid, _ := promoTrack(cur)
	uassert.Equal(t, 0, PromoShare(aid)) // opt-in: off until the artist sets it
	uassert.True(t, strings.Contains(ArtistJSON(aid), `"promo":0`))
	testing.SetRealm(testing.NewUserRealm(alice))
	uassert.AbortsContains(t, cur, "between 0 and 20%", func() { SetPromoShare(cross(cur), 21) })
	uassert.AbortsContains(t, cur, "between 0 and 20%", func() { SetPromoShare(cross(cur), -1) })
	SetPromoShare(cross(cur), 0)
	uassert.Equal(t, 0, PromoShare(aid))
	SetPromoShare(cross(cur), 20)
	uassert.Equal(t, 20, PromoShare(aid))
	testing.SetRealm(testing.NewUserRealm(who("carol")))
	uassert.AbortsContains(t, cur, "create your artist profile", func() { SetPromoShare(cross(cur), 10) })
	testing.SetRealm(testing.NewCodeRealm("gno.land/r/evil/proxy"))
	uassert.AbortsContains(t, cur, "directly from your wallet", func() { SetPromoShare(cross(cur), 10) })
}

// Only the radio writer of the data realm may pay a tip for someone else.
func TestRadioTipGuard(cur realm, t *testing.T) {
	alice, _, _, id := promoTrack(cur)
	carol, picker := who("carol"), who("picker")
	testing.SetRealm(testing.NewUserRealm(carol))
	uassert.AbortsContains(t, cur, "only the GnoRadio radio realm", func() { RadioTip(cross(cur), id, 0, carol, picker, "", ugnot) })
	testing.SetRealm(testing.NewCodeRealm("gno.land/r/gnoradio/radio/v0"))
	uassert.AbortsContains(t, cur, "only the GnoRadio radio realm", func() { RadioTip(cross(cur), id, 0, carol, picker, "", ugnot) })
	testing.SetRealm(testing.NewCodeRealm(radioPath() + "/evil"))
	uassert.AbortsContains(t, cur, "only the GnoRadio radio realm", func() { RadioTip(cross(cur), id, 0, carol, picker, "", ugnot) })
	// The radio cannot route around the tip rules either.
	uassert.AbortsContains(t, cur, "own track", func() { radioTip(cur, id, 0, alice, picker, "", ugnot) })
	uassert.AbortsContains(t, cur, "between 0.1", func() { radioTip(cur, id, 0, carol, picker, "", 10) })
}

func TestRadioTipSplits(cur realm, t *testing.T) {
	alice, bob, _, id := promoTrack(cur)
	dave := treasuryTo(cur)
	carol, picker, referrer := who("carol"), who("picker"), who("referrer")
	testing.SetRealm(testing.NewUserRealm(alice))
	SetPromoShare(cross(cur), 10)

	// 11 GNOT, 10% to GnoRadio: artist side 10, promo 10% = 1 GNOT, half to
	// the picker, half to the referrer; the 9 left split 70/30.
	toP, toR := radioTip(cur, id, 10, carol, picker, referrer, 11*ugnot)
	uassert.Equal(t, int64(ugnot/2), toP)
	uassert.Equal(t, int64(ugnot/2), toR)
	uassert.Equal(t, int64(ugnot/2), balance(picker))
	uassert.Equal(t, int64(ugnot/2), balance(referrer))
	uassert.Equal(t, int64(6_300_000), balance(alice))
	uassert.Equal(t, int64(2_700_000), balance(bob))
	uassert.Equal(t, int64(ugnot), balance(dave))
	uassert.Equal(t, int64(0), balance(realmAddr))
	uassert.Equal(t, int64(9*ugnot), getTrack(rd(), id).Tips)  // what the artist side received
	uassert.Equal(t, int64(9*ugnot), user(rd(), carol).Tipped) // the artist side, promo shares out
	uassert.Equal(t, 1, getTrack(rd(), id).Supporters)

	// Rounding: an odd share gives the extra ugnot to the picker, nothing is left.
	testing.SetRealm(testing.NewUserRealm(alice))
	SetPromoShare(cross(cur), 5)
	p0, r0 := balance(picker), balance(referrer)
	toP, toR = radioTip(cur, id, 0, carol, picker, referrer, 1_000_020) // share 50_001
	uassert.Equal(t, int64(25_001), toP)
	uassert.Equal(t, int64(25_000), toR)
	uassert.Equal(t, toP, balance(picker)-p0)
	uassert.Equal(t, toR, balance(referrer)-r0)
	uassert.Equal(t, int64(0), balance(realmAddr))
	uassert.Equal(t, 1, getTrack(rd(), id).Supporters) // carol is counted once

	// One of them alone takes the whole share.
	toP, toR = radioTip(cur, id, 0, carol, picker, "", 2*ugnot)
	uassert.Equal(t, int64(100_000), toP)
	uassert.Equal(t, int64(0), toR)
	toP, toR = radioTip(cur, id, 0, carol, "", referrer, 2*ugnot)
	uassert.Equal(t, int64(0), toP)
	uassert.Equal(t, int64(100_000), toR)
}

// No share to the tipper, the artist, a GnoRadio realm, or when the artist
// set 0% (the default); a direct tip has none either.
func TestRadioTipNoShare(cur realm, t *testing.T) {
	alice, _, _, id := promoTrack(cur)
	carol, picker, referrer := who("carol"), who("picker"), who("referrer")
	toP, toR := radioTip(cur, id, 0, carol, picker, referrer, ugnot)
	uassert.Equal(t, int64(0), toP+toR) // never set: 0%
	testing.SetRealm(testing.NewUserRealm(alice))
	SetPromoShare(cross(cur), 5)
	cases := []struct {
		pk, ref address
		toP     int64
		toR     int64
	}{
		// Audit (TipOnAir self-dealing): the picker tips their own pick, so
		// nobody brought them, and a link they name (their second wallet)
		// earns nothing either.
		{carol, referrer, 0, 0},
		{carol, "", 0, 0},
		{"", referrer, 0, 50_000},   // nobody picked it: the referrer alone
		{alice, "", 0, 0},           // the artist picked their own track
		{picker, carol, 50_000, 0},  // a tipper cannot refer themselves
		{picker, alice, 50_000, 0},  // nor the artist
		{picker, picker, 50_000, 0}, // picker and referrer at once: one share
		{"", chain.PackageAddress(radioPath()), 0, 0},
		{"", chain.PackageAddress("gno.land/r/gnoradio/data"), 0, 0},
		{"", realmAddr, 0, 0},
		{"", "not-an-address", 0, 0},
	}
	for _, c := range cases {
		toP, toR := radioTip(cur, id, 0, carol, c.pk, c.ref, ugnot)
		uassert.Equal(t, c.toP, toP)
		uassert.Equal(t, c.toR, toR)
		uassert.Equal(t, int64(0), balance(realmAddr))
	}
	testing.SetRealm(testing.NewUserRealm(alice))
	SetPromoShare(cross(cur), 0)
	toP, toR = radioTip(cur, id, 0, carol, picker, referrer, ugnot)
	uassert.Equal(t, int64(0), toP+toR)

	testing.SetRealm(testing.NewUserRealm(alice))
	SetPromoShare(cross(cur), 20)
	p0 := balance(picker)
	testing.IssueCoins(realmAddr, ugnots(ugnot))
	testing.SetOriginSend(ugnots(ugnot))
	testing.SetRealm(testing.NewUserRealm(carol))
	TipWithSupport(cross(cur), id, 0)
	testing.SetOriginSend(nil)
	uassert.Equal(t, p0, balance(picker))
}

// A radio release takes over RadioTip without a new catalog: the guard reads
// the data realm's radio writer, and the old radio is refused once the new
// one is in force.
func TestRadioRealmUpgrade(cur realm, t *testing.T) {
	alice, _, _, id := promoTrack(cur)
	carol, picker := who("carol"), who("picker")
	testing.SetRealm(testing.NewUserRealm(alice))
	SetPromoShare(cross(cur), 5)
	old := radioPath()
	next := "gno.land/r/gnoradio/radio/v" + text.Itoa(seq+2)
	testing.SetRealm(testing.NewUserRealm(dataOwner))
	data.Propose(cross(cur), "radio", next)
	testing.SetRealm(testing.NewCodeRealm(next))
	data.Ready(cross(cur))
	testing.SkipHeights(data.DELAY/5 + 1)
	uassert.Equal(t, next, radioPath())
	verified(cur, getTrack(rd(), id).Artist) // any write puts the release in force
	toP, _ := radioTip(cur, id, 0, carol, picker, "", ugnot)
	uassert.Equal(t, int64(50_000), toP)
	testing.IssueCoins(realmAddr, ugnots(ugnot))
	testing.SetRealm(testing.NewCodeRealm(old))
	uassert.AbortsContains(t, cur, "only the GnoRadio radio realm", func() { RadioTip(cross(cur), id, 0, carol, picker, "", ugnot) })
	// Old and new radio realms alike can never receive coins.
	testing.SetRealm(testing.NewUserRealm(boss))
	uassert.AbortsContains(t, cur, "cannot be a GnoRadio realm", func() { SetTreasury(cross(cur), chain.PackageAddress(old)) })
	uassert.AbortsContains(t, cur, "cannot be a GnoRadio realm", func() { SetTreasury(cross(cur), chain.PackageAddress(next)) })
}
