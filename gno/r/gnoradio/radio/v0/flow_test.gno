package radio

import (
	"testing"
	"time"

	"gno.land/p/nt/testutils/v0"
	"gno.land/p/nt/uassert/v0"
	"gno.land/p/nt/urequire/v0"
	"gno.land/r/gnoradio/catalog/v0"
)

func energyIndex(genre int) int {
	for i, g := range energy {
		if g == genre {
			return i
		}
	}
	return -1
}

// Sync writes an hour of the main station in sets of one genre, moving only
// between neighbours on the energy line, never the same artist twice in a row
// nor a track twice; a listener pick goes before the flow, which moves back.
func TestMainFlow(cur realm, t *testing.T) {
	reset()
	x, y := testutils.TestAddress("flowx"), testutils.TestAddress("flowy")
	testing.SetRealm(testing.NewUserRealm(x))
	catalog.RegisterArtist(cross(cur), "Flow X", "")
	testing.SetRealm(testing.NewUserRealm(y))
	catalog.RegisterArtist(cross(cur), "Flow Y", "")
	var tracks []int
	for _, g := range []int{3, 11, 10} { // Ambient, Cinematic, Folk: the calm end
		for k := 0; k < 8; k++ {
			who := x
			if k%2 == 1 {
				who = y
			}
			testing.SetRealm(testing.NewUserRealm(who))
			tracks = append(tracks, publish(cur, "Flow", g, "3:00"))
		}
	}
	testing.SetRealm(testing.NewUserRealm(carol))
	Sync(cross(cur), 50)

	st := stations[MainStation]
	urequire.True(t, len(st.schedule) >= 12)
	uassert.Equal(t, 0, len(UpNext(MainStation))) // the flow is not a listener queue
	_, _, queued := NowPlaying(MainStation)
	uassert.False(t, queued)
	seen := map[int]bool{}
	run := 0
	for i, s := range st.schedule {
		uassert.Equal(t, address(""), s.By)
		uassert.False(t, seen[s.Track])
		seen[s.Track] = true
		a, g, _, _ := catalog.TrackBrief(s.Track)
		run++
		if i == 0 {
			continue
		}
		prev := st.schedule[i-1]
		uassert.Equal(t, prev.Start+prev.Dur, s.Start) // gapless
		pa, pg, _, _ := catalog.TrackBrief(prev.Track)
		uassert.NotEqual(t, pa, a)
		if g != pg {
			uassert.Equal(t, 1, abs(energyIndex(g)-energyIndex(pg)))
			run = 1
		}
		uassert.True(t, run <= 5)
	}

	// A listener pick airs at once over a flow track (the app crossfades) and
	// takes the place of the flow's next track; the flow follows, gapless.
	pick := 0
	for _, id := range tracks {
		if !seen[id] && pick == 0 {
			pick = id
		}
	}
	onAir := st.schedule[0]
	testing.SkipHeights((onAir.Start - time.Now().Unix() + 60) / 5)
	ts := time.Now().Unix()
	next := st.schedule[2] // the flow track after the one the pick replaces
	Queue(cross(cur), MainStation, pick)
	id, _, queued := NowPlaying(MainStation)
	uassert.Equal(t, pick, id)
	uassert.True(t, queued)
	i := slotOf(st, pick)
	uassert.Equal(t, ts, st.schedule[i].Start)
	uassert.Equal(t, ts, st.schedule[i-1].Start+st.schedule[i-1].Dur) // the flow track was cut, not skipped
	uassert.Equal(t, next.Track, st.schedule[i+1].Track)
	uassert.Equal(t, ts+180, st.schedule[i+1].Start)

	// While a listener's pick is on air, the next pick waits for it, and a
	// track the flow had planned can be picked: it leaves the flow.
	planned := st.schedule[i+2].Track
	testing.SetRealm(testing.NewUserRealm(dave))
	Queue(cross(cur), MainStation, planned)
	j := slotOf(st, planned)
	uassert.Equal(t, i+1, j)
	uassert.Equal(t, ts+180, st.schedule[j].Start)
	uassert.Equal(t, "", string(st.schedule[j+1].By))
	uassert.Equal(t, st.schedule[j].Start+st.schedule[j].Dur, st.schedule[j+1].Start)
	count := 0
	for _, s := range st.schedule {
		if s.Track == planned {
			count++
		}
	}
	uassert.Equal(t, 1, count)
}

func slotOf(st *station, track int) int {
	for i, s := range st.schedule {
		if s.Track == track {
			return i
		}
	}
	return -1
}

// Each set steps toward the daypart's energy (UTC), and wanders around it.
func TestNextGenreFollowsDayparts(cur realm, t *testing.T) {
	reset()
	for _, st := range stations {
		st.live = 1
	}
	night, evening := int64(4*3600), int64(20*3600) // targets Ambient, Electronic
	uassert.Equal(t, 1, nextGenre(4, night))        // Techno -> Electronic, calming down
	uassert.Equal(t, 11, nextGenre(3, evening))     // Ambient -> Cinematic, warming up
	g := nextGenre(1, evening)                      // at the target: one step either way
	uassert.True(t, g == 2 || g == 4)
	stations[11].live, stations[10].live = 0, 0
	uassert.Equal(t, 9, nextGenre(3, evening)) // empty genres are skipped
	for _, st := range stations {
		st.live = 0
	}
	uassert.Equal(t, 0, nextGenre(3, evening))
}

func abs(n int) int {
	if n < 0 {
		return -n
	}
	return n
}
