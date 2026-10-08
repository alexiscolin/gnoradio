package radio

import (
	"strings"
	"testing"

	"gno.land/p/gnoradio/text/v0"
	"gno.land/p/nt/testutils/v0"
	"gno.land/p/nt/uassert/v0"
	"gno.land/p/nt/urequire/v0"
	"gno.land/r/gnoradio/catalog/v1"
	"gno.land/r/gnoradio/data"
)

// A booked pick keeps the replay gap between its end and its fold.
func TestBookedReplayGapBeforeFold(cur realm, t *testing.T) {
	reset(cur)
	testing.SetRealm(testing.NewUserRealm(testutils.TestAddress("gap_artist")))
	catalog.RegisterArtist(cross(cur), "Gap Artist", "")
	a := publish(cur, "Gap A", 5, "1:00")
	publish(cur, "Gap B", 5, "1:00")
	testing.SetRealm(testing.NewUserRealm(carol))
	Sync(cross(cur), 50)
	testing.SetRealm(testing.NewUserRealm(fan(1)))
	QueueAt(cross(cur), 5, a, now()+20*60)
	testing.SkipHeights(30 * 60 / 5) // aired and ended, not folded yet
	_, ok := sta(5).lastPicked(a)
	urequire.False(t, ok)
	testing.SetRealm(testing.NewUserRealm(fan(2)))
	uassert.AbortsContains(t, cur, "less than 3 hours ago", func() { Queue(cross(cur), 5, a) })
}

// RestoreNote takes back the strike its hide gave, and only that one.
func TestRestoreNoteKeepsEarlierStrike(cur realm, t *testing.T) {
	reset(cur)
	testing.SetRealm(testing.NewUserRealm(testutils.TestAddress("strike_artist")))
	catalog.RegisterArtist(cross(cur), "Strike Artist", "")
	tracks := []int{publish(cur, "Strike A", 3, "3:00"), publish(cur, "Strike B", 3, "3:00")}
	testing.SetRealm(testing.NewUserRealm(carol))
	Sync(cross(cur), 50)
	// No earlier strike: restoring leaves none.
	start := hideNote(cur, tracks[0])
	testing.SetRealm(testing.NewUserRealm(erin))
	RestoreNote(cross(cur), 3, start)
	uassert.False(t, data.Has(cStrikes, alice.String()))
	// An earlier strike (older than the mute window) survives a restore.
	earlier := text.Itoa64(now() - muteFor - 100)
	edit(cur, func(t *tx) { t.set(cStrikes, alice.String(), earlier) })
	testing.SkipHeights(720)
	start = hideNote(cur, tracks[1])
	last, _ := data.Get(cStrikes, alice.String())
	uassert.NotEqual(t, earlier, last)
	testing.SetRealm(testing.NewUserRealm(erin))
	RestoreNote(cross(cur), 3, start)
	last, _ = data.Get(cStrikes, alice.String())
	uassert.Equal(t, earlier, last)
	uassert.False(t, noteAt(3, tracks[1]).NoteHidden)
}

// hideNote has alice dedicate a pick of track on station 3 (Main relays it) and three listeners hide it.
func hideNote(cur realm, track int) int64 {
	dedicate(cur, alice, 3, track, "for Marie")
	s := noteAt(3, track)
	for _, who := range []string{"k1", "k2", "k3"} {
		picked(cur, who)
		testing.SetRealm(testing.NewUserRealm(testutils.TestAddress(who)))
		ReportNote(cross(cur), 3, s.Start)
	}
	return s.Start
}

// StationsJSON tells the app which tracks New still takes.
func TestStationsJSONNewFloor(cur realm, t *testing.T) {
	reset(cur)
	floor := synced() - newCap
	if floor < 0 {
		floor = 0
	}
	uassert.True(t, strings.Contains(StationsJSON(), `"newFloor":`+text.Itoa(floor)+`,`))
}

// longSetup publishes a 3-minute track and n 15-minute ones on genre 5, one
// artist each, so picks for now can wait close to two hours.
func longSetup(cur realm, name string, n int) (a int, long []int) {
	ids := bookSetup(cur, name, 5, 1)
	for i := 0; i < n; i++ {
		testing.SetRealm(testing.NewUserRealm(testutils.TestAddress(name + "long" + text.Itoa(i))))
		catalog.RegisterArtist(cross(cur), name+" Long "+text.Itoa(i), "")
		long = append(long, publish(cur, name+" Long Song "+text.Itoa(i), 5, "15:00"))
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
	s := slotBy(5, fan(1))
	urequire.True(t, s.Start-ts > 6000)
	last, _ := sta(5).lastPicked(a)
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
	short := bookTrack(cur, "GapAlign Short", 5, "2:00")
	ts := now()
	for i := 0; i < 8; i++ {
		testing.SetRealm(testing.NewUserRealm(fan(20 + i)))
		Queue(cross(cur), 5, ids[i])
	}
	testing.SetRealm(testing.NewUserRealm(erin))
	for i := 0; i < 7; i++ {
		Unqueue(cross(cur), 5, ids[i])
	}
	n := slotBy(5, fan(27))
	urequire.True(t, n.Start >= ts+20*60)
	testing.SetRealm(testing.NewUserRealm(fan(1)))
	QueueAt(cross(cur), 5, short, ts+15*60)
	b := slotBy(5, fan(1))
	urequire.True(t, b.Start+b.Dur < n.Start) // in the gap, before the pick for now
	moved := slotBy(5, fan(27))
	uassert.True(t, onBoundary(5, moved))
	uassert.True(t, moved.Start > n.Start)
	last, _ := sta(5).lastPicked(ids[7])
	uassert.Equal(t, moved.Start, last)
}

// RestoreNote refuses a dedication that is not hidden and keeps its reports.
func TestRestoreNoteNotHidden(cur realm, t *testing.T) {
	reset(cur)
	testing.SetRealm(testing.NewUserRealm(testutils.TestAddress("visible_artist")))
	catalog.RegisterArtist(cross(cur), "Visible Artist", "")
	track := publish(cur, "Visible A", 3, "3:00")
	testing.SetRealm(testing.NewUserRealm(carol))
	Sync(cross(cur), 50)
	dedicate(cur, alice, 3, track, "for Marie")
	s := noteAt(3, track)
	picked(cur, "v1")
	testing.SetRealm(testing.NewUserRealm(testutils.TestAddress("v1")))
	ReportNote(cross(cur), 3, s.Start)
	testing.SetRealm(testing.NewUserRealm(erin))
	uassert.AbortsContains(t, cur, "not hidden", func() { RestoreNote(cross(cur), 3, s.Start) })
	uassert.True(t, data.Has(cNotes, noteKey(3, s.Start)))
}
