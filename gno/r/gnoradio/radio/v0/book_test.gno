package radio

import (
	"strings"
	"testing"

	"gno.land/p/nt/testutils/v0"
	"gno.land/p/nt/uassert/v0"
	"gno.land/p/nt/urequire/v0"
	"gno.land/r/gnoradio/catalog/v0"
)

// bookSetup publishes n tracks of 3 minutes on genre g, one artist each.
func bookSetup(cur realm, name string, g, n int) []int {
	reset()
	resetCurators()
	stubPromo()
	var ids []int
	for i := 0; i < n; i++ {
		testing.SetRealm(testing.NewUserRealm(testutils.TestAddress(name + itoa(i))))
		catalog.RegisterArtist(cross(cur), name+" "+itoa(i), "")
		ids = append(ids, publish(cur, name+" Song "+itoa(i), g, "3:00"))
	}
	testing.SetRealm(testing.NewUserRealm(dave))
	Sync(cross(cur), 50)
	return ids
}

func fan(i int) address { return testutils.TestAddress("bookfan" + itoa(i)) }

func slotBy(st *station, by address) Slot {
	for _, s := range st.schedule {
		if s.By == by {
			return s
		}
	}
	return Slot{}
}

// onBoundary: the rotation is between two tracks when the slot starts.
func onBoundary(st *station, s Slot) bool {
	_, _, off, _, ok := st.rotationAt(s.Start)
	return !ok || off == 0
}

func TestBookWindow(cur realm, t *testing.T) {
	ids := bookSetup(cur, "Window", 5, 2)
	ts := now()
	testing.SetRealm(testing.NewUserRealm(fan(1)))
	uassert.AbortsContains(t, cur, "between 15 minutes and 24 hours", func() { QueueAt(cross(cur), 5, ids[0], ts+14*60) })
	uassert.AbortsContains(t, cur, "between 15 minutes and 24 hours", func() { QueueAt(cross(cur), 5, ids[0], ts+bookMax+1) })
	uassert.AbortsContains(t, cur, "between 15 minutes and 24 hours", func() { QueueAt(cross(cur), 5, ids[0], -1) })
	QueueAt(cross(cur), 5, ids[0], ts+bookMax)
	s := slotBy(stations[5], fan(1))
	uassert.Equal(t, ts+bookMax, s.At)
	// One waiting pick per listener and station, booked or not; the cooldown holds.
	uassert.AbortsContains(t, cur, "already have a track waiting", func() { Queue(cross(cur), 5, ids[1]) })
	// gnoweb and the app see it, whatever the horizon.
	uassert.Equal(t, 1, len(UpNext(5)))
	js := ScheduleJSON(5, 600)
	urequire.True(t, strings.Contains(js, `"booked":[{"track":`+itoa(ids[0])+`,"start":`+itoa64(s.Start)), js)
}

// A booked pick starts at the first track boundary at or after its time, and
// keeps it: picks for now go before it only if they end by then, else after
// it; the rotation never cuts a song around it.
func TestBookAlignAndAround(cur realm, t *testing.T) {
	ids := bookSetup(cur, "Align", 5, 8)
	st := stations[5]
	ts := now()
	at := ts + 20*60 + 7 // mid-track
	testing.SetRealm(testing.NewUserRealm(fan(1)))
	QueueAt(cross(cur), 5, ids[0], at)
	b := slotBy(st, fan(1))
	urequire.True(t, b.Start >= at && b.Start < at+180)
	uassert.True(t, onBoundary(st, b))

	// Picks for now fit before it and it moves to the new boundary, never before its time.
	for i := 2; i <= 4; i++ {
		testing.SetRealm(testing.NewUserRealm(fan(i)))
		Queue(cross(cur), 5, ids[i])
		b = slotBy(st, fan(1))
		urequire.True(t, b.Start >= at && b.Start < at+180)
		uassert.True(t, onBoundary(st, b))
		n := slotBy(st, fan(i))
		uassert.True(t, n.Start+n.Dur <= at)
	}
	// Seven 3-minute picks no longer fit before 20 minutes: the next goes after it.
	for i := 5; i <= 7; i++ {
		testing.SetRealm(testing.NewUserRealm(fan(i)))
		Queue(cross(cur), 5, ids[i])
	}
	b = slotBy(st, fan(1))
	urequire.True(t, b.Start >= at && b.Start < at+180)
	last := slotBy(st, fan(7))
	uassert.True(t, last.Start >= b.Start+b.Dur)
	// The schedule stays sorted and without overlap.
	for i := 1; i < len(st.schedule); i++ {
		uassert.True(t, st.schedule[i-1].Start+st.schedule[i-1].Dur <= st.schedule[i].Start)
	}
	// It airs at its start.
	testing.SkipHeights((b.Start-now())/5 + 1)
	id, _, queued := NowPlaying(5)
	uassert.Equal(t, ids[0], id)
	uassert.True(t, queued)
}

// On Main the booked pick starts at its time: the flow's track then fades out
// and the flow goes on after it, gapless, as around any pick.
func TestBookMainFlow(cur realm, t *testing.T) {
	reset()
	var tracks []int
	for _, g := range []int{3, 16, 15} {
		for k := 0; k < 10; k++ {
			testing.SetRealm(testing.NewUserRealm(testutils.TestAddress("mainflow" + itoa(g) + itoa(k))))
			catalog.RegisterArtist(cross(cur), "Main Flow "+itoa(g)+" "+itoa(k), "")
			tracks = append(tracks, publish(cur, "Flow", g, "3:00"))
		}
	}
	testing.SetRealm(testing.NewUserRealm(dave))
	Sync(cross(cur), 50)
	st := stations[MainStation]
	urequire.True(t, st.ahead(now()) > 3600, itoa64(st.ahead(now()))+" "+itoa(len(st.schedule)))
	pick := 0
	for _, id := range tracks {
		if !st.programmed(id) && pick == 0 {
			pick = id
		}
	}
	testing.SkipHeights((st.schedule[0].Start-now())/5 + 12) // the flow is on air
	ts := now()
	at := ts + 30*60 + 10
	testing.SetRealm(testing.NewUserRealm(fan(1)))
	QueueAt(cross(cur), MainStation, pick, at)
	b := slotBy(st, fan(1))
	uassert.Equal(t, at, b.Start)
	gapless := func() {
		for i := 1; i < len(st.schedule); i++ {
			p, s := st.schedule[i-1], st.schedule[i]
			urequire.Equal(t, p.Start+p.Dur, s.Start)
		}
	}
	gapless()
	// A pick for now on Main takes over the flow; the booked one keeps its time.
	other := 0
	for _, id := range tracks {
		if !st.programmed(id) && id != pick && other == 0 {
			other = id
		}
	}
	testing.SetRealm(testing.NewUserRealm(fan(2)))
	Queue(cross(cur), MainStation, other)
	uassert.Equal(t, now(), slotBy(st, fan(2)).Start)
	uassert.Equal(t, at, slotBy(st, fan(1)).Start)
	gapless()
	// Sync tops the flow up after it, and NeedsSync does not count it.
	testing.SetRealm(testing.NewUserRealm(dave))
	Sync(cross(cur), 50)
	gapless()
	uassert.Equal(t, at, slotBy(st, fan(1)).Start)
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
	last, _ := lastPicked(5, ids[0])
	urequire.True(t, last >= ts+4*3600)
	testing.SetRealm(testing.NewUserRealm(fan(5)))
	uassert.AbortsContains(t, cur, "less than 3 hours ago", func() { Queue(cross(cur), 5, ids[0]) })
}

// The admin cancels a booked pick with Unqueue; a sponsored one gives its
// reservation back. A sponsored booked pick is reserved until 7 days after
// its booked end.
func TestBookUnqueueAndSponsored(cur realm, t *testing.T) {
	ids := bookSetup(cur, "BookSpon", 5, 2)
	trust(carol)
	ts := now()
	at := ts + 3600
	testing.SetRealm(testing.NewUserRealm(carol))
	QueueSponsoredAt(cross(cur), 5, ids[0], at)
	s := slotBy(stations[5], carol)
	urequire.True(t, s.Pay > 0)
	uassert.Equal(t, "reserve "+itoa(ids[0])+" "+carol.String()+" "+itoa64(at+s.Dur), promoCalls[0])
	urequire.True(t, strings.Contains(SponsoredJSON(carol), `"start":`+itoa64(s.Start)+`,"track":`+itoa(ids[0])+`,"end":`+itoa64(s.Start+s.Dur)), SponsoredJSON(carol))

	testing.SetRealm(testing.NewUserRealm(fan(1)))
	QueueAt(cross(cur), 5, ids[1], at+600)
	testing.SetRealm(testing.NewUserRealm(erin))
	Unqueue(cross(cur), 5, ids[0])
	uassert.Equal(t, "release "+itoa(ids[0])+" "+itoa64(at+s.Dur)+" 30000 "+carol.String()+" unaired", promoCalls[len(promoCalls)-1])
	uassert.Equal(t, int64(0), slotBy(stations[5], carol).Start)
	uassert.Equal(t, at+600 <= slotBy(stations[5], fan(1)).Start, true) // the other booking stays

	// Collected once aired in full.
	testing.SetRealm(testing.NewUserRealm(carol))
	testing.SkipHeights(queueCooldown / 5)
	QueueSponsoredAt(cross(cur), 5, ids[0], now()+bookMin)
	s = slotBy(stations[5], carol)
	testing.SkipHeights((s.Start+s.Dur-now())/5 + 1)
	ClaimPickPayout(cross(cur), 5, s.Start)
	uassert.Equal(t, "claim "+itoa(ids[0])+" "+carol.String()+" "+itoa64(s.held())+" 30000", promoCalls[len(promoCalls)-1])
}

// Gas: booking on a full station (29 waiting slots, half of them booked,
// all realigned by the new one) costs about what a pick for now costs there.
// Run each test alone (-run, -print-runtime-metrics; the catalog grows with
// every test) and compare: QueueAt at the end of TestBookGasFull minus
// TestBookGasFill, and the same with TestBookGasFullNow.
// Measured: empty station Queue +10.8 M, QueueAt +10.9 M; full Queue +18.8 M,
// QueueAt +18.6 M (+16.0 M when it goes last).
func bookFill(cur realm) []int {
	ids := bookSetup(cur, "Gas", 5, 31)
	ts := now()
	for i := 0; i < 28; i++ {
		at := int64(0)
		if i%2 == 0 {
			at = ts + bookMin + int64(i)*1800
		}
		queue(cur, fan(100+i), 5, ids[i], false, false, "", at)
	}
	return ids
}

func TestBookGasFill(cur realm, t *testing.T) { bookFill(cur) }

func TestBookGasFull(cur realm, t *testing.T) {
	ids := bookFill(cur)
	testing.SetRealm(testing.NewUserRealm(fan(1)))
	QueueAt(cross(cur), 5, ids[30], now()+bookMin+60)
	uassert.Equal(t, 29, len(UpNext(5)))
	st := stations[5]
	for i := 1; i < len(st.schedule); i++ {
		uassert.True(t, st.schedule[i-1].Start+st.schedule[i-1].Dur <= st.schedule[i].Start)
		if s := st.schedule[i]; s.At > 0 {
			uassert.True(t, s.Start >= s.At)
		}
	}
}

func TestBookGasFullNow(cur realm, t *testing.T) {
	ids := bookFill(cur)
	testing.SetRealm(testing.NewUserRealm(fan(1)))
	Queue(cross(cur), 5, ids[30])
}
