package radio

import (
	"strings"
	"testing"

	"gno.land/p/nt/testutils/v0"
	"gno.land/p/nt/uassert/v0"
	"gno.land/p/nt/urequire/v0"
	"gno.land/r/gnoradio/catalog/v0"
)

func TestCuratorQueueAndActivity(cur realm, t *testing.T) {
	reset()
	activity, activityHead, activityN = [activitySize]Activity{}, 0, 0
	frank := testutils.TestAddress("frank_curator")
	testing.SetRealm(testing.NewUserRealm(frank))
	catalog.RegisterArtist(cross(cur), "Frank Curated", "")
	a := publish(cur, "C One", 5, "1:00")
	b := publish(cur, "C Two", 5, "1:00")
	c := publish(cur, "C Three", 5, "1:00")
	d := publish(cur, "C Four", 3, "1:00")
	Sync(cross(cur), 200)

	// A listener: one waiting slot, two per artist.
	testing.SetRealm(testing.NewUserRealm(carol))
	Queue(cross(cur), 5, a)
	uassert.AbortsContains(t, cur, "already have a track waiting", func() { Queue(cross(cur), 5, b) })

	// The curator bypasses both quotas but not the duplicate or genre rules.
	uassert.AbortsWithMessage(t, cur, "radio: admin only", func() { CuratorQueue(cross(cur), 5, b) })
	testing.SetRealm(testing.NewUserRealm(erin))
	CuratorQueue(cross(cur), 5, b)
	CuratorQueue(cross(cur), 5, c) // third track by the same artist
	uassert.AbortsContains(t, cur, "already programmed", func() { CuratorQueue(cross(cur), 5, a) })
	uassert.AbortsContains(t, cur, "does not belong", func() { CuratorQueue(cross(cur), 5, d) })
	uassert.Equal(t, 3, len(UpNext(5)))

	acts := Activities(10)
	uassert.Equal(t, 3, len(acts))
	uassert.Equal(t, "curator", acts[0].Kind)
	uassert.Equal(t, c, acts[0].Track)
	uassert.Equal(t, "queue", acts[2].Kind)
	uassert.Equal(t, carol, acts[2].By)
	js := ActivityJSON(1)
	urequire.True(t, strings.HasPrefix(js, `[{"kind":"curator","by":"`+erin.String()+`","track":`), js)
	urequire.True(t, strings.Contains(js, `"station":5,"start":`), js)

	// Ring wraps at 64 entries, newest first.
	for i := 0; i < 70; i++ {
		recordActivity("queue", carol, 1000+i, 0, 0)
	}
	got := Activities(64)
	uassert.Equal(t, 64, len(got))
	uassert.Equal(t, 1069, got[0].Track)
	uassert.Equal(t, 1006, got[63].Track)
}

// A curator is one map entry: picks on several stations, across weeks, keep
// one record whose old station entries go once past the cooldown.
func TestCuratorOneRecord(t *testing.T) {
	reset()
	credit(carol, 4, 1, 0, 0)
	credit(carol, 5, 1, 0, 0)
	credit(carol, allStations+1, 0, 1, 9)
	uassert.Equal(t, 1, curators.Len())
	c, sts := curRec(carol.String())
	uassert.Equal(t, int64(2), c[cWeek+1])
	uassert.Equal(t, int64(1), c[cWeek+2])
	uassert.Equal(t, int64(1), stationOf(sts, 5)[1])
	ts := now()
	old := withStation(sts, 4, []int64{1, 1, 0, 0, ts - queueCooldown}, ts) // an old week, past the cooldown
	uassert.Equal(t, int64(0), stationOf(withStation(old, 6, []int64{weekOf(ts), 1, 0, 0, ts}, ts), 4)[4])
	uassert.Equal(t, int64(1), stationOf(withStation(old, 6, []int64{weekOf(ts), 1, 0, 0, ts}, ts), 5)[1])
}

// The replay record of a station keeps the later time per track and only the
// picks of the last replayGap.
func TestLastPickRecord(t *testing.T) {
	reset()
	ts := now()
	setPicked(3, 7, ts-replayGap-1) // already out of the gap: not kept
	_, ok := lastPicked(3, 7)
	uassert.False(t, ok)
	setPicked(3, 7, ts-10)
	setPicked(3, 70, ts)
	setPicked(3, 7, ts-100) // an earlier time does not win
	last, ok := lastPicked(3, 7)
	uassert.True(t, ok)
	uassert.Equal(t, ts-10, last)
	last, _ = lastPicked(3, 70)
	uassert.Equal(t, ts, last)
	_, ok = lastPicked(4, 7)
	uassert.False(t, ok)
	uassert.Equal(t, 1, lastPick.Len()) // one record per station
}
