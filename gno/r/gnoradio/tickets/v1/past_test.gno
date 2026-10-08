package tickets

import (
	"testing"

	"gno.land/p/gnoradio/text/v0"
	"gno.land/p/nt/uassert/v0"
	"gno.land/r/gnoradio/catalog/v1"
)

// Past concerts page from the start-time index, latest first; a hidden
// profile's past concerts leave it once refreshed, and come back.
func TestPastEventsAndRefresh(cur realm, t *testing.T) {
	_, before := PastEvents(0, 100)
	w, aid := artist(cur, "Past Artist")
	var ids []int
	for i := 0; i < 3; i++ {
		ids = append(ids, CreateEvent(cross(cur), "Past "+text.Itoa(i), "Club", "", inHours(1+i), "0", 5))
	}
	uassert.AbortsContains(t, cur, "no past concert", func() { RefreshArtistPast(cross(cur), aid, 0) })
	testing.SkipHeights(4 * 720)
	got, total := PastEvents(0, 2)
	uassert.Equal(t, before+3, total)
	uassert.Equal(t, 2, len(got))
	uassert.Equal(t, ids[2], got[0]) // latest first
	uassert.Equal(t, ids[1], got[1])
	more, _ := PastEvents(2, 2)
	uassert.Equal(t, ids[0], more[0])
	none, _ := PastEvents(total, 10)
	uassert.Equal(t, 0, len(none))

	testing.SetRealm(testing.NewUserRealm(w))
	catalog.HideOwn(cross(cur), "artist", aid, true)
	RefreshArtistPast(cross(cur), aid, 0)
	_, total = PastEvents(0, 100)
	uassert.Equal(t, before, total)
	catalog.HideOwn(cross(cur), "artist", aid, false)
	RefreshArtistPast(cross(cur), aid, 0)
	_, total = PastEvents(0, 100)
	uassert.Equal(t, before+3, total)
}
