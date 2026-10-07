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
