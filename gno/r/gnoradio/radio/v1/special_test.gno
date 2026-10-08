package radio

import (
	"strings"
	"testing"

	"gno.land/p/gnoradio/text/v0"
	"gno.land/p/nt/testutils/v0"
	"gno.land/p/nt/uassert/v0"
	"gno.land/r/gnoradio/catalog/v1"
)

// Every ingested track joins New; past newCap the oldest goes silent and
// leaves New's index, so Refresh does not bring it back.
func TestNewStation(cur realm, t *testing.T) {
	reset(cur)
	testing.SetRealm(testing.NewUserRealm(testutils.TestAddress("newartist")))
	catalog.RegisterArtist(cross(cur), "New Artist", "")
	first := publish(cur, "New 0", 3, "1:00")
	for i := 1; i < newCap; i++ {
		publish(cur, "New "+text.Itoa(i), 1+i%catalog.NumGenres, "1:00")
	}
	id, _, _ := NowPlaying(NewStation)
	uassert.Equal(t, first, id)
	tracks, loop, _ := StationInfo(NewStation)
	uassert.Equal(t, newCap, tracks)
	uassert.Equal(t, int64(60*newCap), loop)

	publish(cur, "New "+text.Itoa(newCap), 1, "1:00") // newCap+1 tracks: the newest takes the first one's slot
	tracks, _, _ = StationInfo(NewStation)
	uassert.Equal(t, newCap, tracks)
	st := sta(NewStation)
	uassert.Equal(t, newCap, st.count()) // a ring: it never grows past newCap
	id, d := st.rotSlot(0)
	uassert.Equal(t, first+newCap, id)
	uassert.Equal(t, int64(60), d)
	i, in := st.ringSlot(first + newCap)
	uassert.True(t, in)
	uassert.Equal(t, 0, i)
	_, in = st.ringSlot(first)
	uassert.False(t, in)
	_, in = st.ringSlot(first + 1)
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
	reset(cur)
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
	dedicate(cur, bob, ChoiceStation, b, "for you")
	testing.SetRealm(testing.NewUserRealm(erin))
	CuratorQueue(cross(cur), NewStation, c)
	ch := sta(ChoiceStation)
	uassert.Equal(t, 2, ch.count())
	id, _ := ch.rotSlot(0)
	uassert.Equal(t, a, id)
	id, d := ch.rotSlot(1)
	uassert.Equal(t, b, id)
	uassert.Equal(t, int64(120), d)

	testing.SetRealm(testing.NewUserRealm(carol))
	Queue(cross(cur), NewStation, b)
	uassert.Equal(t, b, UpNext(NewStation)[1].Track) // after the curator's pick
	uassert.Equal(t, 1, len(UpNext(ChoiceStation)))
	uassert.True(t, strings.Contains(ScheduleJSON(ChoiceStation, 3600), `"by":"`+bob.String()))

	catalog.Like(cross(cur), c)
	Sync(cross(cur), 10)
	ch = sta(ChoiceStation)
	uassert.Equal(t, 3, ch.count())
	id, _ = ch.rotSlot(2)
	uassert.Equal(t, c, id)

	// The cap: past keep entries the oldest slot is reused; its track can come back.
	ts := now()
	edit(cur, func(t *tx) { t.station(ChoiceStation).join(c, 180, ts, 2) }) // stands for the cap: 3 joins so far, slot 3%2 is reused
	ch = sta(ChoiceStation)
	id, d = ch.rotSlot(1)
	uassert.Equal(t, c, id)
	uassert.Equal(t, int64(180), d)
	uassert.Equal(t, 3, ch.count())
	_, in := ch.ringSlot(b)
	uassert.False(t, in)
	edit(cur, func(t *tx) { choose(t, b, 120, ts) })
	_, in = sta(ChoiceStation).ringSlot(b)
	uassert.True(t, in)
}

func TestSpecialStationsListed(cur realm, t *testing.T) {
	reset(cur)
	uassert.Equal(t, catalog.NumGenres+3, StationCount())
	uassert.Equal(t, "New this week", StationName(NewStation))
	uassert.Equal(t, "Listeners' choice", StationName(ChoiceStation))
	js := StationsJSON()
	uassert.True(t, strings.Contains(js, `"name":"New this week"`))
	uassert.True(t, strings.Contains(js, `"name":"Listeners' choice"`))
}
