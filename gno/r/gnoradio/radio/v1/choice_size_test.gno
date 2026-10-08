package radio

import (
	"strings"
	"testing"

	"gno.land/p/gnoradio/store/v0"
	"gno.land/p/gnoradio/text/v0"
	"gno.land/p/nt/testutils/v0"
	"gno.land/p/nt/uassert/v0"
	"gno.land/r/gnoradio/catalog/v1"
)

// Audit open question 3: Listeners' choice at its worst, a full ring of
// choiceCap tracks plus maxKept listener slots each carrying a maxNote
// dedication of 4-byte characters, measured as save would write it.
func TestChoiceRecordWorstCase(cur realm, t *testing.T) {
	reset(cur)
	tx := rd()
	tx.setFlowAt(fSynced, 4, choiceCap)
	cs := tx.station(ChoiceStation)
	ts := now()
	for id := 1; id <= choiceCap; id++ {
		choose(tx, id, 240, ts)
	}
	ring := cs.size()
	note := strings.Repeat("𝄞", maxNote)
	var sl []Slot
	for i := 0; i < maxKept; i++ {
		sl = append(sl, Slot{Track: i + 1, Start: ts + int64(i)*240, Dur: 240, By: testutils.TestAddress("choicefan" + text.Itoa(i)), Note: note, artist: i + 1})
	}
	cs.setSlots(sl)
	t.Logf("choice record: ring %d bytes; %d noted slots would be %d bytes (picks stop at %d)", ring, maxKept, cs.size(), maxRecord-recordHeadroom)
	// What queue lets in: plain slots always fit beside the full ring, and a
	// dedication only takes the room they cannot need.
	for i := range sl {
		sl[i].Note = ""
	}
	cs.setSlots(sl)
	uassert.True(t, cs.size() <= maxRecord-recordHeadroom, "plain slots fit")
	for i := range sl {
		cs.picks += store.Fixed(int64(i+1), 4) + store.Fixed(ts, 6) // each pick's replay entry
		sl[i].Note = note
		cs.setSlots(sl)
		if cs.size()+noteReserve(cs, i) > maxRecord-recordHeadroom {
			sl[i].Note = "" // queue refuses this dedication; the plain pick goes in
			cs.setSlots(sl)
		}
	}
	cs.top = strings.Repeat("x", topMax) // and the week's top fills up
	uassert.True(t, cs.size() <= maxRecord-recordHeadroom, "never locked")
}

// Review R56: a dedication that would eat the plain picks' room is refused,
// and a plain pick still goes in right after.
func TestDedicationsFull(cur realm, t *testing.T) {
	reset(cur)
	testing.SetRealm(testing.NewUserRealm(testutils.TestAddress("full_artist")))
	catalog.RegisterArtist(cross(cur), "Full Artist", "")
	a, b := publish(cur, "Full A", 5, "3:00"), publish(cur, "Full B", 5, "3:00")
	ts := now()
	edit(cur, func(t *tx) {
		st := t.station(5)
		fill := ""
		for i := 0; st.size()+len(fill)+pickW < maxRecord-recordHeadroom-noteReserve(st, 0)-40; i++ {
			fill += store.Fixed(int64(9000+i), 4) + store.Fixed(ts, 6)
		}
		st.picks, st.dirty = st.picks+fill, true
	})
	testing.SetRealm(testing.NewCodeRealm(self))
	uassert.PanicsContains(t, cur, "dedications are full", func() { queue(cur, alice, 5, a, false, false, "for everyone listening tonight", 0) })
	testing.SetRealm(testing.NewUserRealm(bob))
	Queue(cross(cur), 5, b)
}
