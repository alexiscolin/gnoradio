package radio

import (
	"strings"
	"testing"

	"gno.land/p/nt/testutils/v0"
	"gno.land/p/nt/uassert/v0"
	"gno.land/p/nt/urequire/v0"
	"gno.land/r/gnoradio/catalog/v0"
)

// A sponsored slot moved since its reservation releases the end the catalog
// filed it under, not its new one.
func TestSponsoredReleaseKeepsHeldEnd(cur realm, t *testing.T) {
	ids := sponsorSetup(cur, "Held Sponsor", 1)
	trust(carol)
	testing.SetRealm(testing.NewUserRealm(carol))
	QueueSponsored(cross(cur), 5, ids[0])
	st := stations[5]
	k := -1
	for i, s := range st.schedule {
		if s.By == carol {
			k = i
		}
	}
	urequire.True(t, k >= 0)
	held := st.schedule[k].Start + st.schedule[k].Dur
	st.move(k, st.schedule[k].Start+600) // pushed back, as by a booked pick before it
	testing.SetRealm(testing.NewUserRealm(erin))
	Unqueue(cross(cur), 5, ids[0])
	uassert.Equal(t, "release "+itoa(ids[0])+" "+itoa64(held)+" 30000 "+carol.String()+" unaired", promoCalls[len(promoCalls)-1])
}

// A booked pick keeps the replay gap between its end and its fold.
func TestBookedReplayGapBeforeFold(cur realm, t *testing.T) {
	reset()
	testing.SetRealm(testing.NewUserRealm(testutils.TestAddress("gap_artist")))
	catalog.RegisterArtist(cross(cur), "Gap Artist", "")
	a := publish(cur, "Gap A", 5, "1:00")
	publish(cur, "Gap B", 5, "1:00")
	testing.SetRealm(testing.NewUserRealm(carol))
	Sync(cross(cur), 50)
	testing.SetRealm(testing.NewUserRealm(fan(1)))
	QueueAt(cross(cur), 5, a, now()+20*60)
	testing.SkipHeights(30 * 60 / 5) // aired and ended, not folded yet
	_, ok := lastPicked(5, a)
	urequire.False(t, ok)
	testing.SetRealm(testing.NewUserRealm(fan(2)))
	uassert.AbortsContains(t, cur, "less than 3 hours ago", func() { Queue(cross(cur), 5, a) })
}

// A sponsored pick on air earns its picker no promo share and no curator point.
func TestTipOnAirSkipsSponsored(cur realm, t *testing.T) {
	a, _ := onAirSetupSponsored(cur, "Tip Sponsored Artist")
	id, _, _ := NowPlaying(5)
	urequire.Equal(t, a, id)
	tipOnAir(cur, dave, 5, a, "", ugnot)
	uassert.Equal(t, address(""), paid.picker)
	uassert.Equal(t, 0, CuratorOf(carol).Tips)
}

func onAirSetupSponsored(cur realm, name string) (a, b int) {
	reset()
	resetCurators()
	stubCatalog()
	stubPromo()
	testing.SetRealm(testing.NewUserRealm(testutils.TestAddress(name)))
	catalog.RegisterArtist(cross(cur), name, "")
	a = publish(cur, name+" A", 5, "1:00")
	b = publish(cur, name+" B", 5, "1:00")
	testing.SetRealm(testing.NewUserRealm(carol))
	Sync(cross(cur), 50)
	trust(carol)
	QueueSponsored(cross(cur), 5, a)
	testing.SkipHeights(12)
	return a, b
}

// Nothing left to pay (cancelled, lapsed or removed): the record goes, so the
// next sponsored pick on the station is open at once.
func TestClaimPickPayoutVoid(cur realm, t *testing.T) {
	ids := sponsorSetup(cur, "Void Sponsor", 2)
	trust(carol)
	testing.SetRealm(testing.NewUserRealm(carol))
	QueueSponsored(cross(cur), 5, ids[0])
	start := int64(0)
	for _, s := range stations[5].schedule {
		if s.By == carol {
			start = s.Start
		}
	}
	testing.SkipHeights(queueCooldown/5 + 1)
	claimable = false
	n := len(promoCalls)
	ClaimPickPayout(cross(cur), 5, start)
	uassert.Equal(t, n, len(promoCalls)) // nothing claimed
	_, open := sponsor.Get(sponsorKey(5, carol))
	uassert.False(t, open)
	uassert.Equal(t, int64(0), CuratorOf(carol).Promo)
	testing.SkipHeights(sponsorWindow / 5) // the artist's sponsored hour here is over
	QueueSponsored(cross(cur), 5, ids[1])
}

// RestoreNote takes back the strike its hide gave, and only that one.
func TestRestoreNoteKeepsEarlierStrike(cur realm, t *testing.T) {
	reset()
	testing.SetRealm(testing.NewUserRealm(testutils.TestAddress("strike_artist")))
	catalog.RegisterArtist(cross(cur), "Strike Artist", "")
	tracks := []int{publish(cur, "Strike A", 3, "3:00"), publish(cur, "Strike B", 3, "3:00")}
	testing.SetRealm(testing.NewUserRealm(carol))
	Sync(cross(cur), 50)
	// No earlier strike: restoring leaves none.
	start := hideNote(cur, tracks[0])
	testing.SetRealm(testing.NewUserRealm(erin))
	RestoreNote(cross(cur), MainStation, start)
	_, struck := strikes.Get(alice.String())
	uassert.False(t, struck)
	// An earlier strike (older than the mute window) survives a restore.
	earlier := itoa64(now() - muteFor - 100)
	strikes.Set(alice.String(), earlier)
	testing.SkipHeights(720)
	start = hideNote(cur, tracks[1])
	last, _ := strikes.Get(alice.String())
	uassert.NotEqual(t, earlier, last)
	testing.SetRealm(testing.NewUserRealm(erin))
	RestoreNote(cross(cur), MainStation, start)
	last, _ = strikes.Get(alice.String())
	uassert.Equal(t, earlier, last)
}

// hideNote has alice dedicate a pick of track on Main and three listeners hide it.
func hideNote(cur realm, track int) int64 {
	testing.SetRealm(testing.NewUserRealm(alice))
	dedicate(cur, MainStation, track, "for Marie")
	s := stations[MainStation].schedule[slotOf(stations[MainStation], track)]
	for _, who := range []string{"k1", "k2", "k3"} {
		picked(who)
		testing.SetRealm(testing.NewUserRealm(testutils.TestAddress(who)))
		ReportNote(cross(cur), MainStation, s.Start)
	}
	return s.Start
}

// StationsJSON tells the app which tracks New still takes.
func TestStationsJSONNewFloor(t *testing.T) {
	reset()
	floor := synced - newCap
	if floor < 0 {
		floor = 0
	}
	uassert.True(t, strings.Contains(StationsJSON(), `"newFloor":`+itoa(floor)+`,`))
}

// longSetup publishes a 3-minute track and n 15-minute ones on genre 5, one
// artist each, so picks for now can wait close to two hours.
func longSetup(cur realm, name string, n int) (a int, long []int) {
	ids := bookSetup(cur, name, 5, 1)
	for i := 0; i < n; i++ {
		testing.SetRealm(testing.NewUserRealm(testutils.TestAddress(name + "long" + itoa(i))))
		catalog.RegisterArtist(cross(cur), name+" Long "+itoa(i), "")
		long = append(long, publish(cur, name+" Long Song "+itoa(i), 5, "15:00"))
	}
	testing.SetRealm(testing.NewUserRealm(dave))
	Sync(cross(cur), 50)
	return ids[0], long
}

// The replay gap counts from when a pick for now really airs, not from when
// it was queued: behind 105 minutes of picks, it airs within 3 hours of a
// booking queued for 4 h 30 from now.
func TestReplayGapFromNowPickStart(cur realm, t *testing.T) {
	a, long := longSetup(cur, "GapNow", 7)
	ts := now()
	testing.SetRealm(testing.NewUserRealm(fan(1)))
	QueueAt(cross(cur), 5, a, ts+4*3600+1800)
	for i, id := range long {
		testing.SetRealm(testing.NewUserRealm(fan(10 + i)))
		Queue(cross(cur), 5, id)
	}
	testing.SetRealm(testing.NewUserRealm(fan(2)))
	uassert.AbortsContains(t, cur, "already programmed", func() { Queue(cross(cur), 5, a) })
}

// The other way round: a pick for now records its airing time, so once it is
// folded a booking 2 h 45 after it airs is refused although it is more than
// 3 hours after the pick was queued.
func TestReplayGapRecordsNowPickStart(cur realm, t *testing.T) {
	a, long := longSetup(cur, "GapRec", 7)
	for i, id := range long {
		testing.SetRealm(testing.NewUserRealm(fan(10 + i)))
		Queue(cross(cur), 5, id)
	}
	ts := now()
	testing.SetRealm(testing.NewUserRealm(fan(1)))
	Queue(cross(cur), 5, a)
	s := slotBy(stations[5], fan(1))
	urequire.True(t, s.Start-ts > 6000)
	last, _ := lastPicked(5, a)
	uassert.Equal(t, s.Start, last)
	testing.SkipHeights((s.Start+s.Dur+foldAfter-now())/5 + 1)
	at := s.Start + 2*3600 + 2700
	urequire.True(t, at-ts >= replayGap && at >= now()+bookMin)
	testing.SetRealm(testing.NewUserRealm(fan(2)))
	uassert.AbortsContains(t, cur, "less than 3 hours ago", func() { QueueAt(cross(cur), 5, a, at) })
}

// A pick for now that waits for a rotation track after a gap (its
// predecessors were unqueued) still starts at the end of that track when a
// booked pick goes in before it and pushes the rotation back: nothing is cut,
// and its replay record follows it.
func TestRealignNowPickAfterGap(cur realm, t *testing.T) {
	ids := bookSetup(cur, "GapAlign", 5, 9)
	testing.SetRealm(testing.NewUserRealm(testutils.TestAddress("gapalignshort")))
	catalog.RegisterArtist(cross(cur), "GapAlign Short", "")
	short := publish(cur, "GapAlign Short Song", 5, "2:00")
	testing.SetRealm(testing.NewUserRealm(dave))
	Sync(cross(cur), 50)
	ts := now()
	for i := 0; i < 8; i++ {
		testing.SetRealm(testing.NewUserRealm(fan(20 + i)))
		Queue(cross(cur), 5, ids[i])
	}
	testing.SetRealm(testing.NewUserRealm(erin))
	for i := 0; i < 7; i++ {
		Unqueue(cross(cur), 5, ids[i])
	}
	st := stations[5]
	n := slotBy(st, fan(27))
	urequire.True(t, n.Start >= ts+20*60)
	testing.SetRealm(testing.NewUserRealm(fan(1)))
	QueueAt(cross(cur), 5, short, ts+15*60)
	b := slotBy(st, fan(1))
	urequire.True(t, b.Start+b.Dur < n.Start) // in the gap, before the pick for now
	moved := slotBy(st, fan(27))
	uassert.True(t, onBoundary(st, moved))
	uassert.True(t, moved.Start > n.Start)
	last, _ := lastPicked(5, ids[7])
	uassert.Equal(t, moved.Start, last)
}

// A freeze cannot make a listener's refund lapse: collecting still works.
func TestClaimPickPayoutWhileFrozen(cur realm, t *testing.T) {
	ids := sponsorSetup(cur, "Frozen Sponsor", 1)
	trust(carol)
	testing.SetRealm(testing.NewUserRealm(carol))
	QueueSponsored(cross(cur), 5, ids[0])
	s := slotBy(stations[5], carol)
	uassert.Equal(t, "airing", PickPayoutStatus(carol, 5, s.Start))
	uassert.Equal(t, "none", PickPayoutStatus(carol, 5, s.Start+1))
	uassert.Equal(t, "none", PickPayoutStatus(bob, 5, s.Start))
	testing.SkipHeights((s.Start+s.Dur-now())/5 + 1)
	uassert.Equal(t, "ok", PickPayoutStatus(carol, 5, s.Start))
	urequire.True(t, strings.Contains(SponsoredJSON(carol), `"amount":30000,"status":"ok"}`), SponsoredJSON(carol))
	claimable = false
	uassert.Equal(t, "lapsed", PickPayoutStatus(carol, 5, s.Start))
	claimable = true
	testing.SetRealm(testing.NewUserRealm(erin))
	Freeze(cross(cur), true)
	testing.SetRealm(testing.NewUserRealm(carol))
	ClaimPickPayout(cross(cur), 5, s.Start)
	uassert.Equal(t, "claim", promoCalls[len(promoCalls)-1][:5])
	uassert.Equal(t, "none", PickPayoutStatus(carol, 5, s.Start))
	frozen = false
}

// RestoreNote refuses a dedication that is not hidden and keeps its reports.
func TestRestoreNoteNotHidden(cur realm, t *testing.T) {
	reset()
	testing.SetRealm(testing.NewUserRealm(testutils.TestAddress("visible_artist")))
	catalog.RegisterArtist(cross(cur), "Visible Artist", "")
	track := publish(cur, "Visible A", 3, "3:00")
	testing.SetRealm(testing.NewUserRealm(carol))
	Sync(cross(cur), 50)
	testing.SetRealm(testing.NewUserRealm(alice))
	dedicate(cur, MainStation, track, "for Marie")
	s := stations[MainStation].schedule[slotOf(stations[MainStation], track)]
	picked("v1")
	testing.SetRealm(testing.NewUserRealm(testutils.TestAddress("v1")))
	ReportNote(cross(cur), MainStation, s.Start)
	testing.SetRealm(testing.NewUserRealm(erin))
	uassert.AbortsContains(t, cur, "not hidden", func() { RestoreNote(cross(cur), MainStation, s.Start) })
	_, kept := noteReports.Get(itoa(MainStation) + "/" + itoa64(s.Start))
	uassert.True(t, kept)
}
