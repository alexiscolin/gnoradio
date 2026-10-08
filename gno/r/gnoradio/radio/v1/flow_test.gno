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

// relaySetup publishes n tracks of dur on each genre, two artists per genre
// so that each genre station's loop alternates them.
func relaySetup(cur realm, name, dur string, n int, genres ...int) []int {
	reset(cur)
	var ids []int
	for _, g := range genres {
		for k := 0; k < n; k++ {
			who := testutils.TestAddress(name + text.Itoa(g) + "_" + text.Itoa(k%2))
			testing.SetRealm(testing.NewUserRealm(who))
			if k < 2 {
				catalog.RegisterArtist(cross(cur), name+" "+text.Itoa(g)+" "+text.Itoa(k), "")
			}
			ids = append(ids, publish(cur, name+" "+text.Itoa(g)+" "+text.Itoa(k), g, dur))
		}
	}
	return ids
}

func genreOf(track int) int {
	_, g, _, _ := catalog.TrackBrief(track)
	return g
}

// skipTo moves block time (5 s a block) to ts or just past it.
func skipTo(ts int64) {
	if d := ts - now(); d > 0 {
		testing.SkipHeights((d + 4) / 5)
	}
}

// aired is one ScheduleJSON entry, its numbers read back.
type aired struct {
	track              int
	start, end, offset int64
}

func jsonNum(s, key string) int64 {
	i := strings.Index(s, `"`+key+`":`) + len(key) + 3
	j := i
	for j < len(s) && (s[j] == '-' || s[j] >= '0' && s[j] <= '9') {
		j++
	}
	return text.Atoi64(s[i:j])
}

func scheduleOf(stationID, horizon int) []aired {
	js := ScheduleJSON(stationID, horizon)
	js = js[:strings.Index(js, `],"booked"`)]
	var out []aired
	for _, e := range strings.Split(js, `{"track":`)[1:] {
		e = `"track":` + e
		out = append(out, aired{int(jsonNum(e, "track")), jsonNum(e, "start"), jsonNum(e, "end"), jsonNum(e, "offset")})
	}
	return out
}

func liveAll(cur realm, on int) {
	edit(cur, func(t *tx) {
		for g := 1; g <= NumGenres; g++ {
			t.setFlowAt(fLive+g, 1, on)
		}
	})
}

// The hour's genre: one step below the daypart target, the target, one step
// above, clamped to the energy line; else the nearest live genre (calmer
// first), or none.
func TestHourGenre(cur realm, t *testing.T) {
	reset(cur)
	liveAll(cur, 1)
	for h := int64(0); h < 24; h++ {
		i := dayparts[h/3] + int(h%3) - 1
		if i < 0 {
			i = 0
		}
		if i > len(energy)-1 {
			i = len(energy) - 1
		}
		uassert.Equal(t, energy[i], hourGenre(rd(), h*3600+1800), "hour "+text.Itoa64(h))
		uassert.Equal(t, energy[i], hourGenre(rd(), 86400*400+h*3600)) // any day
	}
	uassert.Equal(t, 3, HourGenre(3*3600))   // 03:00 clamps to Ambient
	uassert.Equal(t, 12, HourGenre(23*3600)) // 23:00 clamps to Metal & Punk
	edit(cur, func(t *tx) {
		t.setFlowAt(fLive+16, 1, 0) // Cinematic & Classical
		t.setFlowAt(fLive+15, 1, 0) // Folk & Acoustic
	})
	uassert.Equal(t, 3, hourGenre(rd(), 5*3600))  // Cinematic is empty: Ambient, one step calmer
	uassert.Equal(t, 14, hourGenre(rd(), 0*3600)) // Folk and Cinematic empty: Jazz & Blues
	liveAll(cur, 0)
	uassert.Equal(t, 0, hourGenre(rd(), 0))
	edit(cur, func(t *tx) { t.setFlowAt(fLive+12, 1, 1) }) // only Metal & Punk, the far end
	for h := int64(0); h < 24; h++ {
		uassert.Equal(t, 12, hourGenre(rd(), h*3600))
	}
}

// Hours after the last write, Main still plays the hour genre's rotation:
// nothing needs Sync, a robot or a keeper.
func TestMainRelayNoStall(cur realm, t *testing.T) {
	ids := relaySetup(cur, "Stall", "3:00", 4, 5)
	testing.SkipHeights(6 * 3600 / 5)
	ts := now()
	id, off, queued := NowPlaying(MainStation)
	uassert.Equal(t, 5, genreOf(id))
	uassert.Equal(t, hourGenre(rd(), ts), genreOf(id))
	uassert.True(t, off >= 0 && off < 180)
	uassert.False(t, queued)
	uassert.Equal(t, 0, len(sta(MainStation).slots())) // nothing written for it
	urequire.True(t, len(ids) == 4)
}

// simulcasts reports whether Main plays what the hour's genre station plays.
func simulcasts(t *testing.T, msg string) {
	g := hourGenre(rd(), now())
	id, off, _ := NowPlaying(MainStation)
	gid, goff, _ := NowPlaying(g)
	uassert.Equal(t, gid, id, msg)
	uassert.Equal(t, goff, off, msg)
}

// Between picks Main plays exactly what the hour's genre station plays, at
// any moment of the day.
func TestMainSimulcast(cur realm, t *testing.T) {
	relaySetup(cur, "Simul", "7:00", 4, 3, 14, 8, 17, 11, 5, 6)
	for k := 0; k < 30; k++ {
		simulcasts(t, "step "+text.Itoa(k))
		testing.SkipHeights(int64(97 + 61*k%400)) // uneven steps through the day
	}
}

// ScheduleJSON(Main) is gapless and follows the hours: each entry is of its
// hour's genre and none crosses the hour; the next hour's genre station is
// joined where it is, mid-track.
func TestMainRelaySchedule(cur realm, t *testing.T) {
	relaySetup(cur, "Sched", "7:00", 4, 3, 14, 8, 17, 11, 5, 6)
	skipTo(now() - now()%3600 + 3600 + 600) // 10 minutes into an hour
	es := scheduleOf(MainStation, 7200)
	urequire.True(t, len(es) > 10)
	uassert.True(t, es[0].start <= now())
	crossed := 0
	for i, e := range es {
		uassert.Equal(t, hourGenre(rd(), e.end-1), genreOf(e.track), "entry "+text.Itoa(i))
		uassert.Equal(t, (e.start+e.offset)/3600, (e.end-1)/3600, "entry "+text.Itoa(i))
		if i == 0 {
			continue
		}
		uassert.Equal(t, es[i-1].end, e.start+e.offset, "gapless at "+text.Itoa(i))
		if e.offset == 0 && (e.start)%3600 != 0 {
			continue
		}
		crossed++
	}
	uassert.True(t, crossed >= 2) // two hour boundaries in two hours
	uassert.True(t, es[len(es)-1].end >= now()+7200)
}

// A pick on Main airs at once over the simulcast, which then picks up the
// genre station where it is. The track the genre station plays cannot be
// picked on Main.
func TestMainRelayAfterPick(cur realm, t *testing.T) {
	ids := relaySetup(cur, "After", "3:00", 6, 5)
	skipTo(now() - now()%3600 + 3600 + 60) // a minute into an hour
	onAir, _, _ := NowPlaying(MainStation)
	testing.SetRealm(testing.NewUserRealm(dave))
	uassert.AbortsContains(t, cur, "already programmed", func() { Queue(cross(cur), MainStation, onAir) })
	pick := ids[0]
	if pick == onAir {
		pick = ids[1]
	}
	testing.SetRealm(testing.NewUserRealm(carol))
	Queue(cross(cur), MainStation, pick)
	s := slotBy(MainStation, carol)
	uassert.Equal(t, now(), s.Start)
	id, _, queued := NowPlaying(MainStation)
	uassert.Equal(t, pick, id)
	uassert.True(t, queued)
	js := ScheduleJSON(MainStation, 600)
	uassert.True(t, strings.Contains(js, `"queued":true,"by":"`+carol.String()+`","note":"","sponsored":0,"at":0,"relay":false}`), js) // Main's own slot
	uassert.True(t, strings.Contains(js, `"relay":true}`), js)                                                                         // then the simulcast
	skipTo(s.Start + s.Dur + 30)
	_, _, queued = NowPlaying(MainStation)
	uassert.False(t, queued)
	simulcasts(t, "after the pick")
}

// A pick on the hour's genre station airs on Main too, and Main follows that
// station on after it.
func TestMainRelayGenrePick(cur realm, t *testing.T) {
	ids := relaySetup(cur, "GenrePick", "7:00", 6, 5)
	testing.SetRealm(testing.NewUserRealm(dave))
	Queue(cross(cur), 5, ids[2])
	s := slotBy(5, dave)
	skipTo(s.Start + 5)
	urequire.True(t, now() < s.Start+s.Dur-60)
	id, _, _ := NowPlaying(MainStation)
	uassert.Equal(t, ids[2], id)
	simulcasts(t, "during the genre pick")
	js := ScheduleJSON(MainStation, 600)
	uassert.True(t, strings.Contains(js, `"queued":true,"by":"`+dave.String()+`"`) && strings.Contains(js, `"relay":true}`), js) // a genre pick, not Main's
	uassert.False(t, strings.Contains(js, `"relay":false}`), js)
	skipTo(s.Start + s.Dur + 20)
	simulcasts(t, "after the genre pick")
}

// A track the admin dropped from Main never airs on it through the relay.
func TestMainRelayDropped(cur realm, t *testing.T) {
	ids := relaySetup(cur, "Dropped", "3:00", 4, 5)
	x := ids[1]
	testing.SetRealm(testing.NewUserRealm(erin))
	DropSlot(cross(cur), MainStation, x)
	for k := 0; k < 24; k++ { // every minute for 24 minutes: twice round the loop
		id, _, _ := NowPlaying(MainStation)
		uassert.NotEqual(t, x, id)
		for _, e := range scheduleOf(MainStation, 1800) {
			uassert.NotEqual(t, x, e.track)
		}
		testing.SkipHeights(12)
	}
	i, _ := sta(5).slot(x) // still on its genre station

	_, d := sta(5).rotSlot(i)
	uassert.Equal(t, int64(180), d)
}

// Main never jumps: a publish, a duration edit or a dropped slot on the
// genre station, behind or ahead of the listeners, leaves the track Main
// plays and its offset as they were.
func TestMainRelayStable(cur realm, t *testing.T) {
	ids := relaySetup(cur, "Stable", "15:00", 6, 5) // a 90-minute loop
	skipTo(now() - now()%3600 + 3600 + 60)
	id, off, _ := NowPlaying(MainStation)
	for off+60 >= 900 || (now()+60)%3600 < 60 { // a moment the same track plays on
		testing.SkipHeights(12)
		id, off, _ = NowPlaying(MainStation)
	}
	testing.SkipHeights(6)
	id2, off2, _ := NowPlaying(MainStation)
	uassert.Equal(t, id, id2)
	uassert.Equal(t, off+30, off2)
	testing.SetRealm(testing.NewUserRealm(testutils.TestAddress("Stable5_0")))
	publish(cur, "Stable late", 5, "4:00")
	other := ids[0]
	if other == id {
		other = ids[1]
	}
	testing.SetRealm(testing.NewUserRealm(erin))
	DropSlot(cross(cur), 5, other)
	id3, off3, _ := NowPlaying(MainStation)
	uassert.Equal(t, id, id3)
	uassert.Equal(t, off2, off3)
	simulcasts(t, "after the edits")
}

// A flow record an earlier release wrote shorter reads padded: Main still
// finds its genre, and the next write stores the full record.
func TestFlowRecordPadded(cur realm, t *testing.T) {
	ids := relaySetup(cur, "Padded", "3:00", 2, 5)
	edit(cur, func(t *tx) { t.set(cMeta, "flow", t.flowRec()[:fLive+3]) }) // genre 5 cut off
	uassert.False(t, rd().hasLive(5))
	uassert.False(t, rd().hasLive(NumGenres+1))
	edit(cur, func(t *tx) { t.setFlowAt(fLive+5, 1, 1) })
	urequire.Equal(t, flowLen, len(rd().flowRec()))
	id, _, _ := NowPlaying(MainStation)
	uassert.True(t, id == ids[0] || id == ids[1])
}

// Review R20: a dedicated pick Main simulcasts that began before the hour
// (the previous hour's genre was another) can still be reported from Main.
func TestMainReportAcrossHour(cur realm, t *testing.T) {
	ids := relaySetup(cur, "Rep", "3:00", 2, 3, 14, 8, 17)
	h := now() - now()%3600 + 3600
	for hourGenre(rd(), h-1) == hourGenre(rd(), h) {
		h += 3600
	}
	g := hourGenre(rd(), h)
	track := 0
	for _, id := range ids {
		if genreOf(id) == g {
			track = id
			break
		}
	}
	start := h - 30
	edit(cur, func(t *tx) {
		st := t.station(g)
		st.setSlots(append(st.slots(), Slot{Track: track, Start: start, Dur: 600, By: alice, Note: "for Main listeners"}))
	})
	skipTo(h + 10)
	picked(cur, "mainrep")
	testing.SetRealm(testing.NewUserRealm(testutils.TestAddress("mainrep")))
	ReportNote(cross(cur), MainStation, start)
	uassert.AbortsContains(t, cur, "already reported", func() { ReportNote(cross(cur), MainStation, start) })
}
