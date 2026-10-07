package radio

import (
	"testing"

	"gno.land/p/nt/testutils/v0"
	"gno.land/p/nt/uassert/v0"
	"gno.land/r/gnoradio/catalog/v0"
)

// The main station keeps no slot index; genre stations are listed in homes.
func TestMainStationNeedsNoIndex(cur realm, t *testing.T) {
	reset()
	testing.SetRealm(testing.NewUserRealm(testutils.TestAddress("idxartist")))
	catalog.RegisterArtist(cross(cur), "Index Artist", "")
	a := publish(cur, "Idx A", 4, "1:00")
	b := publish(cur, "Idx B", 6, "2:00")
	Sync(cross(cur), 50)

	i, ok := stations[MainStation].slot(b)
	uassert.True(t, ok)
	id, d := stations[MainStation].rot.Slot(i)
	uassert.Equal(t, b, id)
	uassert.Equal(t, int64(120), d)
	_, ok = stations[MainStation].slot(b + 1)
	uassert.False(t, ok)

	ha, _ := homes.Get(a - 1)
	hb, _ := homes.Get(b - 1)
	uassert.Equal(t, "4:0,"+itoa(NewStation)+":0", ha) // genre station 4 slot 0, New slot 0
	uassert.Equal(t, "6:0,"+itoa(NewStation)+":1", hb)

	ids, durs := RotationPage(MainStation, a-1, 10) // main slot = id-1
	uassert.Equal(t, 2, len(ids))
	uassert.Equal(t, a, ids[0])
	uassert.Equal(t, int64(60), durs[0])
	ids, _ = RotationPage(6, 0, 10)
	uassert.Equal(t, 1, len(ids))
	uassert.Equal(t, b, ids[0])
}
