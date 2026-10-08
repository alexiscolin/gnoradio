package radio

import (
	"testing"

	"gno.land/p/nt/uassert/v0"
)

// replace leaves a station exactly as setDuration(i, 0), setRot and
// setDuration(i, d) did: same epoch, rotation and live count, whether the
// slot is ahead of the listeners, behind them, on air, the last one, silent,
// or the only one.
func TestReplaceMatchesThreeSteps(cur realm, t *testing.T) {
	reset(cur)
	const g, solo = 9, 10
	ts := now()
	edit(cur, func(x *tx) {
		st := x.station(g)
		for k, d := range []int64{100, 200, 300, 0, 500, 600} { // prefixes 0 100 300 600 600 1100, loop 1700
			st.appendRot(9001+k, d)
		}
		st.live = 5
		st.anchor(ts, 0)
		one := x.station(solo)
		one.appendRot(9101, 250)
		one.live = 1
		one.anchor(ts, 0)
	})
	for _, c := range []struct {
		st, i int
		at    int64 // seconds into the loop at ts
		d     int64
	}{
		{g, 4, 350, 400},   // ahead
		{g, 1, 350, 150},   // behind
		{g, 2, 350, 250},   // on air: it ends now
		{g, 2, 350, 0},     // on air, silenced
		{g, 5, 1300, 700},  // the last slot, on air
		{g, 5, 1300, 0},    // the last slot silenced: the loop restarts
		{g, 3, 350, 0},     // silent stays silent
		{g, 3, 350, 450},   // silent comes on
		{g, 0, 50, 100},    // on air, same length
		{solo, 0, 100, 80}, // the only slot
	} {
		at := ts + c.at
		a, b := rd().station(c.st), rd().station(c.st)
		a.replace(c.i, 4242, c.d, at)
		b.setDuration(c.i, 0, at)
		b.setRot(c.i, 4242, 0)
		b.setDuration(c.i, c.d, at)
		uassert.Equal(t, b.epoch, a.epoch)
		uassert.Equal(t, b.h, a.h)
		uassert.Equal(t, b.live, a.live)
		for j := 0; j < b.count(); j++ {
			id, d := b.rotSlot(j)
			id2, d2 := a.rotSlot(j)
			uassert.Equal(t, id, id2)
			uassert.Equal(t, d, d2)
		}
		uassert.Equal(t, b.pos(at), a.pos(at))
	}
}
