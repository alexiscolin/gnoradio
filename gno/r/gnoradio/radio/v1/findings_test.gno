package radio

import (
	"strings"
	"testing"

	"gno.land/p/gnoradio/store/v0"
	"gno.land/p/nt/testutils/v0"
	"gno.land/p/nt/uassert/v0"
	"gno.land/p/nt/urequire/v0"
	"gno.land/r/gnoradio/catalog/v1"
	"gno.land/r/gnoradio/data"
)

// Regression tests for review findings that touched radio/v1.

// recLen is the length of the record save would write for st.
func recLen(st *station) int {
	f := []string{store.Fixed(st.epoch, 6), store.Fixed(int64(st.ring), 6), store.Fixed(int64(st.live), 4), st.h, encodeSchedule(st.slots()), st.picks, st.top}
	if st.ringed() {
		f = append(f, st.rot, st.idx)
	}
	return len(store.Rec(f...))
}

// fillRecord replaces st's schedule with aired, unfolded picks of 10
// seconds, each with a dedication of noteLen bytes, until its record is
// exactly room bytes short of maxRecord.
func fillRecord(st *station, ts int64, room, noteLen int) {
	target := maxRecord - room
	by := testutils.TestAddress("filler")
	note := strings.Repeat("x", noteLen)
	var sl []Slot
	for i := 0; ; i++ {
		s := Slot{Track: 1, Start: ts - foldAfter + 60 + int64(i)*10, Dur: 10, By: by, Note: note, artist: 1}
		st.setSlots(append(sl, s))
		if recLen(st) > target {
			break
		}
		sl = append(sl, s)
	}
	st.setSlots(sl)
	last := &sl[len(sl)-1]
	last.Note, last.body = note+strings.Repeat("x", target-recLen(st)), ""
	st.setSlots(sl)
}

// M2: Choice (its ring below its cap) and Main filled to a few bytes of the
// data realm's limit no longer block picks elsewhere: a genre-station pick
// and a Sync go through; Choice waits for room.
func TestFullRecordsKeepPicksOpen(cur realm, t *testing.T) {
	ids := bookSetup(cur, "FullRec", 5, 3)
	ts := now()
	edit(cur, func(t *tx) {
		fillRecord(t.station(ChoiceStation), ts, 8, 100)
		fillRecord(t.station(MainStation), ts, 8, 100)
	})
	testing.SetRealm(testing.NewUserRealm(fan(1)))
	Queue(cross(cur), 5, ids[0])
	uassert.Equal(t, ids[0], slotBy(5, fan(1)).Track)
	_, in := sta(ChoiceStation).ringFind(ids[0])
	uassert.False(t, in)
	testing.SetRealm(testing.NewUserRealm(testutils.TestAddress("FullRec new")))
	catalog.RegisterArtist(cross(cur), "FullRec New", "")
	publish(cur, "FullRec New Song", 5, "3:00") // full records never block a publication
	testing.SetRealm(testing.NewUserRealm(dave))
	uassert.Equal(t, 0, Sync(cross(cur), 50))
	for _, id := range []int{MainStation, 5, ChoiceStation} {
		rec, _ := data.Get(cStations, store.Pad(id))
		uassert.True(t, len(rec) <= maxRecord)
		st := sta(id)
		uassert.Equal(t, len(rec), st.size()) // undecoded
		st.slots()
		uassert.Equal(t, len(rec), st.size()) // decoded: measured as encodeSchedule writes it
	}
	// A pick on a full station is refused before anything is written.
	testing.SetRealm(testing.NewUserRealm(fan(2)))
	uassert.AbortsContains(t, cur, "full", func() { Queue(cross(cur), MainStation, ids[1]) })
}

// M2: a station refuses a pick when its record would leave less than
// recordHeadroom, before the data realm's limit is reached.
func TestPickRefusedNearRecordLimit(cur realm, t *testing.T) {
	ids := bookSetup(cur, "NearRec", 5, 2)
	ts := now()
	edit(cur, func(t *tx) { fillRecord(t.station(5), ts, 600, 250) })
	urequire.True(t, len(sta(5).slots()) < maxKept)
	testing.SetRealm(testing.NewUserRealm(fan(1)))
	uassert.AbortsContains(t, cur, "this station is full for now", func() { Queue(cross(cur), 5, ids[0]) })
}

// M2: aired listener slots count against a cap until they fold, so very
// short tracks cannot pile up a station's record.
func TestAiredSlotsCap(cur realm, t *testing.T) {
	ids := bookSetup(cur, "Aired", 5, 2)
	ts := now()
	edit(cur, func(t *tx) {
		var sl []Slot
		for i := 0; i < maxKept; i++ {
			sl = append(sl, Slot{Track: ids[1], Start: ts - foldAfter + 60 + int64(i)*10, Dur: 10, By: fan(500 + i), artist: 1})
		}
		t.station(5).setSlots(sl)
	})
	testing.SetRealm(testing.NewUserRealm(fan(1)))
	uassert.AbortsContains(t, cur, "the queue is full", func() { Queue(cross(cur), 5, ids[0]) })
}

// M7: reporting a dedication needs the reputation sponsored picks need; a
// throwaway wallet with one free pick may not report.
func TestReportNeedsReputation(cur realm, t *testing.T) {
	reset(cur)
	testing.SetRealm(testing.NewUserRealm(testutils.TestAddress("report_artist")))
	catalog.RegisterArtist(cross(cur), "Reporting Artist", "")
	track := publish(cur, "Reporting A", 3, "3:00")
	testing.SetRealm(testing.NewUserRealm(carol))
	Sync(cross(cur), 50)
	dedicate(cur, alice, 3, track, "for Marie")
	s := noteAt(3, track)
	throwaway := testutils.TestAddress("throwaway")
	edit(cur, func(t *tx) { credit(t, throwaway, 3, 1, 0, 0) })
	testing.SetRealm(testing.NewUserRealm(throwaway))
	uassert.AbortsContains(t, cur, "reporting needs", func() { ReportNote(cross(cur), 3, s.Start) })
	trust(cur, throwaway)
	testing.SetRealm(testing.NewUserRealm(throwaway))
	ReportNote(cross(cur), 3, s.Start)
	uassert.True(t, data.Has(cNotes, noteKey(3, s.Start)))
}

// M10: a pick for now made while a booked pick is on air starts when the
// booked pick ends: no rotation fragment in between.
func TestPickForNowDuringBooked(cur realm, t *testing.T) {
	ids := bookSetup(cur, "DuringBooked", 5, 3)
	testing.SetRealm(testing.NewUserRealm(fan(1)))
	QueueAt(cross(cur), 5, ids[0], now()+bookMin)
	b := slotBy(5, fan(1))
	testing.SkipHeights((b.Start-now())/5 + 6) // 30 s into the booked pick
	urequire.True(t, now() > b.Start && now() < b.Start+b.Dur)
	testing.SetRealm(testing.NewUserRealm(fan(2)))
	Queue(cross(cur), 5, ids[1])
	uassert.Equal(t, b.Start+b.Dur, slotBy(5, fan(2)).Start)
}

// L13: an artist (or a collaborator) picking their own track airs it but
// earns no curator point and does not feed Listeners' choice.
func TestSelfPickEarnsNothing(cur realm, t *testing.T) {
	reset(cur)
	own, collab := testutils.TestAddress("self_artist"), testutils.TestAddress("self_collab")
	testing.SetRealm(testing.NewUserRealm(own))
	catalog.RegisterArtist(cross(cur), "Self Artist", "")
	a := publish(cur, "Self A", 5, "3:00")
	b := PublishTrack(cross(cur), "Self B", 5, "3:00", "CC-BY", "none", "", "ipfs://"+cid, "", "", "", collab.String()+":30", "yes")
	testing.SetRealm(testing.NewUserRealm(carol))
	Sync(cross(cur), 50)
	for _, p := range []struct {
		who   address
		track int
	}{{own, a}, {collab, b}} {
		testing.SetRealm(testing.NewUserRealm(p.who))
		Queue(cross(cur), 5, p.track)
		uassert.Equal(t, p.track, slotBy(5, p.who).Track)
		uassert.Equal(t, 0, CuratorOf(p.who).Picks)
		_, in := sta(ChoiceStation).ringFind(p.track)
		uassert.False(t, in)
		uassert.True(t, lastPickAt(rd(), p.who, 5) > 0) // the cooldown still applies
	}
}

// L20: the 4 booked picks per clock hour count the ones that already aired.
func TestHourCapCountsAired(cur realm, t *testing.T) {
	ids := bookSetup(cur, "HourAired", 5, 6)
	h := (now()+bookMin)/3600*3600 + 3600
	for i := 0; i < maxBookedHour; i++ {
		testing.SetRealm(testing.NewUserRealm(fan(10 + i)))
		QueueAt(cross(cur), 5, ids[i], h+int64(i)*200)
	}
	testing.SkipHeights((h + 1200 - now()) / 5)
	urequire.True(t, slotBy(5, fan(10)).Start+180 <= now())
	testing.SetRealm(testing.NewUserRealm(fan(20)))
	uassert.AbortsContains(t, cur, "4 picks are already booked", func() { QueueAt(cross(cur), 5, ids[4], h+3000) })
}

// L21: two booked picks of one track keep the replay gap plus a track's
// length, which realign may still move either by.
func TestBookedReplayMargin(cur realm, t *testing.T) {
	ids := bookSetup(cur, "Margin", 5, 2)
	at := now() + bookMin + 60
	testing.SetRealm(testing.NewUserRealm(fan(1)))
	QueueAt(cross(cur), 5, ids[0], at)
	testing.SetRealm(testing.NewUserRealm(fan(2)))
	uassert.AbortsContains(t, cur, "already programmed", func() { QueueAt(cross(cur), 5, ids[0], at+replayGap+300) })
	QueueAt(cross(cur), 5, ids[0], at+replayGap+maxTrack+300)
}

// M4: an address argument must be canonical (lower case): an upper-case
// spelling reaches the same account but no string comparison.
func TestUpperCaseAddressRefused(cur realm, t *testing.T) {
	a, _ := onAirSetup(cur, "Upper Case Artist", true)
	upper := address(strings.ToUpper(carol.String()))
	testing.IssueCoins(radioAddr, ugnots(ugnot))
	testing.SetOriginSend(ugnots(ugnot))
	testing.SetRealm(testing.NewUserRealm(carol))
	uassert.AbortsContains(t, cur, "not an address", func() { TipOnAir(cross(cur), 5, a, 0, upper) })
	testing.SetOriginSend(nil)
	testing.SetRealm(testing.NewUserRealm(erin))
	uassert.AbortsContains(t, cur, "not an address", func() { Unmute(cross(cur), upper) })
}

// Audit Y1: booked picks take at most half the queue, so bookings spread
// over the next 24 hours cannot refuse every pick for now.
func TestBookedHalfQueue(cur realm, t *testing.T) {
	ids := bookSetup(cur, "HalfQueue", 5, maxQueue/2+2)
	ts := now()
	for i := 0; i < maxQueue/2; i++ {
		queueAs(cur, fan(300+i), 5, ids[i], ts+bookMin+int64(i)*3600)
	}
	testing.SetRealm(testing.NewUserRealm(fan(1)))
	uassert.AbortsContains(t, cur, "booked picks", func() { QueueAt(cross(cur), 5, ids[maxQueue/2], ts+bookMin+20*3600) })
	Queue(cross(cur), 5, ids[maxQueue/2+1])
}
