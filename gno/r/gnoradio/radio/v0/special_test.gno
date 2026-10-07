package radio

import (
	"strings"
	"testing"

	"gno.land/p/nt/testutils/v0"
	"gno.land/p/nt/uassert/v0"
	"gno.land/r/gnoradio/catalog/v0"
)

// Every ingested track joins New; past newCap the oldest goes silent and
// leaves homes, so Refresh does not bring it back.
func TestNewStation(cur realm, t *testing.T) {
	reset()
	testing.SetRealm(testing.NewUserRealm(testutils.TestAddress("newartist")))
	catalog.RegisterArtist(cross(cur), "New Artist", "")
	first := publish(cur, "New 0", 3, "1:00")
	for i := 1; i <= newCap; i++ {
		publish(cur, "New "+itoa(i), 1+i%catalog.NumGenres, "1:00")
	}
	Sync(cross(cur), 100)
	id, _, _ := NowPlaying(NewStation)
	uassert.Equal(t, first, id)
	tracks, loop, _ := StationInfo(NewStation)
	uassert.Equal(t, 100, tracks)
	uassert.Equal(t, int64(6000), loop)

	Sync(cross(cur), 200)
	Sync(cross(cur), 200) // newCap+1 tracks: the newest takes the first one's slot
	tracks, _, _ = StationInfo(NewStation)
	uassert.Equal(t, newCap, tracks)
	uassert.Equal(t, newCap, stations[NewStation].rot.Len()) // a ring: it never grows past newCap
	id, d := stations[NewStation].rot.Slot(0)
	uassert.Equal(t, first+newCap, id)
	uassert.Equal(t, int64(60), d)
	uassert.Equal(t, 1, homesOf(first + newCap)[NewStation]) // slot 0
	_, in := homesOf(first)[NewStation]
	uassert.False(t, in)
	_, in = homesOf(first + 1)[NewStation]
	uassert.True(t, in)
	Refresh(cross(cur), first)
	tracks, _, _ = StationInfo(NewStation)
	uassert.Equal(t, newCap, tracks)
	tracks, _, _ = StationInfo(3)
	uassert.True(t, tracks > 0) // its genre station keeps it
}

// A listener pick adds its track to Choice once; curator picks do not; the
// most liked tracks are seeded by Sync; picks on New and Choice skip the
// genre check.
func TestChoiceStation(cur realm, t *testing.T) {
	reset()
	testing.SetRealm(testing.NewUserRealm(testutils.TestAddress("choiceartist")))
	catalog.RegisterArtist(cross(cur), "Choice Artist", "")
	a := publish(cur, "Choice A", 2, "1:00")
	b := publish(cur, "Choice B", 5, "2:00")
	c := publish(cur, "Choice C", 7, "3:00")
	Sync(cross(cur), 10)
	tracks, _, _ := StationInfo(ChoiceStation)
	uassert.Equal(t, 0, tracks)

	testing.SetRealm(testing.NewUserRealm(alice))
	Queue(cross(cur), 2, a)
	testing.SetRealm(testing.NewUserRealm(bob))
	Queue(cross(cur), MainStation, a)
	dedicate(cur, ChoiceStation, b, "for you")
	testing.SetRealm(testing.NewUserRealm(erin))
	CuratorQueue(cross(cur), NewStation, c)
	ids, durs := RotationPage(ChoiceStation, 0, 10)
	uassert.Equal(t, 2, len(ids))
	uassert.Equal(t, a, ids[0])
	uassert.Equal(t, b, ids[1])
	uassert.Equal(t, int64(120), durs[1])

	testing.SetRealm(testing.NewUserRealm(carol))
	Queue(cross(cur), NewStation, b)
	uassert.Equal(t, b, UpNext(NewStation)[1].Track) // after the curator's pick
	uassert.Equal(t, 1, len(UpNext(ChoiceStation)))
	uassert.True(t, strings.Contains(ScheduleJSON(ChoiceStation, 3600), `"by":"`+bob.String()))

	catalog.Like(cross(cur), c)
	Sync(cross(cur), 10)
	ids, _ = RotationPage(ChoiceStation, 0, 10)
	uassert.Equal(t, 3, len(ids))
	uassert.Equal(t, c, ids[2])

	// The cap: past keep entries the oldest slot is reused; its track can come back.
	ts := now()
	stations[ChoiceStation].join(c, 180, ts, 2) // stands for the cap: 3 joins so far, slot 3%2 is reused
	id, d := stations[ChoiceStation].rot.Slot(1)
	uassert.Equal(t, c, id)
	uassert.Equal(t, int64(180), d)
	uassert.Equal(t, 3, stations[ChoiceStation].rot.Len())
	_, in := homesOf(b)[ChoiceStation]
	uassert.False(t, in)
	choose(b, 120, ts)
	_, in = homesOf(b)[ChoiceStation]
	uassert.True(t, in)
}

func TestSpecialStationsListed(cur realm, t *testing.T) {
	reset()
	uassert.Equal(t, catalog.NumGenres+3, StationCount())
	uassert.Equal(t, "New this week", StationName(NewStation))
	uassert.Equal(t, "Listeners' choice", StationName(ChoiceStation))
	js := StationsJSON()
	uassert.True(t, strings.Contains(js, `"name":"New this week"`))
	uassert.True(t, strings.Contains(js, `"name":"Listeners' choice"`))
}
