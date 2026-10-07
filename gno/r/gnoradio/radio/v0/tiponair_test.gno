package radio

import (
	"chain"
	"chain/banker"
	"strings"
	"testing"

	"gno.land/p/gnoradio/store/v0"
	"gno.land/p/nt/testutils/v0"
	"gno.land/p/nt/uassert/v0"
	"gno.land/p/nt/urequire/v0"
	"gno.land/r/gnoradio/catalog/v0"
)

var (
	radioAddr   = chain.PackageAddress("gno.land/r/gnoradio/radio/v0")
	catalogAddr = chain.PackageAddress("gno.land/r/gnoradio/catalog/v0")
)

const ugnot = 1_000_000

func ugnots(n int64) chain.Coins { return chain.Coins{{Denom: "ugnot", Amount: n}} }

func balance(addr address) int64 {
	return banker.NewReadonlyBanker().GetCoins(addr).AmountOf("ugnot")
}

// tipOnAir tips as tipper with n ugnot attached, the way a wallet does.
func tipOnAir(cur realm, tipper address, stationID, trackID int, ref address, n int64) {
	testing.IssueCoins(radioAddr, ugnots(n))
	testing.SetOriginSend(ugnots(n))
	testing.SetRealm(testing.NewUserRealm(tipper))
	TipOnAir(cross(cur), stationID, trackID, 0, ref)
	testing.SetOriginSend(nil)
}

func resetCurators() {
	curators = store.NewMap(64)
	tops = [ChoiceStation + 2]weekTop{}
}

// paid records what the radio handed the catalog; the stand-in pays the
// picker 5% (the split itself is tested in catalog/promo_test.gno).
var paid struct {
	tipper, picker, ref address
	track               int
	total               int64
}

func stubCatalog() {
	radioTip = func(cur realm, trackID, supportPct int, tipper, picker, ref address, total int64) (int64, int64) {
		paid.tipper, paid.picker, paid.ref, paid.track, paid.total = tipper, picker, ref, trackID, total
		if picker == "" {
			return 0, 0
		}
		return total / 20, 0
	}
}

// onAirSetup publishes two one-minute tracks on station 5 and lets carol's
// pick of the first reach the air.
func onAirSetup(cur realm, name string) (a, b int) {
	reset()
	resetCurators()
	stubCatalog()
	testing.SetRealm(testing.NewUserRealm(testutils.TestAddress(name)))
	catalog.RegisterArtist(cross(cur), name, "")
	a = publish(cur, name+" A", 5, "1:00")
	b = publish(cur, name+" B", 5, "1:00")
	testing.SetRealm(testing.NewUserRealm(carol))
	Sync(cross(cur), 50)
	Queue(cross(cur), 5, a)
	testing.SkipHeights(12) // the rotation's track ends first
	return a, b
}

// A tip while carol's pick is on air credits her: the radio finds her in its
// own schedule, the client never names her. The coins go to the catalog.
func TestTipOnAirFindsThePicker(cur realm, t *testing.T) {
	a, b := onAirSetup(cur, "Tip On Air Artist")
	id, _, queued := NowPlaying(5)
	urequire.Equal(t, a, id)
	urequire.True(t, queued)

	c0 := balance(catalogAddr)
	tipOnAir(cur, dave, 5, a, bob, 2*ugnot)
	uassert.Equal(t, int64(2*ugnot), balance(catalogAddr)-c0)
	uassert.Equal(t, int64(0), balance(radioAddr))
	uassert.Equal(t, dave, paid.tipper)
	uassert.Equal(t, carol, paid.picker)
	uassert.Equal(t, bob, paid.ref)
	uassert.Equal(t, a, paid.track)
	uassert.Equal(t, int64(2*ugnot), paid.total)

	c := CuratorOf(carol)
	uassert.Equal(t, 1, c.Picks)
	uassert.Equal(t, 1, c.Tips)
	uassert.Equal(t, int64(100_000), c.Earned)
	top := TopCurators(5)
	urequire.Equal(t, 1, len(top))
	uassert.Equal(t, carol, top[0].Address)
	uassert.Equal(t, 1, len(TopCurators(allStations)))
	js := CuratorJSON(carol)
	urequire.True(t, strings.Contains(js, `"picks":1,"tips":1,"earned":100000,"promo":0,"week":{"picks":1,"tips":1,"earned":100000,"rank":1}`), js)
	js = TopCuratorsJSON(5)
	urequire.True(t, strings.Contains(js, `"top":[{"address":"`+carol.String()+`","picks":1,"tips":1,"earned":100000}]`), js)

	// Not a pick on air on that station: no picker.
	tipOnAir(cur, dave, 5, b, "", ugnot)
	uassert.Equal(t, address(""), paid.picker)
	tipOnAir(cur, dave, MainStation, a, "", ugnot)
	uassert.Equal(t, address(""), paid.picker)

	// Up to two minutes after the pick ends it still counts, then no longer.
	testing.SkipHeights(12 + 20) // the pick's 60 s, then 100 s
	tipOnAir(cur, dave, 5, a, "", ugnot)
	uassert.Equal(t, carol, paid.picker)
	testing.SkipHeights(10)
	tipOnAir(cur, dave, 5, a, "", ugnot)
	uassert.Equal(t, address(""), paid.picker)
	uassert.Equal(t, 2, CuratorOf(carol).Tips)
}

func TestTipOnAirGuards(cur realm, t *testing.T) {
	a, b := onAirSetup(cur, "Tip Guard Artist")
	testing.SetRealm(testing.NewUserRealm(dave))
	uassert.AbortsContains(t, cur, "amount in ugnot", func() { TipOnAir(cross(cur), 5, a, 0, "") })
	testing.SetOriginSend(chain.Coins{{Denom: "foo", Amount: ugnot}})
	uassert.AbortsContains(t, cur, "amount in ugnot", func() { TipOnAir(cross(cur), 5, a, 0, "") })
	testing.SetOriginSend(ugnots(ugnot))
	testing.SetRealm(testing.NewCodeRealm("gno.land/r/evil/proxy"))
	uassert.AbortsContains(t, cur, "directly from your wallet", func() { TipOnAir(cross(cur), 5, a, 0, "") })
	testing.SetOriginSend(nil)
	uassert.AbortsContains(t, cur, "unknown station", func() { tipOnAir(cur, dave, 99, a, "", ugnot) })
	testing.SetOriginSend(nil)

	// Through the real catalog: the radio passes its guard and the catalog's
	// own rules apply (this test artist never verified).
	radioTip = catalog.RadioTip
	uassert.AbortsContains(t, cur, "has not verified", func() { tipOnAir(cur, dave, 5, a, "", ugnot) })
	stubCatalog()
	testing.SetOriginSend(nil) // left by the aborted tip

	// The admin's curator picks earn nothing.
	testing.SetRealm(testing.NewUserRealm(erin))
	CuratorQueue(cross(cur), 5, b)
	testing.SkipHeights(13) // after carol's pick
	id, _, _ := NowPlaying(5)
	urequire.Equal(t, b, id)
	tipOnAir(cur, dave, 5, b, "", ugnot)
	uassert.Equal(t, address(""), paid.picker)
	uassert.Equal(t, 0, CuratorOf(erin).Picks)
}

// The weekly top keeps the ten best, highest first, and starts over each week.
func TestWeeklyTop(t *testing.T) {
	resetCurators()
	for i := 1; i <= 12; i++ {
		who := testutils.TestAddress("curator" + itoa(i))
		for j := 0; j < i; j++ {
			credit(who, 3, 1, 0, 0)
		}
	}
	top := TopCurators(3)
	uassert.Equal(t, topCurators, len(top))
	uassert.Equal(t, testutils.TestAddress("curator12"), top[0].Address)
	uassert.Equal(t, 12, top[0].Picks)
	uassert.Equal(t, 3, top[9].Picks)
	credit(testutils.TestAddress("curator1"), 3, 0, 5, 10) // 1 pick + 5 tips = 6 points, after curator6
	uassert.Equal(t, testutils.TestAddress("curator1"), TopCurators(3)[7].Address)
	uassert.Equal(t, 0, len(TopCurators(4)))
	uassert.Equal(t, 12, CuratorOf(testutils.TestAddress("curator12")).Picks)

	testing.SkipHeights(7 * 24 * 720) // a week of 5 s blocks
	uassert.Equal(t, 0, len(TopCurators(3)))
	credit(testutils.TestAddress("curator2"), 3, 1, 0, 0)
	top = TopCurators(3)
	uassert.Equal(t, 1, len(top))
	uassert.Equal(t, 1, top[0].Picks) // this week's picks only
	uassert.Equal(t, 3, CuratorOf(testutils.TestAddress("curator2")).Picks)
	uassert.Equal(t, int64(1_794_182_400), weekOf(1_794_268_800)*week-3*24*3600) // Tuesday 10 Nov 2026: the week starts Monday 9 Nov 00:00 UTC
}
