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

func slotDur(st, track int) int64 {
	s := sta(st)
	i, ok := s.slot(track)
	if !ok {
		return -1
	}
	_, d := s.rotSlot(i)
	return d
}

// A dropped slot stays silent through Refresh until the admin restores it.
func TestDropSlotIsSticky(cur realm, t *testing.T) {
	reset(cur)
	testing.SetRealm(testing.NewUserRealm(testutils.TestAddress("stickyartist")))
	catalog.RegisterArtist(cross(cur), "Sticky Artist", "")
	a := publish(cur, "Sticky A", 9, "1:00")
	Sync(cross(cur), 50)

	testing.SetRealm(testing.NewUserRealm(erin))
	DropSlot(cross(cur), 9, a)
	testing.SetRealm(testing.NewUserRealm(testutils.TestAddress("stickyfan")))
	Refresh(cross(cur), a)
	uassert.Equal(t, int64(0), slotDur(9, a))
	// Audit Y1: no pick brings a dropped track back, on its station or on Main.
	uassert.AbortsWithMessage(t, cur, "radio: this track was removed from this station", func() { Queue(cross(cur), 9, a) })
	testing.SetRealm(testing.NewUserRealm(erin))
	DropSlot(cross(cur), MainStation, a)
	uassert.AbortsWithMessage(t, cur, "radio: this track was removed from this station", func() { CuratorQueue(cross(cur), MainStation, a) })
	RestoreSlot(cross(cur), MainStation, a)
	testing.SetRealm(testing.NewUserRealm(testutils.TestAddress("stickyfan")))
	uassert.Equal(t, int64(60), slotDur(NewStation, a)) // other stations untouched
	uassert.AbortsWithMessage(t, cur, "radio: admin only", func() { RestoreSlot(cross(cur), 9, a) })

	testing.SetRealm(testing.NewUserRealm(erin))
	RestoreSlot(cross(cur), 9, a)
	uassert.Equal(t, int64(60), slotDur(9, a))
	uassert.AbortsContains(t, cur, "was not dropped", func() { RestoreSlot(cross(cur), 9, a) })
}

// RefreshArtist applies a catalog change to all of an artist's tracks in
// batches: a hidden artist goes silent everywhere.
func TestRefreshArtist(cur realm, t *testing.T) {
	reset(cur)
	testing.SetRealm(testing.NewUserRealm(testutils.TestAddress("batchartist")))
	aid := catalog.RegisterArtist(cross(cur), "Batch Artist", "")
	var ids []int
	for i := 0; i < maxRefreshBatch+3; i++ {
		ids = append(ids, publish(cur, "Batch "+text.Itoa(i), 10, "1:00"))
	}
	testing.SetRealm(testing.NewUserRealm(boss))
	catalog.HideArtist(cross(cur), aid, true, "test")

	testing.SetRealm(testing.NewUserRealm(testutils.TestAddress("batchfan")))
	next := RefreshArtist(cross(cur), aid, 0)
	uassert.Equal(t, maxRefreshBatch, next)
	urequire.Equal(t, int64(0), slotDur(10, ids[0]))
	uassert.Equal(t, int64(60), slotDur(10, ids[len(ids)-1])) // not reached yet
	uassert.Equal(t, 0, RefreshArtist(cross(cur), aid, next))
	for _, id := range ids {
		uassert.Equal(t, int64(0), slotDur(10, id))
		uassert.Equal(t, int64(0), slotDur(NewStation, id))
	}
	uassert.AbortsContains(t, cur, "unknown artist", func() { RefreshArtist(cross(cur), 99999, 0) })
}

// The realm points gnoweb to the site and to its data.
func TestRenderPointsHome(t *testing.T) {
	uassert.True(t, strings.Contains(Render(""), "(/r/gnoradio/home/v1)"))
	uassert.True(t, strings.Contains(Render(""), "(/r/gnoradio/data)"))
	uassert.False(t, strings.Contains(Render(""), "retired"))
}

// New and Choice are rings: once full, a join reuses the oldest slot in
// place, and listeners never jump (the slot on air ends, others stay put).
func TestRingNoJump(cur realm, t *testing.T) {
	reset(cur)
	ts := int64(1_000_000)
	edit(cur, func(t *tx) {
		st := t.station(ChoiceStation)
		for i := 0; i < 3; i++ {
			st.join(2000001+i, 60, ts, 3) // A, B, C
		}
	})
	slot, _, off, _, _ := sta(ChoiceStation).rotationAt(ts + 70)
	uassert.Equal(t, 1, slot) // B, 10s in
	uassert.Equal(t, int64(10), off)

	edit(cur, func(t *tx) { t.station(ChoiceStation).join(2000004, 60, ts+70, 3) }) // D takes A's slot, behind listeners
	i, _ := sta(ChoiceStation).ringSlot(2000004)
	uassert.Equal(t, 0, i)
	_, gone := sta(ChoiceStation).ringSlot(2000001)
	uassert.False(t, gone)
	slot, id, off, _, _ := sta(ChoiceStation).rotationAt(ts + 70)
	uassert.Equal(t, 1, slot)
	uassert.Equal(t, 2000002, id)
	uassert.Equal(t, int64(10), off)

	edit(cur, func(t *tx) { t.station(ChoiceStation).join(2000005, 60, ts+70, 3) }) // E takes B's slot, on air: the next one starts now
	st := sta(ChoiceStation)
	slot, id, off, _, _ = st.rotationAt(ts + 70)
	uassert.Equal(t, 2, slot)
	uassert.Equal(t, 2000003, id)
	uassert.Equal(t, int64(0), off)
	uassert.Equal(t, 3, st.count())
	uassert.Equal(t, 3, st.live)
	uassert.Equal(t, int64(180), st.total())
}

// The queue cooldown reads the station's weekly curator record: a pick sets
// it, a new week keeps it, the all-stations record does not count.
func TestCooldownInWeeklyRecord(cur realm, t *testing.T) {
	reset(cur)
	uassert.Equal(t, int64(0), lastPickAt(rd(), carol, 4))
	edit(cur, func(t *tx) { credit(t, carol, 4, 1, 0, 0) })
	ts := now()
	uassert.Equal(t, ts, lastPickAt(rd(), carol, 4))
	uassert.Equal(t, int64(0), lastPickAt(rd(), carol, 5))
	edit(cur, func(t *tx) {
		c, _ := curRec(t, carol.String())
		putCur(t, carol.String(), c, withStation("", 4, []int64{1, 1, 0, 0, ts}, ts)) // an old week
		credit(t, carol, 4, 0, 1, 7)                                                  // a tip this week
	})
	uassert.Equal(t, ts, lastPickAt(rd(), carol, 4))
	top := TopCurators(4)
	uassert.Equal(t, 0, top[0].Picks)
	uassert.Equal(t, 1, top[0].Tips)
}

// The main station keeps no rotation (it simulcasts the genre stations);
// genre stations are listed in homes, New and Choice in their own index.
func TestMainStationNeedsNoIndex(cur realm, t *testing.T) {
	reset(cur)
	testing.SetRealm(testing.NewUserRealm(testutils.TestAddress("idxartist")))
	catalog.RegisterArtist(cross(cur), "Index Artist", "")
	a := publish(cur, "Idx A", 4, "1:00")
	b := publish(cur, "Idx B", 6, "2:00")
	Sync(cross(cur), 50)

	main := sta(MainStation)
	_, ok := main.slot(b)
	uassert.False(t, ok)
	live, loop := main.rotating() // the genre stations' added up
	uassert.Equal(t, 2, live)
	uassert.Equal(t, int64(180), loop)
	var i int

	t0 := rd()
	uassert.Equal(t, homeEntry(4, 0), t0.homes(a)) // genre station 4 slot 0
	uassert.Equal(t, homeEntry(6, 0), t0.homes(b))
	i, _ = sta(NewStation).ringSlot(a)
	uassert.Equal(t, 0, i)
	i, _ = sta(NewStation).ringSlot(b)
	uassert.Equal(t, 1, i)
	st6 := sta(6)
	uassert.Equal(t, 1, st6.count())
	id, _ := st6.rotSlot(0)
	uassert.Equal(t, b, id)
}
