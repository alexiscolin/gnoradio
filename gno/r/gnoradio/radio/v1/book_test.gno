package radio

import (
	"strings"
	"testing"

	"gno.land/p/gnoradio/text/v0"
	"gno.land/p/nt/testutils/v0"
	"gno.land/p/nt/uassert/v0"
	"gno.land/p/nt/urequire/v0"
	"gno.land/r/gnoradio/catalog/v1"
)

// bookSetup publishes n tracks of 3 minutes on genre g, one artist each.
func bookSetup(cur realm, name string, g, n int) []int {
	reset(cur)
	var ids []int
	for i := 0; i < n; i++ {
		testing.SetRealm(testing.NewUserRealm(testutils.TestAddress(name + text.Itoa(i))))
		catalog.RegisterArtist(cross(cur), name+" "+text.Itoa(i), "")
		ids = append(ids, publish(cur, name+" Song "+text.Itoa(i), g, "3:00"))
	}
	testing.SetRealm(testing.NewUserRealm(dave))
	Sync(cross(cur), 50)
	return ids
}

func fan(i int) address { return testutils.TestAddress("bookfan" + text.Itoa(i)) }

func slotBy(st int, by address) Slot {
	for _, s := range sta(st).slots() {
		if s.By == by {
			return s
		}
	}
	return Slot{}
}

// onBoundary: the rotation is between two tracks when the slot starts.
func onBoundary(st int, s Slot) bool {
	_, _, off, _, ok := sta(st).rotationAt(s.Start)
	return !ok || off == 0
}

// queueAs programs a pick as the radio does for who, without the wallet
// check (v0's tests called queue the same way).
func queueAs(cur realm, who address, stationID, trackID int, at int64) {
	testing.SetRealm(testing.NewCodeRealm(self))
	queue(cur, who, stationID, trackID, false, false, "", at)
}

func TestBookWindow(cur realm, t *testing.T) {
	ids := bookSetup(cur, "Window", 5, 2)
	ts := now()
	testing.SetRealm(testing.NewUserRealm(fan(1)))
	uassert.AbortsContains(t, cur, "between 15 minutes and 24 hours", func() { QueueAt(cross(cur), 5, ids[0], ts+14*60) })
	uassert.AbortsContains(t, cur, "between 15 minutes and 24 hours", func() { QueueAt(cross(cur), 5, ids[0], ts+bookMax+1) })
	uassert.AbortsContains(t, cur, "between 15 minutes and 24 hours", func() { QueueAt(cross(cur), 5, ids[0], -1) })
	QueueAt(cross(cur), 5, ids[0], ts+bookMax)
	s := slotBy(5, fan(1))
	uassert.Equal(t, ts+bookMax, s.At)
	// One waiting pick per listener and station, booked or not; the cooldown holds.
	uassert.AbortsContains(t, cur, "already have a track waiting", func() { Queue(cross(cur), 5, ids[1]) })
	// gnoweb and the app see it, whatever the horizon.
	uassert.Equal(t, 1, len(UpNext(5)))
	js := ScheduleJSON(5, 600)
	urequire.True(t, strings.Contains(js, `"booked":[{"track":`+text.Itoa(ids[0])+`,"start":`+text.Itoa64(s.Start)), js)
	// Once aired it still counts toward its hour's cap until it folds: the app sees it.
	testing.SkipHeights((s.Start + s.Dur + 60 - ts) / 5)
	urequire.True(t, strings.Contains(ScheduleJSON(5, 600), `"booked":[{"track":`+text.Itoa(ids[0])), "aired")
	testing.SkipHeights(foldAfter / 5)
	urequire.True(t, strings.Contains(ScheduleJSON(5, 600), `"booked":[]`), "folded")
}

// A booked pick starts at the first track boundary at or after its time, and
// keeps it: picks for now go before it only if they end by then, else after
// it; the rotation never cuts a song around it.
func TestBookAlignAndAround(cur realm, t *testing.T) {
	ids := bookSetup(cur, "Align", 5, 8)
	ts := now()
	at := ts + 20*60 + 7 // mid-track
	testing.SetRealm(testing.NewUserRealm(fan(1)))
	QueueAt(cross(cur), 5, ids[0], at)
	b := slotBy(5, fan(1))
	urequire.True(t, b.Start >= at && b.Start < at+180)
	uassert.True(t, onBoundary(5, b))

	// Picks for now fit before it and it moves to the new boundary, never before its time.
	for i := 2; i <= 4; i++ {
		testing.SetRealm(testing.NewUserRealm(fan(i)))
		Queue(cross(cur), 5, ids[i])
		b = slotBy(5, fan(1))
		urequire.True(t, b.Start >= at && b.Start < at+180)
		uassert.True(t, onBoundary(5, b))
		n := slotBy(5, fan(i))
		uassert.True(t, n.Start+n.Dur <= at)
	}
	// Seven 3-minute picks no longer fit before 20 minutes: the next goes after it.
	for i := 5; i <= 7; i++ {
		testing.SetRealm(testing.NewUserRealm(fan(i)))
		Queue(cross(cur), 5, ids[i])
	}
	b = slotBy(5, fan(1))
	urequire.True(t, b.Start >= at && b.Start < at+180)
	last := slotBy(5, fan(7))
	uassert.True(t, last.Start >= b.Start+b.Dur)
	// The schedule stays sorted and without overlap.
	sl := sta(5).slots()
	for i := 1; i < len(sl); i++ {
		uassert.True(t, sl[i-1].Start+sl[i-1].Dur <= sl[i].Start)
	}
	// It airs at its start.
	testing.SkipHeights((b.Start-now())/5 + 1)
	id, _, queued := NowPlaying(5)
	uassert.Equal(t, ids[0], id)
	uassert.True(t, queued)
}

// On Main a booked pick starts at its time and a pick for now at once, over
// the relay; neither moves the other, nor does a Sync.
func TestBookMainFlow(cur realm, t *testing.T) {
	ids := bookSetup(cur, "MainBook", 5, 3)
	onAir, _, _ := NowPlaying(MainStation)
	var picks []int
	for _, id := range ids {
		if id != onAir {
			picks = append(picks, id)
		}
	}
	at := now() + 30*60 + 10
	testing.SetRealm(testing.NewUserRealm(fan(1)))
	QueueAt(cross(cur), MainStation, picks[0], at)
	uassert.Equal(t, at, slotBy(MainStation, fan(1)).Start)
	testing.SetRealm(testing.NewUserRealm(fan(2)))
	Queue(cross(cur), MainStation, picks[1])
	uassert.Equal(t, now(), slotBy(MainStation, fan(2)).Start)
	uassert.Equal(t, at, slotBy(MainStation, fan(1)).Start)
	testing.SetRealm(testing.NewUserRealm(dave))
	Sync(cross(cur), 50)
	uassert.Equal(t, at, slotBy(MainStation, fan(1)).Start)
	uassert.Equal(t, 2, len(sta(MainStation).slots()))
}

// programmed reports whether a station's log holds a track.
func programmed(st, trackID int) bool {
	for _, s := range sta(st).slots() {
		if s.Track == trackID {
			return true
		}
	}
	return false
}

// At most 4 booked picks per station and clock hour.
func TestBookHourCap(cur realm, t *testing.T) {
	ids := bookSetup(cur, "Cap", 5, 6)
	hour := (now()/3600 + 3) * 3600
	for i := 0; i < 4; i++ {
		testing.SetRealm(testing.NewUserRealm(fan(i)))
		QueueAt(cross(cur), 5, ids[i], hour+int64(i)*600)
	}
	testing.SetRealm(testing.NewUserRealm(fan(4)))
	uassert.AbortsContains(t, cur, "4 picks are already booked for that hour", func() { QueueAt(cross(cur), 5, ids[4], hour+3000) })
	QueueAt(cross(cur), 5, ids[4], hour+3600) // the next hour is free
	// Booked picks are not in the 2-hour cap of picks for now.
	testing.SetRealm(testing.NewUserRealm(fan(5)))
	Queue(cross(cur), 5, ids[5])
}

// The replay gap is measured around the booked time, both ways, and after it aired.
func TestBookReplayGap(cur realm, t *testing.T) {
	ids := bookSetup(cur, "Replay", 5, 3)
	ts := now()
	testing.SetRealm(testing.NewUserRealm(fan(1)))
	Queue(cross(cur), 5, ids[0])
	testing.SetRealm(testing.NewUserRealm(fan(2)))
	uassert.AbortsContains(t, cur, "already programmed", func() { QueueAt(cross(cur), 5, ids[0], ts+2*3600) })
	QueueAt(cross(cur), 5, ids[0], ts+4*3600)
	testing.SetRealm(testing.NewUserRealm(fan(3)))
	uassert.AbortsContains(t, cur, "already programmed", func() { QueueAt(cross(cur), 5, ids[0], ts+6*3600) })

	// Once it aired and folded, a pick within 3 hours of its time is still refused.
	testing.SkipHeights((5*3600 + 600) / 5)
	testing.SetRealm(testing.NewUserRealm(fan(4)))
	Queue(cross(cur), 5, ids[1]) // folds the schedule
	last, _ := sta(5).lastPicked(ids[0])
	urequire.True(t, last >= ts+4*3600)
	testing.SetRealm(testing.NewUserRealm(fan(5)))
	uassert.AbortsContains(t, cur, "less than 3 hours ago", func() { Queue(cross(cur), 5, ids[0]) })
}

// The admin cancels a booked pick with Unqueue; a sponsored one gives its
// reservation back. A sponsored booked pick is reserved until 7 days after
// its booked end.
func TestBookUnqueueAndSponsored(cur realm, t *testing.T) {
	sp := sponsorSetup(cur, "BookSpon", 1)
	other := bookTrack(cur, "BookSponOther", 5, "3:00")
	trust(cur, carol)
	ts := now()
	at := ts + 3600
	testing.SetRealm(testing.NewUserRealm(carol))
	QueueSponsoredAt(cross(cur), 5, sp.ids[0], at)
	s := slotBy(5, carol)
	urequire.True(t, s.Pay > 0)
	uassert.Equal(t, int64(pickPay), sp.held(at+s.Dur)) // reserved for the booked end
	urequire.True(t, strings.Contains(SponsoredJSON(carol), `"start":`+text.Itoa64(s.Start)+`,"track":`+text.Itoa(sp.ids[0])+`,"end":`+text.Itoa64(s.Start+s.Dur)), SponsoredJSON(carol))
	uassert.Equal(t, 1, sp.today())

	testing.SetRealm(testing.NewUserRealm(fan(1)))
	QueueAt(cross(cur), 5, other, at+600)
	testing.SetRealm(testing.NewUserRealm(erin))
	Unqueue(cross(cur), 5, sp.ids[0])
	uassert.Equal(t, int64(0), sp.held(at+s.Dur)) // released
	uassert.Equal(t, 0, sp.today())               // and the day's count with it: it never aired
	uassert.Equal(t, int64(0), slotBy(5, carol).Start)
	uassert.Equal(t, at+600 <= slotBy(5, fan(1)).Start, true) // the other booking stays

	// Collected once aired in full.
	testing.SetRealm(testing.NewUserRealm(carol))
	testing.SkipHeights(queueCooldown / 5)
	QueueSponsoredAt(cross(cur), 5, sp.ids[0], now()+bookMin)
	s = slotBy(5, carol)
	testing.SkipHeights((s.Start+s.Dur-now())/5 + 1)
	b := balance(carol)
	ClaimPickPayout(cross(cur), 5, s.Start)
	uassert.Equal(t, int64(pickPay), balance(carol)-b)
}

// bookTrack publishes one track on genre g for a new artist and syncs it.
func bookTrack(cur realm, name string, g int, dur string) int {
	testing.SetRealm(testing.NewUserRealm(testutils.TestAddress(name)))
	catalog.RegisterArtist(cross(cur), name, "")
	id := publish(cur, name+" Song", g, dur)
	testing.SetRealm(testing.NewUserRealm(dave))
	Sync(cross(cur), 50)
	return id
}

// A full station (29 waiting slots, half of them booked, all realigned by
// the new one) still takes a booked pick, sorted and in place.
func bookFill(cur realm) []int {
	ids := bookSetup(cur, "Gas", 5, 31)
	ts := now()
	for i := 0; i < 28; i++ {
		at := int64(0)
		if i%2 == 0 {
			at = ts + bookMin + int64(i)*1800
		}
		queueAs(cur, fan(100+i), 5, ids[i], at)
	}
	return ids
}

func TestBookFull(cur realm, t *testing.T) {
	ids := bookFill(cur)
	testing.SetRealm(testing.NewUserRealm(fan(1)))
	QueueAt(cross(cur), 5, ids[30], now()+bookMin+60)
	uassert.Equal(t, 29, len(UpNext(5)))
	sl := sta(5).slots()
	for i := 1; i < len(sl); i++ {
		uassert.True(t, sl[i-1].Start+sl[i-1].Dur <= sl[i].Start)
		if s := sl[i]; s.At > 0 {
			uassert.True(t, s.Start >= s.At)
		}
	}
}
