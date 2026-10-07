package radio

import (
	"strings"
	"testing"

	"gno.land/p/nt/testutils/v0"
	"gno.land/p/nt/uassert/v0"
	"gno.land/p/nt/urequire/v0"
	"gno.land/r/gnoradio/catalog/v0"
)

func slotDur(st, track int) int64 {
	i, ok := stations[st].slot(track)
	if !ok {
		return -1
	}
	_, d := stations[st].rot.Slot(i)
	return d
}

// A dropped slot stays silent through Refresh until the admin restores it.
func TestDropSlotIsSticky(cur realm, t *testing.T) {
	reset()
	testing.SetRealm(testing.NewUserRealm(testutils.TestAddress("stickyartist")))
	catalog.RegisterArtist(cross(cur), "Sticky Artist", "")
	a := publish(cur, "Sticky A", 9, "1:00")
	Sync(cross(cur), 50)

	testing.SetRealm(testing.NewUserRealm(erin))
	DropSlot(cross(cur), 9, a)
	testing.SetRealm(testing.NewUserRealm(testutils.TestAddress("stickyfan")))
	Refresh(cross(cur), a)
	uassert.Equal(t, int64(0), slotDur(9, a))
	uassert.Equal(t, int64(60), slotDur(MainStation, a)) // other stations untouched
	uassert.AbortsWithMessage(t, cur, "radio: admin only", func() { RestoreSlot(cross(cur), 9, a) })

	testing.SetRealm(testing.NewUserRealm(erin))
	RestoreSlot(cross(cur), 9, a)
	uassert.Equal(t, int64(60), slotDur(9, a))
	uassert.AbortsContains(t, cur, "was not dropped", func() { RestoreSlot(cross(cur), 9, a) })
}

// RefreshArtist applies a catalog change to all of an artist's tracks in batches.
func TestRefreshArtist(cur realm, t *testing.T) {
	reset()
	testing.SetRealm(testing.NewUserRealm(testutils.TestAddress("batchartist")))
	aid := catalog.RegisterArtist(cross(cur), "Batch Artist", "")
	var ids []int
	for i := 0; i < maxRefreshBatch+3; i++ {
		ids = append(ids, publish(cur, "Batch "+itoa(i), 10, "1:00"))
	}
	Sync(cross(cur), 200)
	for _, id := range ids {
		catalog.EditTrack(cross(cur), id, "Batch", 11, "1:00", "", "ipfs://"+cid, "", "", "")
	}

	testing.SetRealm(testing.NewUserRealm(testutils.TestAddress("batchfan")))
	next := RefreshArtist(cross(cur), aid, 0)
	uassert.Equal(t, maxRefreshBatch, next)
	urequire.Equal(t, int64(60), slotDur(11, ids[0]))
	uassert.Equal(t, int64(60), slotDur(10, ids[len(ids)-1])) // not reached yet
	uassert.Equal(t, 0, RefreshArtist(cross(cur), aid, next))
	for _, id := range ids {
		uassert.Equal(t, int64(0), slotDur(10, id))
		uassert.Equal(t, int64(60), slotDur(11, id))
	}
	uassert.AbortsContains(t, cur, "unknown artist", func() { RefreshArtist(cross(cur), 99999, 0) })
}

func TestRenderPointsHome(t *testing.T) {
	uassert.True(t, strings.Contains(Render(""), "(/r/gnoradio/home/v0)"))
}

// New and Choice are rings: once full, a join reuses the oldest slot in
// place, and listeners never jump (the slot on air ends, others stay put).
func TestRingNoJump(t *testing.T) {
	reset()
	st := stations[ChoiceStation]
	ts := int64(1_000_000)
	for i := 0; i < 3; i++ {
		st.join(2000001+i, 60, ts, 3) // A, B, C
	}
	slot, _, off, _, _ := st.rotationAt(ts + 70)
	uassert.Equal(t, 1, slot) // B, 10s in
	uassert.Equal(t, int64(10), off)

	uassert.Equal(t, ChoiceStation, st.id)
	uassert.Equal(t, itoa(ChoiceStation)+":0", st.join(2000004, 60, ts+70, 3)) // D takes A's slot, behind listeners
	slot, id, off, _, _ := st.rotationAt(ts + 70)
	uassert.Equal(t, 1, slot)
	uassert.Equal(t, 2000002, id)
	uassert.Equal(t, int64(10), off)

	st.join(2000005, 60, ts+70, 3) // E takes B's slot, on air: the next one starts now
	slot, id, off, _, _ = st.rotationAt(ts + 70)
	uassert.Equal(t, 2, slot)
	uassert.Equal(t, 2000003, id)
	uassert.Equal(t, int64(0), off)
	uassert.Equal(t, 3, st.rot.Len())
	uassert.Equal(t, 3, st.live)
	uassert.Equal(t, int64(180), st.rot.Total())
}

// The schedule never grows past maxSchedule, even with 10-second tracks.
func TestScheduleCap(cur realm, t *testing.T) {
	reset()
	x, y := testutils.TestAddress("shortx"), testutils.TestAddress("shorty")
	testing.SetRealm(testing.NewUserRealm(x))
	catalog.RegisterArtist(cross(cur), "Short Ex", "")
	testing.SetRealm(testing.NewUserRealm(y))
	catalog.RegisterArtist(cross(cur), "Short Why", "")
	for i := 0; i < maxSchedule+20; i++ {
		testing.SetRealm(testing.NewUserRealm([]address{x, y}[i%2]))
		publish(cur, "Short "+itoa(i), 9, "0:10")
	}
	testing.SetRealm(testing.NewUserRealm(carol))
	Sync(cross(cur), 200)
	for i := 0; i < 8; i++ {
		Sync(cross(cur), 1)
	}
	n := len(stations[MainStation].schedule)
	uassert.Equal(t, maxSchedule, n)
	uassert.False(t, NeedsSync()) // full: the robot does not pay for a Sync that cannot add anything
}

// Everything a successor needs can be read, and the successor announced.
func TestMigrationReads(cur realm, t *testing.T) {
	reset()
	testing.SetRealm(testing.NewUserRealm(testutils.TestAddress("migartist")))
	catalog.RegisterArtist(cross(cur), "Mig Artist", "")
	a := publish(cur, "Mig A", 10, "3:00")
	b := publish(cur, "Mig B", 10, "3:00")
	testing.SetRealm(testing.NewUserRealm(carol))
	Sync(cross(cur), 10)
	Queue(cross(cur), 10, a)
	testing.SetRealm(testing.NewUserRealm(erin))
	DropSlot(cross(cur), 10, b)

	keys, vals := StatePage("dropped", 0, 10)
	uassert.Equal(t, 1, len(keys))
	uassert.Equal(t, dropKey(10, b), keys[0])
	uassert.Equal(t, "1", vals[0])
	keys, _ = StatePage("lastPick", 0, 100)
	uassert.True(t, len(keys) >= 1)
	keys, vals = StatePage("curators", 0, 100)
	found := false
	for i, k := range keys {
		found = found || k == carol.String() && vals[i] != ""
	}
	uassert.True(t, found)
	uassert.PanicsWithMessage(t, cur, "radio: unknown table", func() { StatePage("homes", 0, 10) })

	_, _, sched := StationState(10)
	uassert.Equal(t, a, sched[0].Track)
	uassert.Equal(t, carol, sched[0].By)
	upTo, _, _, cursors := FlowState()
	uassert.Equal(t, catalog.TrackCount(), upTo)
	uassert.Equal(t, catalog.NumGenres+1, len(cursors))

	testing.SetRealm(testing.NewUserRealm(carol))
	uassert.AbortsWithMessage(t, cur, "radio: admin only", func() { SetSuccessor(cross(cur), "gno.land/r/gnoradio/radio/v1") })
	testing.SetRealm(testing.NewUserRealm(erin))
	uassert.AbortsContains(t, cur, "invalid realm path", func() { SetSuccessor(cross(cur), "gno.land/r/x\"y") })
	SetSuccessor(cross(cur), "gno.land/r/gnoradio/radio/v1")
	uassert.Equal(t, "gno.land/r/gnoradio/radio/v1", Successor())
}

// The queue cooldown reads the station's weekly curator record: a pick sets
// it, a new week keeps it, the all-stations record does not count.
func TestCooldownInWeeklyRecord(t *testing.T) {
	reset()
	uassert.Equal(t, int64(0), lastPickAt(carol, 4))
	credit(carol, 4, 1, 0, 0)
	ts := now()
	uassert.Equal(t, ts, lastPickAt(carol, 4))
	uassert.Equal(t, int64(0), lastPickAt(carol, 5))
	c, _ := curRec(carol.String())
	putCur(carol.String(), c, withStation("", 4, []int64{1, 1, 0, 0, ts}, ts)) // an old week
	credit(carol, 4, 0, 1, 7)                                                  // a tip this week
	uassert.Equal(t, ts, lastPickAt(carol, 4))
	top := TopCurators(4)
	uassert.Equal(t, 0, top[0].Picks)
	uassert.Equal(t, 1, top[0].Tips)
}
