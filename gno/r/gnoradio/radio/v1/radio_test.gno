package radio

import (
	"chain"
	"strings"
	"testing"
	"time"

	"gno.land/p/gnoradio/store/v0"
	"gno.land/p/nt/testutils/v0"
	"gno.land/p/nt/uassert/v0"
	"gno.land/p/nt/urequire/v0"
	"gno.land/r/gnoradio/catalog/v1"
	"gno.land/r/gnoradio/data"
)

var (
	alice = testutils.TestAddress("alice")
	bob   = testutils.TestAddress("bob")
	carol = testutils.TestAddress("carol")
	dave  = testutils.TestAddress("dave")
	erin  = chain.PackageAddress("gno.land/r/gnoradio/radio/v1/dev")   // the radio admin under gno test
	boss  = chain.PackageAddress("gno.land/r/gnoradio/catalog/v1/dev") // the catalog admin under gno test
)

const cid = "bafybeigdyrzt5sfp7udm7hu76uh7y26nf3efuylqabf3oclgtqy55fbzdi"

// reset gives the radio fresh stations. The data realm keeps what every test
// wrote (gno test runs a package's tests on one store), so reset wipes the
// radio's collections, as the radio realm (the only writer allowed), and
// writes back a radio that synced every track already in the catalog
// (other realms' state is not reset): a silent main slot and an empty homes
// entry each, as on a chain where Sync ingested them.
func reset(cur realm) {
	testing.SetRealm(testing.NewCodeRealm(self))
	for _, c := range collections {
		for {
			keys, _ := store.Rows(data.Page(c, "", "", 64, false))
			if len(keys) == 0 {
				break
			}
			var ops store.Ops
			for _, k := range keys {
				ops = ops.Del(c, k)
			}
			data.Batch(cross(cur), ops)
		}
	}
	n := catalog.TrackCount()
	t := rd()
	t.put(cMeta, "flow", strings.Repeat("0", flowLen))
	t.setFlowAt(fSynced, 4, n)
	t.put(cConfig, "admin", erin.String())
	main := t.station(MainStation)
	for id := 1; id <= n; id++ {
		main.appendRot(id, 0)
	}
	save(cur, t)
	var ops store.Ops
	for k := 0; k*homesChunk < n; k++ {
		m := n - k*homesChunk
		if m > homesChunk {
			m = homesChunk
		}
		if ops = ops.Set(cHomes, store.Pad(k), store.Rec(make([]string, m)...)); len(ops) == 4*64 {
			data.Batch(cross(cur), ops)
			ops = nil
		}
	}
	if len(ops) > 0 {
		data.Batch(cross(cur), ops)
	}
}

// sta loads a station for a test to look at.
func sta(id int) *station { return rd().station(id) }

// edit runs fn on a tx and saves it as the radio realm: what a test changes
// directly (v0's tests set package variables).
func edit(cur realm, fn func(t *tx)) {
	t := rd()
	fn(t)
	testing.SetRealm(testing.NewCodeRealm(self))
	save(cur, t)
}

// publish adds a track of the current caller's artist profile.
func publish(cur realm, title string, genre int, dur string) int {
	return PublishTrack(cross(cur), title, genre, dur, "CC-BY", "none", "", "ipfs://"+cid, "", "", "", "", "yes")
}

// curatorKeys lists the curator records.
func curatorKeys() ([]string, []string) { return store.Rows(data.Page(cCurators, "", "", 100, false)) }

// synced is how many catalog tracks the radio ingested.
func synced() int { return rd().synced() }

func TestRotationAndQueue(cur realm, t *testing.T) {
	reset(cur)
	testing.SetRealm(testing.NewUserRealm(alice))
	catalog.RegisterArtist(cross(cur), "Alice Radio", "")
	one := publish(cur, "One", 2, "1:00")
	two := publish(cur, "Two", 2, "2:00")
	testing.SetRealm(testing.NewUserRealm(dave))
	catalog.RegisterArtist(cross(cur), "Dave Radio", "")
	three := publish(cur, "Three", 2, "1:00")

	testing.SetRealm(testing.NewUserRealm(carol))
	uassert.Equal(t, 0, Sync(cross(cur), 50)) // published tracks are on the air already
	uassert.Equal(t, 0, Pending())

	// The genre station starts with track one; Main relays the only live
	// genre.
	id, off, queued := NowPlaying(2)
	uassert.Equal(t, one, id)
	uassert.Equal(t, int64(0), off)
	uassert.False(t, queued)
	id, _, queued = NowPlaying(MainStation)
	_, g, _, _ := catalog.TrackBrief(id)
	uassert.Equal(t, 2, g)
	uassert.False(t, queued)
	id, _, _ = NowPlaying(3)
	uassert.Equal(t, 0, id) // empty genre station

	// 20s in, a new publication does not move listeners.
	testing.SkipHeights(4)
	id, off, _ = NowPlaying(2)
	testing.SetRealm(testing.NewUserRealm(dave))
	four := publish(cur, "Four", 2, "1:00")
	Sync(cross(cur), 50)
	id2, off2, _ := NowPlaying(2)
	uassert.Equal(t, id, id2)
	uassert.Equal(t, off, off2)

	// Carol programs track three: it starts when track one ends.
	testing.SetRealm(testing.NewUserRealm(carol))
	Queue(cross(cur), 2, three)
	ts := time.Now().Unix()
	up := UpNext(2)
	uassert.Equal(t, 1, len(up))
	uassert.Equal(t, ts+60-off2, up[0].Start)
	uassert.AbortsContains(t, cur, "already have a track waiting", func() { Queue(cross(cur), 2, two) })
	uassert.AbortsContains(t, cur, "does not belong", func() { Queue(cross(cur), 5, two) })

	// Duplicate and per-artist limits (Dave owns three and four).
	testing.SetRealm(testing.NewUserRealm(bob))
	uassert.AbortsContains(t, cur, "already programmed", func() { Queue(cross(cur), 2, three) })
	Queue(cross(cur), 2, four)
	testing.SetRealm(testing.NewUserRealm(dave))
	five := publish(cur, "Five", 2, "1:00")
	Sync(cross(cur), 50)
	testing.SetRealm(testing.NewUserRealm(erin))
	uassert.AbortsContains(t, cur, "already has 2 tracks", func() { Queue(cross(cur), 2, five) })

	// When track one ends, carol's slot plays; after the slots the rotation
	// resumes with track two (paused, not skipped).
	testing.SkipHeights((up[0].Start - ts + 5) / 5)
	id, _, queued = NowPlaying(2)
	uassert.Equal(t, three, id)
	uassert.True(t, queued)
	ups := sta(2).slots()
	last := ups[len(ups)-1]
	ts = time.Now().Unix()
	testing.SkipHeights((last.Start + last.Dur - ts + 5) / 5)
	id, off, queued = NowPlaying(2)
	uassert.Equal(t, two, id)
	uassert.False(t, queued)
	urequire.True(t, off < 15)

	js := ScheduleJSON(2, 900)
	urequire.True(t, strings.Contains(js, `"title":"Two"`))
	urequire.True(t, strings.Contains(StationsJSON(), `"name":"Main"`))
}

// hide silences a track in a station as Refresh does once the catalog
// reports it unplayable (or plays it again, on false).
func hide(cur realm, stationID, trackID int, on bool) {
	edit(cur, func(t *tx) {
		st := t.station(stationID)
		i, _ := st.slot(trackID)
		d := int64(0)
		if !on {
			_, _, d, _ = catalog.TrackBrief(trackID)
		}
		ts := time.Now().Unix()
		st.setDuration(i, d, ts)
		if on {
			st.dropSlots(trackID, ts)
		}
	})
}

func TestHideMovesToNextTrack(cur realm, t *testing.T) {
	reset(cur)
	testing.SetRealm(testing.NewUserRealm(alice))
	a := publish(cur, "Hide A", 3, "1:00")
	b := publish(cur, "Hide B", 3, "1:00")
	c := publish(cur, "Hide C", 3, "1:00")
	Sync(cross(cur), 50)

	// 30s into A, A is hidden: B starts now.
	testing.SkipHeights(6)
	id, off, _ := NowPlaying(3)
	uassert.Equal(t, a, id)
	uassert.Equal(t, int64(30), off)
	hide(cur, 3, a, true)
	id, off, _ = NowPlaying(3)
	uassert.Equal(t, b, id)
	uassert.Equal(t, int64(0), off)
	tracks, loop, _ := StationInfo(3)
	uassert.Equal(t, 2, tracks)
	uassert.Equal(t, int64(120), loop)

	// Hiding a track ahead of the listeners does not move them.
	testing.SkipHeights(4)
	id, off, _ = NowPlaying(3)
	hide(cur, 3, c, true)
	id2, off2, _ := NowPlaying(3)
	uassert.Equal(t, id, id2)
	uassert.Equal(t, off, off2)

	// Restoring it, or restoring A behind them, does not move anyone either.
	hide(cur, 3, c, false)
	hide(cur, 3, a, false)
	id3, off3, _ := NowPlaying(3)
	uassert.Equal(t, id, id3)
	uassert.Equal(t, off, off3)
	tracks, _, _ = StationInfo(3)
	uassert.Equal(t, 3, tracks)
}

// An edited duration applies on the air in the edit's transaction.
func TestEditedDurationOnAir(cur realm, t *testing.T) {
	reset(cur)
	testing.SetRealm(testing.NewUserRealm(alice))
	a := publish(cur, "Edit A", 6, "2:00")
	b := publish(cur, "Edit B", 6, "1:00")
	Sync(cross(cur), 50)
	testing.SkipHeights(10) // 50s into A

	// Shortening A below the current offset: B starts now.
	EditTrack(cross(cur), a, "Edit A", 6, "0:40", "", "ipfs://"+cid, "", "", "")
	id, off, _ := NowPlaying(6)
	uassert.Equal(t, b, id)
	uassert.Equal(t, int64(0), off)
	_, loop, _ := StationInfo(6)
	uassert.Equal(t, int64(100), loop)

	// Lengthening A (behind the listeners now) keeps them on B.
	testing.SkipHeights(2)
	id, off, _ = NowPlaying(6)
	testing.SetRealm(testing.NewUserRealm(alice))
	EditTrack(cross(cur), a, "Edit A", 6, "3:00", "", "ipfs://"+cid, "", "", "")
	id2, off2, _ := NowPlaying(6)
	uassert.Equal(t, id, id2)
	uassert.Equal(t, off, off2)
}

func TestHiddenQueuedSlotIsDropped(cur realm, t *testing.T) {
	reset(cur)
	testing.SetRealm(testing.NewUserRealm(alice))
	a := publish(cur, "Drop A", 4, "1:00")
	b := publish(cur, "Drop B", 4, "1:00")
	Sync(cross(cur), 50)
	testing.SetRealm(testing.NewUserRealm(carol))
	Queue(cross(cur), 4, b)
	uassert.Equal(t, 1, len(UpNext(4)))
	hide(cur, 4, b, true)
	uassert.Equal(t, 0, len(UpNext(4)))
	id, _, _ := NowPlaying(4)
	uassert.Equal(t, a, id)
}

func TestGuards(cur realm, t *testing.T) {
	reset(cur)
	testing.SetRealm(testing.NewCodeRealm("gno.land/r/evil/proxy"))
	uassert.AbortsContains(t, cur, "directly from your wallet", func() { Queue(cross(cur), 0, 1) })
	testing.SetRealm(testing.NewUserRealm(carol))
	uassert.AbortsContains(t, cur, "unknown station", func() { Queue(cross(cur), 99, 1) })
	uassert.AbortsContains(t, cur, "unknown track", func() { Queue(cross(cur), 0, 999999) })
	uassert.AbortsWithMessage(t, cur, "radio: admin only", func() { DropSlot(cross(cur), 0, 1) })
	// A paused radio (the data realm's emergency brake) writes nothing.
	testing.SetRealm(testing.NewUserRealm(testutils.TestAddress("pausedartist")))
	catalog.RegisterArtist(cross(cur), "Paused Artist", "")
	a := publish(cur, "Paused A", 4, "1:00")
	testing.SetRealm(testing.NewUserRealm(chain.PackageAddress("gno.land/r/gnoradio/data/dev")))
	data.Pause(cross(cur), "radio", true)
	testing.SetRealm(testing.NewUserRealm(carol))
	uassert.AbortsContains(t, cur, "radio is paused", func() { Queue(cross(cur), 4, a) })
	testing.SetRealm(testing.NewUserRealm(chain.PackageAddress("gno.land/r/gnoradio/data/dev")))
	data.Pause(cross(cur), "radio", false)
}

// Scale: Main, New and Choice with n rotation slots each (built directly,
// without the catalog), then NowPlaying, ScheduleJSON, Sync and Queue (which
// feed and trim New and Choice). Ops must barely grow with n (SPEC §6); the
// z_gas filetests measure them.
func bigStation(cur realm, n int) {
	reset(cur)
	edit(cur, func(t *tx) {
		ts := time.Now().Unix()
		for _, id := range []int{NewStation, ChoiceStation, MainStation} {
			st := t.station(id)
			for i := 0; i < n; i++ {
				st.appendRot(1000000+i, 180)
				st.live++
			}
			st.anchor(ts, 0)
		}
	})
}

func scaleOps(cur realm, t *testing.T) {
	testing.SetRealm(testing.NewUserRealm(alice))
	tr := publish(cur, "Scale", 1, "3:00")
	edit(cur, func(t *tx) { t.setFlowAt(fSynced, 4, tr-1) }) // only this track gets synced
	testing.SetRealm(testing.NewUserRealm(carol))
	Sync(cross(cur), 5)
	testing.SkipHeights(1000)
	for k := 0; k < 10; k++ {
		NowPlaying(MainStation)
	}
	_ = ScheduleJSON(MainStation, 3600)
	testing.SetRealm(testing.NewUserRealm(bob))
	Queue(cross(cur), 1, tr) // Main relays it: a pick there would restart it
}

func TestScaleOps1k(cur realm, t *testing.T) { bigStation(cur, 1000); scaleOps(cur, t) }
