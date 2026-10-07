package catalog

import (
	"chain"
	"strings"
	"testing"

	"gno.land/p/gnoradio/store/v0"
	"gno.land/p/nt/testutils/v0"
	"gno.land/p/nt/uassert/v0"
)

var (
	picker   = testutils.TestAddress("picker")
	referrer = testutils.TestAddress("referrer")
)

// promoTrack publishes a verified track of alice with bob as a 30%
// collaborator and returns its id.
func promoTrack(cur realm) int {
	reset()
	resetSupport()
	promo = store.NewMap(16)
	testing.SetRealm(testing.NewUserRealm(alice))
	RegisterArtist(cross(cur), "Promo Alice", "")
	id := PublishTrack(cross(cur), "Promo Song", 2, "1:40", "CC-BY", "none", "", ipfs, "", "", "", bob.String()+":30", "yes")
	verified(cur, 1)
	return id
}

// radioTip calls RadioTip as the radio realm after it forwarded total.
func radioTip(cur realm, id, supportPct int, tipper, pk, ref address, total int64) (int64, int64) {
	testing.IssueCoins(realmAddr, ugnots(total))
	testing.SetRealm(testing.NewCodeRealm(radioRealm))
	return RadioTip(cross(cur), id, supportPct, tipper, pk, ref, total)
}

func TestPromoShareSetting(cur realm, t *testing.T) {
	promoTrack(cur)
	uassert.Equal(t, 5, PromoShare(1)) // default
	uassert.True(t, strings.Contains(ArtistJSON(1), `"promo":5`))
	testing.SetRealm(testing.NewUserRealm(alice))
	uassert.AbortsContains(t, cur, "between 0 and 20%", func() { SetPromoShare(cross(cur), 21) })
	uassert.AbortsContains(t, cur, "between 0 and 20%", func() { SetPromoShare(cross(cur), -1) })
	SetPromoShare(cross(cur), 0)
	uassert.Equal(t, 0, PromoShare(1))
	SetPromoShare(cross(cur), 20)
	uassert.Equal(t, 20, PromoShare(1))
	testing.SetRealm(testing.NewUserRealm(carol))
	uassert.AbortsContains(t, cur, "create your artist profile", func() { SetPromoShare(cross(cur), 10) })
	testing.SetRealm(testing.NewCodeRealm("gno.land/r/evil/proxy"))
	uassert.AbortsContains(t, cur, "directly from your wallet", func() { SetPromoShare(cross(cur), 10) })
}

// Only the radio realm may pay a tip for someone else.
func TestRadioTipGuard(cur realm, t *testing.T) {
	id := promoTrack(cur)
	testing.SetRealm(testing.NewUserRealm(carol))
	uassert.AbortsContains(t, cur, "only the GnoRadio radio realm", func() { RadioTip(cross(cur), id, 0, carol, picker, "", ugnot) })
	testing.SetRealm(testing.NewCodeRealm("gno.land/r/gnoradio/radio/v1"))
	uassert.AbortsContains(t, cur, "only the GnoRadio radio realm", func() { RadioTip(cross(cur), id, 0, carol, picker, "", ugnot) })
	testing.SetRealm(testing.NewCodeRealm("gno.land/r/gnoradio/radio/v0/evil"))
	uassert.AbortsContains(t, cur, "only the GnoRadio radio realm", func() { RadioTip(cross(cur), id, 0, carol, picker, "", ugnot) })
	// The radio cannot route around the tip rules either.
	uassert.AbortsContains(t, cur, "own track", func() { radioTip(cur, id, 0, alice, picker, "", ugnot) })
	uassert.AbortsContains(t, cur, "between 0.1", func() { radioTip(cur, id, 0, carol, picker, "", 10) })
}

// A radio v1 can take over RadioTip without a new catalog, and every
// GnoRadio realm, old or new, stays unable to receive coins.
func TestRadioRealmUpgrade(cur realm, t *testing.T) {
	id := promoTrack(cur)
	v1 := "gno.land/r/gnoradio/radio/v1"
	testing.SetRealm(testing.NewUserRealm(carol))
	uassert.AbortsContains(t, cur, "admin only", func() { SetRadioRealm(cross(cur), v1) })
	testing.SetRealm(testing.NewUserRealm(boss))
	uassert.AbortsContains(t, cur, "invalid realm path", func() { SetRadioRealm(cross(cur), "gno.land/p/x") })
	SetRadioRealm(cross(cur), v1)
	uassert.Equal(t, v1, RadioRealm())

	testing.IssueCoins(realmAddr, ugnots(ugnot))
	testing.SetRealm(testing.NewCodeRealm("gno.land/r/gnoradio/radio/v0"))
	uassert.AbortsContains(t, cur, "only the GnoRadio radio realm", func() { RadioTip(cross(cur), id, 0, carol, picker, "", ugnot) })
	// v0 and v1 are both siblings: never a referrer, a treasury or a collaborator.
	toP, toR := radioTip(cur, id, 0, carol, picker, chain.PackageAddress(v1), ugnot)
	uassert.Equal(t, int64(50_000), toP)
	uassert.Equal(t, int64(0), toR)
	testing.SetRealm(testing.NewUserRealm(boss))
	uassert.AbortsContains(t, cur, "cannot be a GnoRadio realm", func() { SetTreasury(cross(cur), chain.PackageAddress(v1)) })
	uassert.AbortsContains(t, cur, "cannot be a GnoRadio realm", func() { SetTreasury(cross(cur), chain.PackageAddress("gno.land/r/gnoradio/radio/v0")) })

	// SetSibling adds or removes any other realm (tickets v1 here).
	tv1 := "gno.land/r/gnoradio/tickets/v1"
	SetSibling(cross(cur), tv1, true)
	uassert.True(t, isSibling(chain.PackageAddress(tv1)))
	testing.SetRealm(testing.NewUserRealm(alice))
	uassert.AbortsContains(t, cur, "collaborators as", func() {
		PublishTrack(cross(cur), "Split", 2, "1:40", "CC-BY", "none", "", ipfs, "", "", "", chain.PackageAddress(tv1).String()+":30", "yes")
	})
	uassert.AbortsContains(t, cur, "collaborators as", func() {
		PublishTrack(cross(cur), "Split", 2, "1:40", "CC-BY", "none", "", ipfs, "", "", "", chain.PackageAddress("gno.land/r/gnoradio/home/v0").String()+":30", "yes")
	})
	testing.SetRealm(testing.NewUserRealm(boss))
	SetSibling(cross(cur), tv1, false)
	uassert.False(t, isSibling(chain.PackageAddress(tv1)))
	uassert.Equal(t, 4, len(SiblingRealms())) // radio, tickets, home v0 + radio v1
}

func TestRadioTipSplits(cur realm, t *testing.T) {
	id := promoTrack(cur)
	testing.SetRealm(testing.NewUserRealm(alice))
	SetPromoShare(cross(cur), 10)

	// 11 GNOT, 10% to GnoRadio: artist side 10, promo 10% = 1 GNOT, half to
	// the picker, half to the referrer; the 9 left split 70/30.
	a0, b0, p0, r0, d0 := balance(alice), balance(bob), balance(picker), balance(referrer), balance(dave)
	toP, toR := radioTip(cur, id, 10, carol, picker, referrer, 11*ugnot)
	uassert.Equal(t, int64(ugnot/2), toP)
	uassert.Equal(t, int64(ugnot/2), toR)
	uassert.Equal(t, int64(ugnot/2), balance(picker)-p0)
	uassert.Equal(t, int64(ugnot/2), balance(referrer)-r0)
	uassert.Equal(t, int64(6_300_000), balance(alice)-a0)
	uassert.Equal(t, int64(2_700_000), balance(bob)-b0)
	uassert.Equal(t, int64(ugnot), balance(dave)-d0)
	uassert.Equal(t, int64(0), balance(realmAddr))
	uassert.Equal(t, int64(9*ugnot), getTrack(id).Tips) // what the artist side received
	uassert.Equal(t, int64(10*ugnot), getUser(carol).Tipped)
	uassert.Equal(t, 1, len(TippedPage(carol, 0, 10))) // the distinct-supporter set, for a successor
	uassert.Equal(t, id, TippedPage(carol, 0, 10)[0])

	// Rounding: an odd share gives the extra ugnot to the picker, nothing is left.
	testing.SetRealm(testing.NewUserRealm(alice))
	SetPromoShare(cross(cur), 5)
	p0, r0 = balance(picker), balance(referrer)
	toP, toR = radioTip(cur, id, 0, carol, picker, referrer, 1_000_020) // share 50_001
	uassert.Equal(t, int64(25_001), toP)
	uassert.Equal(t, int64(25_000), toR)
	uassert.Equal(t, toP, balance(picker)-p0)
	uassert.Equal(t, int64(0), balance(realmAddr))

	// One of them alone takes the whole share.
	toP, toR = radioTip(cur, id, 0, carol, picker, "", 2*ugnot)
	uassert.Equal(t, int64(100_000), toP)
	uassert.Equal(t, int64(0), toR)
	toP, toR = radioTip(cur, id, 0, carol, "", referrer, 2*ugnot)
	uassert.Equal(t, int64(0), toP)
	uassert.Equal(t, int64(100_000), toR)
}

// No share to the tipper, the artist, a GnoRadio realm, or when the artist
// set 0%; a direct tip has none either.
func TestRadioTipNoShare(cur realm, t *testing.T) {
	id := promoTrack(cur)
	cases := []struct {
		pk, ref address
		toP     int64
		toR     int64
	}{
		{carol, referrer, 0, 50_000}, // the picker tips: the referrer alone
		{alice, "", 0, 0},            // the artist picked their own track
		{picker, carol, 50_000, 0},   // a tipper cannot refer themselves
		{picker, alice, 50_000, 0},   // nor the artist
		{picker, picker, 50_000, 0},  // picker and referrer at once: one share
		{"", chain.PackageAddress("gno.land/r/gnoradio/radio/v0"), 0, 0},
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
	toP, toR := radioTip(cur, id, 0, carol, picker, referrer, ugnot)
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
