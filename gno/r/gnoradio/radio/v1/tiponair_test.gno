package radio

import (
	"chain"
	"strings"
	"testing"

	"gno.land/p/gnoradio/text/v0"
	"gno.land/p/nt/testutils/v0"
	"gno.land/p/nt/uassert/v0"
	"gno.land/p/nt/urequire/v0"
	"gno.land/r/gnoradio/catalog/v1"
)

// tipOnAir tips as tipper with n ugnot attached, the way a wallet does.
func tipOnAir(cur realm, tipper address, stationID, trackID int, ref address, n int64) {
	testing.IssueCoins(radioAddr, ugnots(n))
	testing.SetOriginSend(ugnots(n))
	testing.SetRealm(testing.NewUserRealm(tipper))
	TipOnAir(cross(cur), stationID, trackID, 0, ref)
	testing.SetOriginSend(nil)
}

// onAirSetup publishes two one-minute tracks on station 5 (by an artist the
// catalog admin verified, with a 5% promo share, unless not) and lets
// carol's pick of the first reach the air.
func onAirSetup(cur realm, name string, verified bool) (a, b int) {
	reset(cur)
	testing.SetRealm(testing.NewUserRealm(testutils.TestAddress(name)))
	aid := catalog.RegisterArtist(cross(cur), name, "")
	a = publish(cur, name+" A", 5, "1:00")
	b = publish(cur, name+" B", 5, "1:00")
	if verified {
		testing.SetRealm(testing.NewUserRealm(boss))
		catalog.Verify(cross(cur), aid, true)
		testing.SetRealm(testing.NewUserRealm(testutils.TestAddress(name)))
		catalog.SetPromoShare(cross(cur), 5) // opt-in: 0% by default
	}
	testing.SetRealm(testing.NewUserRealm(carol))
	Sync(cross(cur), 50)
	Queue(cross(cur), 5, a)
	testing.SkipHeights(12) // the rotation's track ends first
	return a, b
}

// A tip while carol's pick is on air credits her: the radio finds her in its
// own schedule, the client never names her. The coins go through the
// catalog, which splits the artist's promo share (5%) between the picker and
// the referrer; neither rules realm keeps any.
func TestTipOnAirFindsThePicker(cur realm, t *testing.T) {
	a, b := onAirSetup(cur, "Tip On Air Artist", true)
	id, _, queued := NowPlaying(5)
	urequire.Equal(t, a, id)
	urequire.True(t, queued)

	owner := testutils.TestAddress("Tip On Air Artist")
	c0, r0, o0 := balance(carol), balance(bob), balance(owner)
	tipOnAir(cur, dave, 5, a, bob, 2*ugnot)
	uassert.Equal(t, int64(50_000), balance(carol)-c0)
	uassert.Equal(t, int64(50_000), balance(bob)-r0)
	uassert.Equal(t, int64(1_900_000), balance(owner)-o0)
	uassert.Equal(t, int64(0), balance(radioAddr))
	uassert.Equal(t, int64(0), balance(catalogAddr))

	c := CuratorOf(carol)
	uassert.Equal(t, 1, c.Picks)
	uassert.Equal(t, 1, c.Tips)
	uassert.Equal(t, int64(50_000), c.Earned)
	top := TopCurators(5)
	urequire.Equal(t, 1, len(top))
	uassert.Equal(t, carol, top[0].Address)
	uassert.Equal(t, 1, len(TopCurators(allStations)))
	js := CuratorJSON(carol)
	urequire.True(t, strings.Contains(js, `"picks":1,"tips":1,"earned":50000,"promo":0,"week":{"picks":1,"tips":1,"earned":50000,"rank":1}`), js)
	js = TopCuratorsJSON(5)
	urequire.True(t, strings.Contains(js, `"top":[{"address":"`+carol.String()+`","picks":1,"tips":1,"earned":50000}]`), js)

	// Not the track of the pick on air: no picker (Main simulcasting it: TestTipOnMainPaysSimulcastPicker).
	c0 = balance(carol)
	tipOnAir(cur, dave, 5, b, "", ugnot)
	tipOnAir(cur, dave, MainStation, b, "", ugnot)
	uassert.Equal(t, c0, balance(carol))

	// Up to two minutes after the pick ends it still counts, then no longer.
	testing.SkipHeights(12 + 20) // the pick's 60 s, then 100 s
	tipOnAir(cur, dave, 5, a, "", ugnot)
	uassert.Equal(t, int64(50_000), balance(carol)-c0)
	testing.SkipHeights(10)
	tipOnAir(cur, dave, 5, a, "", ugnot)
	uassert.Equal(t, int64(50_000), balance(carol)-c0)
	uassert.Equal(t, 2, CuratorOf(carol).Tips)
}

// Audit (TipOnAir self-dealing): the picker tipping their own pick on air
// pays no promo share, to themselves or to a referrer they name.
func TestTipOnAirOwnPick(cur realm, t *testing.T) {
	a, _ := onAirSetup(cur, "Own Pick Artist", true)
	owner := testutils.TestAddress("Own Pick Artist")
	c0, r0, o0 := balance(carol), balance(bob), balance(owner)
	tipOnAir(cur, carol, 5, a, bob, 2*ugnot)
	uassert.Equal(t, int64(0), balance(carol)-c0) // the test issues the tip to the radio
	uassert.Equal(t, int64(0), balance(bob)-r0)
	uassert.Equal(t, int64(2*ugnot), balance(owner)-o0)
	uassert.Equal(t, 0, CuratorOf(carol).Tips)
	uassert.Equal(t, int64(0), balance(radioAddr)+balance(catalogAddr))
}

func TestTipOnAirGuards(cur realm, t *testing.T) {
	a, b := onAirSetup(cur, "Tip Guard Artist", false)
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

	// The catalog's own rules apply: this artist never verified.
	uassert.AbortsContains(t, cur, "has not verified", func() { tipOnAir(cur, dave, 5, a, "", ugnot) })
	testing.SetOriginSend(nil) // left by the aborted tip

	// The admin's curator picks earn nothing.
	testing.SetRealm(testing.NewUserRealm(boss))
	catalog.Verify(cross(cur), catalog.ArtistOf(testutils.TestAddress("Tip Guard Artist")), true)
	testing.SetRealm(testing.NewUserRealm(erin))
	CuratorQueue(cross(cur), 5, b)
	testing.SkipHeights(13) // after carol's pick
	id, _, _ := NowPlaying(5)
	urequire.Equal(t, b, id)
	e0 := balance(erin)
	tipOnAir(cur, dave, 5, b, "", ugnot)
	uassert.Equal(t, e0, balance(erin))
	uassert.Equal(t, 0, CuratorOf(erin).Picks)
}

// A sponsored pick on air earns its picker no promo share and no curator point.
func TestTipOnAirSkipsSponsored(cur realm, t *testing.T) {
	sp := sponsorSetup(cur, "Tip Sponsored", 2)
	picker := testutils.TestAddress("tipspfan")
	trust(cur, picker)
	testing.SetRealm(testing.NewUserRealm(picker))
	QueueSponsored(cross(cur), 5, sp.ids[0])
	testing.SkipHeights(12)
	id, _, _ := NowPlaying(5)
	urequire.Equal(t, sp.ids[0], id)
	p0 := balance(picker)
	tipOnAir(cur, dave, 5, sp.ids[0], "", ugnot)
	uassert.Equal(t, p0, balance(picker))
	uassert.Equal(t, 0, CuratorOf(picker).Tips)
}

// The weekly top keeps the ten best, highest first, and starts over each week.
func TestWeeklyTop(cur realm, t *testing.T) {
	reset(cur)
	credits := func(who address, stationID, picks, tips int, earned int64) {
		edit(cur, func(t *tx) { credit(t, who, stationID, picks, tips, earned) })
	}
	for i := 1; i <= 12; i++ {
		who := testutils.TestAddress("curator" + text.Itoa(i))
		for j := 0; j < i; j++ {
			credits(who, 3, 1, 0, 0)
		}
	}
	top := TopCurators(3)
	uassert.Equal(t, topCurators, len(top))
	uassert.Equal(t, testutils.TestAddress("curator12"), top[0].Address)
	uassert.Equal(t, 12, top[0].Picks)
	uassert.Equal(t, 3, top[9].Picks)
	credits(testutils.TestAddress("curator1"), 3, 0, 5, 10) // 1 pick + 5 tips = 6 points, after curator6
	uassert.Equal(t, testutils.TestAddress("curator1"), TopCurators(3)[7].Address)
	uassert.Equal(t, 0, len(TopCurators(4)))
	uassert.Equal(t, 12, CuratorOf(testutils.TestAddress("curator12")).Picks)

	testing.SkipHeights(7 * 24 * 720) // a week of 5 s blocks
	uassert.Equal(t, 0, len(TopCurators(3)))
	credits(testutils.TestAddress("curator2"), 3, 1, 0, 0)
	top = TopCurators(3)
	uassert.Equal(t, 1, len(top))
	uassert.Equal(t, 1, top[0].Picks) // this week's picks only
	uassert.Equal(t, 3, CuratorOf(testutils.TestAddress("curator2")).Picks)
	uassert.Equal(t, int64(1_794_182_400), weekOf(1_794_268_800)*week-3*24*3600) // Tuesday 10 Nov 2026: the week starts Monday 9 Nov 00:00 UTC
}

// Main simulcasting station 5 while carol's pick plays there shows it as
// her pick, and a tip sent from Main pays her the promo share, exactly as a
// tip from station 5 does.
func TestTipOnMainPaysSimulcastPicker(cur realm, t *testing.T) {
	a, _ := onAirSetup(cur, "Main Tip Artist", true)
	urequire.Equal(t, 5, hourGenre(rd(), now()))
	id, _, queued := NowPlaying(MainStation)
	urequire.Equal(t, a, id)
	uassert.True(t, queued)
	js := ScheduleJSON(MainStation, 600)
	uassert.True(t, strings.Contains(js, `"queued":true,"by":"`+carol.String()+`"`), js)
	c0 := balance(carol)
	tipOnAir(cur, dave, MainStation, a, "", 2*ugnot)
	uassert.Equal(t, int64(100_000), balance(carol)-c0)
	top := TopCurators(5) // ranked on station 5, where her pick lives
	urequire.Equal(t, 1, len(top))
	uassert.Equal(t, 1, top[0].Tips)
	uassert.Equal(t, 0, len(TopCurators(MainStation)))
}
