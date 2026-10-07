package radio

import (
	"strings"
	"testing"
	"time"

	"gno.land/p/gnoradio/store/v0"

	"gno.land/p/gnoradio/blocks/v0"
	"gno.land/p/nt/avl/v0"
	"gno.land/p/nt/testutils/v0"
	"gno.land/p/nt/uassert/v0"
	"gno.land/p/nt/urequire/v0"
	"gno.land/r/gnoradio/catalog/v0"
)

var (
	alice = testutils.TestAddress("alice")
	bob   = testutils.TestAddress("bob")
	carol = testutils.TestAddress("carol")
	dave  = testutils.TestAddress("dave")
	erin  = testutils.TestAddress("erin")
)

const cid = "bafybeigdyrzt5sfp7udm7hu76uh7y26nf3efuylqabf3oclgtqy55fbzdi"

// reset gives the radio fresh stations; tracks already in the catalog (from
// earlier tests: other realms' state is not reset) are skipped.
func reset() {
	stations = nil
	for i := 0; i <= catalog.NumGenres; i++ {
		stations = append(stations, &station{id: i, genre: i, rot: blocks.New()})
	}
	synced = catalog.TrackCount()
	mainBase = synced
	homes = store.NewSeq(128)
	frozen = false
	admin = erin
	lastQ = store.NewMap(128)
	noteReports, muted = store.NewMap(1024), store.NewMap(1024)
	modBot, hideDay, hides = "", 0, 0
	dropped = avl.Tree{}
	setGenre, setLeft, cursor = 0, 0, [catalog.NumGenres + 1]int{}
}

// publish adds a track of the current caller's artist profile.
func publish(cur realm, title string, genre int, dur string) int {
	return catalog.PublishTrack(cross(cur), title, genre, dur, "CC-BY", "none", "", "ipfs://"+cid, "", "", "", "", "yes")
}

func TestRotationAndQueue(cur realm, t *testing.T) {
	reset()
	testing.SetRealm(testing.NewUserRealm(alice))
	catalog.RegisterArtist(cross(cur), "Alice Radio", "")
	one := publish(cur, "One", 2, "1:00")
	two := publish(cur, "Two", 2, "2:00")
	testing.SetRealm(testing.NewUserRealm(dave))
	catalog.RegisterArtist(cross(cur), "Dave Radio", "")
	three := publish(cur, "Three", 2, "1:00")

	testing.SetRealm(testing.NewUserRealm(carol))
	uassert.Equal(t, 3, Sync(cross(cur), 50))
	uassert.Equal(t, 0, Pending())

	// Main and genre station both start with track one.
	for _, s := range []int{MainStation, 2} {
		id, off, queued := NowPlaying(s)
		uassert.Equal(t, one, id)
		uassert.Equal(t, int64(0), off)
		uassert.False(t, queued)
	}
	id, _, _ := NowPlaying(3)
	uassert.Equal(t, 0, id) // empty genre station

	// 20s in, a new publication does not move listeners.
	testing.SkipHeights(4)
	id, off, _ := NowPlaying(2)
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
	id, _, queued := NowPlaying(2)
	uassert.Equal(t, three, id)
	uassert.True(t, queued)
	ups := stations[2].schedule
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
// reports it unplayable (the catalog admin cannot be impersonated from this
// package's tests: its admin is the empty deployer address under gno test).
func hide(stationID, trackID int, on bool) {
	st := stations[stationID]
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
}

func TestHideMovesToNextTrack(cur realm, t *testing.T) {
	reset()
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
	hide(3, a, true)
	id, off, _ = NowPlaying(3)
	uassert.Equal(t, b, id)
	uassert.Equal(t, int64(0), off)
	tracks, loop, _ := StationInfo(3)
	uassert.Equal(t, 2, tracks)
	uassert.Equal(t, int64(120), loop)

	// Hiding a track ahead of the listeners does not move them.
	testing.SkipHeights(4)
	id, off, _ = NowPlaying(3)
	hide(3, c, true)
	id2, off2, _ := NowPlaying(3)
	uassert.Equal(t, id, id2)
	uassert.Equal(t, off, off2)

	// Restoring it, or restoring A behind them, does not move anyone either.
	hide(3, c, false)
	hide(3, a, false)
	id3, off3, _ := NowPlaying(3)
	uassert.Equal(t, id, id3)
	uassert.Equal(t, off, off3)
	tracks, _, _ = StationInfo(3)
	uassert.Equal(t, 3, tracks)
}

func TestEditedDurationViaRefresh(cur realm, t *testing.T) {
	reset()
	testing.SetRealm(testing.NewUserRealm(alice))
	a := publish(cur, "Edit A", 6, "2:00")
	b := publish(cur, "Edit B", 6, "1:00")
	Sync(cross(cur), 50)
	testing.SkipHeights(10) // 50s into A

	// Shortening A below the current offset: B starts now.
	catalog.EditTrack(cross(cur), a, "Edit A", 6, "0:40", "", "ipfs://"+cid, "", "", "")
	testing.SetRealm(testing.NewUserRealm(carol))
	Refresh(cross(cur), a)
	id, off, _ := NowPlaying(6)
	uassert.Equal(t, b, id)
	uassert.Equal(t, int64(0), off)
	_, loop, _ := StationInfo(6)
	uassert.Equal(t, int64(100), loop)

	// Lengthening A (behind the listeners now) keeps them on B.
	testing.SkipHeights(2)
	id, off, _ = NowPlaying(6)
	testing.SetRealm(testing.NewUserRealm(alice))
	catalog.EditTrack(cross(cur), a, "Edit A", 6, "3:00", "", "ipfs://"+cid, "", "", "")
	testing.SetRealm(testing.NewUserRealm(carol))
	Refresh(cross(cur), a)
	id2, off2, _ := NowPlaying(6)
	uassert.Equal(t, id, id2)
	uassert.Equal(t, off, off2)
}

func TestHiddenQueuedSlotIsDropped(cur realm, t *testing.T) {
	reset()
	testing.SetRealm(testing.NewUserRealm(alice))
	a := publish(cur, "Drop A", 4, "1:00")
	b := publish(cur, "Drop B", 4, "1:00")
	Sync(cross(cur), 50)
	testing.SetRealm(testing.NewUserRealm(carol))
	Queue(cross(cur), 4, b)
	uassert.Equal(t, 1, len(UpNext(4)))
	hide(4, b, true)
	uassert.Equal(t, 0, len(UpNext(4)))
	id, _, _ := NowPlaying(4)
	uassert.Equal(t, a, id)
}

func TestGuards(cur realm, t *testing.T) {
	reset()
	testing.SetRealm(testing.NewCodeRealm("gno.land/r/evil/proxy"))
	uassert.AbortsContains(t, cur, "directly from your wallet", func() { Queue(cross(cur), 0, 1) })
	testing.SetRealm(testing.NewUserRealm(carol))
	uassert.AbortsContains(t, cur, "unknown station", func() { Queue(cross(cur), 99, 1) })
	uassert.AbortsContains(t, cur, "unknown track", func() { Queue(cross(cur), 0, 999999) })
	uassert.AbortsWithMessage(t, cur, "radio: admin only", func() { Freeze(cross(cur), true) })
	testing.SetRealm(testing.NewUserRealm(erin))
	Freeze(cross(cur), true)
	testing.SetRealm(testing.NewUserRealm(carol))
	uassert.AbortsContains(t, cur, "paused for maintenance", func() { Sync(cross(cur), 10) })
}

// Scale: a station with n rotation slots (built directly, without the
// catalog), then NowPlaying, ScheduleJSON and Queue. Compare the GAS lines of
// the Build and Ops tests: ops must barely grow with n (SPEC §6).
func bigStation(n int) *station {
	reset()
	st := stations[MainStation]
	ts := time.Now().Unix()
	for i := 0; i < n; i++ {
		st.rot.Append(1000000+i, 180)
		st.live++
	}
	st.anchor(ts, 0)
	return st
}

func scaleOps(cur realm, t *testing.T) {
	testing.SetRealm(testing.NewUserRealm(alice))
	tr := publish(cur, "Scale", 1, "3:00")
	synced = tr // only this track gets synced
	synced--
	Sync(cross(cur), 5)
	testing.SkipHeights(1000)
	for k := 0; k < 10; k++ {
		NowPlaying(MainStation)
	}
	_ = ScheduleJSON(MainStation, 3600)
	testing.SetRealm(testing.NewUserRealm(bob))
	Queue(cross(cur), MainStation, tr)
}

func TestScaleBuild1k(cur realm, t *testing.T)  { bigStation(1000) }
func TestScaleOps1k(cur realm, t *testing.T)    { bigStation(1000); scaleOps(cur, t) }
func TestScaleBuild20k(cur realm, t *testing.T) { bigStation(20000) }
func TestScaleOps20k(cur realm, t *testing.T)   { bigStation(20000); scaleOps(cur, t) }
