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

// Y1: a genre edit must not leave a slot in the old genre station. EditTrack
// moves the track in the same transaction: no Refresh needed.
func TestGenreEditLeavesNoOrphanSlot(cur realm, t *testing.T) {
	reset(cur)
	testing.SetRealm(testing.NewUserRealm(testutils.TestAddress("genreartist")))
	catalog.RegisterArtist(cross(cur), "Genre Mover", "")
	id := publish(cur, "Mover", 3, "2:00")
	Sync(cross(cur), 50)
	i, ok := sta(3).slot(id)
	urequire.True(t, ok)

	EditTrack(cross(cur), id, "Mover", 7, "2:00", "", "ipfs://"+cid, "", "", "")

	_, d := sta(3).rotSlot(i)
	uassert.Equal(t, int64(0), d) // silent on the old genre station
	j, ok := sta(7).slot(id)
	urequire.True(t, ok) // now rotates on the new one
	_, d = sta(7).rotSlot(j)
	uassert.Equal(t, int64(120), d)
	nowID, _, _ := NowPlaying(3)
	uassert.NotEqual(t, id, nowID)
}

// Y1: admin DropSlot and Unqueue.
func TestDropSlotAndUnqueue(cur realm, t *testing.T) {
	reset(cur)
	testing.SetRealm(testing.NewUserRealm(testutils.TestAddress("dropartist")))
	catalog.RegisterArtist(cross(cur), "Drop Artist", "")
	a := publish(cur, "Drop A", 6, "1:00")
	b := publish(cur, "Drop B", 6, "1:00")
	Sync(cross(cur), 50)
	testing.SetRealm(testing.NewUserRealm(testutils.TestAddress("droplistener")))
	Queue(cross(cur), 6, b)
	uassert.AbortsWithMessage(t, cur, "radio: admin only", func() { DropSlot(cross(cur), 6, a) })
	uassert.AbortsWithMessage(t, cur, "radio: admin only", func() { Unqueue(cross(cur), 6, b) })

	testing.SetRealm(testing.NewUserRealm(erin))
	Unqueue(cross(cur), 6, b)
	uassert.Equal(t, 0, len(UpNext(6)))
	DropSlot(cross(cur), 6, a)
	i, _ := sta(6).slot(a)
	_, d := sta(6).rotSlot(i)
	uassert.Equal(t, int64(0), d)
	uassert.False(t, strings.Contains(ScheduleJSON(6, 600), `"track":`+text.Itoa(a)+`,`))
	uassert.AbortsContains(t, cur, "not in this station", func() { DropSlot(cross(cur), 9, a) })
}

// Y6: one queue per station per hour per wallet, and at most 2 hours ahead.
func TestQueueCooldownAndAirtimeCap(cur realm, t *testing.T) {
	reset(cur)
	var ids []int
	for i := 0; i < 10; i++ {
		testing.SetRealm(testing.NewUserRealm(testutils.TestAddress("longartist" + text.Itoa(i))))
		catalog.RegisterArtist(cross(cur), "Long Artist "+text.Itoa(i), "")
		ids = append(ids, publish(cur, "Long "+text.Itoa(i), 8, "19:00"))
	}
	Sync(cross(cur), 50)

	fan := testutils.TestAddress("cooldownfan")
	testing.SetRealm(testing.NewUserRealm(fan))
	Queue(cross(cur), 8, ids[0])
	testing.SkipHeights(300) // 25 min later: the slot started, nothing is waiting
	uassert.AbortsContains(t, cur, "one track per station per hour", func() { Queue(cross(cur), 8, ids[1]) })

	// Distinct wallets, distinct artists: 19-minute tracks hit the 2-hour cap.
	capped := 0
	for i := 1; i < 10 && capped == 0; i++ {
		who := testutils.TestAddress("filler" + text.Itoa(i))
		if programmedAhead(8) > maxAheadAir-19*60 {
			uassert.PanicsContains(t, cur, "two hours ahead", func() { queueAs(cur, who, 8, ids[i], 0) })
			capped = i
			continue
		}
		queueAs(cur, who, 8, ids[i], 0)
	}
	urequire.True(t, capped > 0)
	// Curators are exempt from the cap.
	testing.SetRealm(testing.NewUserRealm(erin))
	CuratorQueue(cross(cur), 8, ids[9])
}

// programmedAhead is the airtime listeners programmed for now on a station.
func programmedAhead(stationID int) int64 {
	ts := now()
	var ahead int64
	for _, s := range sta(stationID).slots() {
		if end := s.Start + s.Dur; end > ts && s.By != "" && s.At == 0 {
			ahead += end - max64(s.Start, ts)
		}
	}
	return ahead
}
