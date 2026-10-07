package radio

import (
	"strings"
	"testing"

	"gno.land/p/nt/testutils/v0"
	"gno.land/p/nt/uassert/v0"
	"gno.land/p/nt/urequire/v0"
	"gno.land/r/gnoradio/catalog/v0"
)

// promoCalls records what the radio asked the catalog (stand-ins: the money
// itself is tested in catalog/sponsor_test.gno).
var (
	promoCalls []string
	claimable  bool // what the catalog says of a refund to collect
)

func stubPromo() {
	promoCalls = nil
	promoReserve = func(cur realm, trackID int, picker address, end int64) int64 {
		promoCalls = append(promoCalls, "reserve "+itoa(trackID)+" "+picker.String()+" "+itoa64(end))
		return 30_000
	}
	promoClaim = func(cur realm, trackID int, picker address, end, amount int64) {
		promoCalls = append(promoCalls, "claim "+itoa(trackID)+" "+picker.String()+" "+itoa64(end)+" "+itoa64(amount))
	}
	promoRelease = func(cur realm, trackID int, picker address, end, amount, reserved int64) {
		aired := "aired"
		if reserved > 0 {
			aired = "unaired"
		}
		promoCalls = append(promoCalls, "release "+itoa(trackID)+" "+itoa64(end)+" "+itoa64(amount)+" "+picker.String()+" "+aired)
	}
	claimable = true
	promoClaimable = func(trackID int, end, amount int64) bool { return claimable }
}

// trust gives addr the reputation sponsored picks need.
func trust(addr address) {
	ts := now()
	putCurator(addr.String(), []int64{3, 0, 0, 0, ts - repAge, ts / repPeriod, repPicks, 0})
}

// sponsorSetup publishes one-minute tracks on station 5 for a fresh artist.
func sponsorSetup(cur realm, name string, n int) []int {
	reset()
	resetCurators()
	stubPromo()
	testing.SetRealm(testing.NewUserRealm(testutils.TestAddress(name)))
	catalog.RegisterArtist(cross(cur), name, "")
	var ids []int
	for i := 0; i < n; i++ {
		ids = append(ids, publish(cur, name+" "+itoa(i), 5, "1:00"))
	}
	testing.SetRealm(testing.NewUserRealm(dave))
	Sync(cross(cur), 50)
	return ids
}

// A wallet earns sponsored picks: a first pick 7 days old and 3 normal picks
// in the last two 15-day periods.
func TestSponsorReputation(cur realm, t *testing.T) {
	ids := sponsorSetup(cur, "Rep Artist", 3)
	uassert.Equal(t, "sponsored picks open 7 days after your first pick", sponsorBlock(carol))
	testing.SetRealm(testing.NewUserRealm(carol))
	uassert.AbortsContains(t, cur, "7 days after your first pick", func() { QueueSponsored(cross(cur), 5, ids[0]) })
	Queue(cross(cur), 5, ids[0])
	testing.SkipHeights(repAge / 5)
	uassert.Equal(t, "sponsored picks need 3 normal picks in the last 30 days", sponsorBlock(carol))
	for _, st := range []int{MainStation, ChoiceStation} {
		testing.SetRealm(testing.NewUserRealm(carol))
		Queue(cross(cur), st, ids[1])
	}
	uassert.Equal(t, "", sponsorBlock(carol))
	// Two periods later the old picks no longer count.
	testing.SkipHeights(2 * repPeriod / 5)
	uassert.Equal(t, "sponsored picks need 3 normal picks in the last 30 days", sponsorBlock(carol))
	js := SponsoredJSON(carol)
	urequire.True(t, strings.Contains(js, `"block":"sponsored picks need 3`), js)
}

// The pick is reserved when queued, paid once it aired in full, once.
func TestSponsoredPickLifecycle(cur realm, t *testing.T) {
	ids := sponsorSetup(cur, "Life Artist", 2)
	trust(carol)
	testing.SetRealm(testing.NewUserRealm(carol))
	QueueSponsored(cross(cur), 5, ids[0])
	_, _, sched := StationState(5)
	var s Slot
	for _, x := range sched {
		if x.By == carol {
			s = x
		}
	}
	urequire.Equal(t, int64(30_000), s.Pay)
	end := s.Start + s.Dur
	urequire.Equal(t, 1, len(promoCalls))
	uassert.Equal(t, "reserve "+itoa(ids[0])+" "+carol.String()+" "+itoa64(end), promoCalls[0])
	js := ScheduleJSON(5, 3600)
	urequire.True(t, strings.Contains(js, `"by":"`+carol.String()+`","note":"","sponsored":30000`), js)
	urequire.True(t, strings.Contains(SponsoredJSON(carol), `"open":[{"station":5,"start":`+itoa64(s.Start)), SponsoredJSON(carol))
	// Paid by the artist: no curator point, no Listeners' choice, but the cooldown holds.
	uassert.Equal(t, 3, CuratorOf(carol).Picks)
	_, inChoice := homesOf(ids[0])[ChoiceStation]
	uassert.False(t, inChoice)
	uassert.Equal(t, "sponsored", Activities(1)[0].Kind)
	uassert.True(t, lastPickAt(carol, 5) > 0)

	// Not before it has aired in full, not by someone else.
	uassert.AbortsContains(t, cur, "not finished airing", func() { ClaimPickPayout(cross(cur), 5, s.Start) })
	testing.SkipHeights((end - now()) / 5)
	if now() < end {
		testing.SkipHeights(1)
	}
	testing.SetRealm(testing.NewUserRealm(dave))
	uassert.AbortsContains(t, cur, "no sponsored pick of yours", func() { ClaimPickPayout(cross(cur), 5, s.Start) })
	testing.SetRealm(testing.NewUserRealm(carol))
	uassert.AbortsContains(t, cur, "no sponsored pick of yours", func() { ClaimPickPayout(cross(cur), 5, s.Start+1) })
	// One open sponsored pick per station: collect it before the next.
	testing.SkipHeights(queueCooldown / 5)
	uassert.AbortsContains(t, cur, "collect your last sponsored pick", func() { QueueSponsored(cross(cur), 5, ids[1]) })
	ClaimPickPayout(cross(cur), 5, s.Start)
	urequire.Equal(t, 2, len(promoCalls))
	uassert.Equal(t, "claim "+itoa(ids[0])+" "+carol.String()+" "+itoa64(end)+" 30000", promoCalls[1])
	uassert.Equal(t, int64(30_000), CuratorOf(carol).Promo)
	urequire.True(t, strings.Contains(CuratorJSON(carol), `"promo":30000`), CuratorJSON(carol))
	// Once per slot.
	uassert.AbortsContains(t, cur, "no sponsored pick of yours", func() { ClaimPickPayout(cross(cur), 5, s.Start) })
	uassert.Equal(t, 2, len(promoCalls))
}

// A sponsored slot removed before its end gives the reservation back.
func TestSponsoredPickDropped(cur realm, t *testing.T) {
	ids := sponsorSetup(cur, "Cut Sponsor", 1)
	testing.SetRealm(testing.NewUserRealm(testutils.TestAddress("dropother")))
	catalog.RegisterArtist(cross(cur), "Cut Other", "")
	ids = append(ids, publish(cur, "Cut Other Song", 5, "1:00"))
	testing.SetRealm(testing.NewUserRealm(dave))
	Sync(cross(cur), 50)
	trust(carol)
	trust(bob)
	testing.SetRealm(testing.NewUserRealm(carol))
	QueueSponsored(cross(cur), 5, ids[0])
	testing.SetRealm(testing.NewUserRealm(bob))
	QueueSponsored(cross(cur), 5, ids[1])
	_, _, sched := StationState(5)
	var c, b Slot
	for _, x := range sched {
		if x.By == carol {
			c = x
		}
		if x.By == bob {
			b = x
		}
	}
	urequire.True(t, c.Pay > 0 && b.Pay > 0)

	testing.SetRealm(testing.NewUserRealm(erin)) // radio admin
	Unqueue(cross(cur), 5, ids[1])               // not started: removed
	uassert.Equal(t, "release "+itoa(ids[1])+" "+itoa64(b.Start+b.Dur)+" 30000 "+bob.String()+" unaired", promoCalls[len(promoCalls)-1])
	testing.SetRealm(testing.NewUserRealm(bob))
	uassert.AbortsContains(t, cur, "no sponsored pick of yours", func() { ClaimPickPayout(cross(cur), 5, b.Start) })

	// carol's pick: cut while on air.
	if now() < c.Start {
		testing.SkipHeights((c.Start-now())/5 + 1)
	}
	urequire.True(t, now() < c.Start+c.Dur)
	uassert.Equal(t, int64(30_000), OnAirPay(5))
	n := len(promoCalls)
	testing.SetRealm(testing.NewUserRealm(erin))
	Unqueue(cross(cur), 5, ids[0])
	urequire.Equal(t, n+1, len(promoCalls))
	uassert.Equal(t, "release "+itoa(ids[0])+" "+itoa64(c.Start+c.Dur)+" 30000 "+carol.String()+" aired", promoCalls[n])
	testing.SkipHeights(30)
	testing.SetRealm(testing.NewUserRealm(carol))
	uassert.AbortsContains(t, cur, "no sponsored pick of yours", func() { ClaimPickPayout(cross(cur), 5, c.Start) })
}

// One sponsored pick per artist per station and hour; sponsored airtime at
// most a quarter of the 2-hour listener window.
func TestSponsoredQuotas(cur realm, t *testing.T) {
	ids := sponsorSetup(cur, "Quota Artist", 2)
	for _, a := range []address{carol, bob} {
		trust(a)
	}
	testing.SetRealm(testing.NewUserRealm(carol))
	QueueSponsored(cross(cur), 5, ids[0])
	testing.SetRealm(testing.NewUserRealm(bob))
	uassert.AbortsContains(t, cur, "sponsored pick this hour here", func() { QueueSponsored(cross(cur), 5, ids[1]) })
	Queue(cross(cur), 5, ids[1]) // a normal pick of the same artist is fine

	// Long tracks of other artists fill the sponsored quarter (1800 s).
	var long []int
	for i := 0; i < 2; i++ {
		testing.SetRealm(testing.NewUserRealm(testutils.TestAddress("longartist" + itoa(i))))
		catalog.RegisterArtist(cross(cur), "Long Sponsor "+itoa(i), "")
		long = append(long, publish(cur, "Long "+itoa(i), 5, "15:00"))
	}
	testing.SetRealm(testing.NewUserRealm(dave))
	Sync(cross(cur), 50)
	f1, f2 := testutils.TestAddress("fan1"), testutils.TestAddress("fan2")
	trust(f1)
	trust(f2)
	testing.SetRealm(testing.NewUserRealm(f1))
	QueueSponsored(cross(cur), 5, long[0]) // 60 + 900 s
	testing.SetRealm(testing.NewUserRealm(f2))
	uassert.AbortsContains(t, cur, "sponsored picks are full", func() { QueueSponsored(cross(cur), 5, long[1]) })
	Queue(cross(cur), 5, long[1])
}
