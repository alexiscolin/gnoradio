package tickets

import (
	"strings"
	"testing"

	"gno.land/p/nt/uassert/v0"
)

// EventsJSON(all) jumps to its offset and hands back the next one; hidden
// concerts are left out of the page instead of ending the list.
func TestEventsJSONOffsetCursor(cur realm, t *testing.T) {
	reset()
	ensureArtist(cur, t)
	testing.SetRealm(testing.NewUserRealm(alice))
	var ids []int
	for i := 0; i < 5; i++ {
		ids = append(ids, CreateEvent(cross(cur), "Gig "+itoa(i), "Club", "", inHours(24+i), "0", 10))
	}
	testing.SetRealm(testing.NewUserRealm(bob))
	HideEvent(cross(cur), ids[3], true, "test hide")

	page := EventsJSON(0, 2, false) // newest first: ids 5, 4 (hidden)
	uassert.True(t, strings.Contains(page, `"title":"Gig 4"`), page)
	uassert.False(t, strings.Contains(page, `"title":"Gig 3"`), page)
	uassert.True(t, strings.HasSuffix(page, `],"next":2}`), page)

	page = EventsJSON(4, 2, false)
	uassert.True(t, strings.Contains(page, `"title":"Gig 0"`), page)
	uassert.True(t, strings.HasSuffix(page, `],"next":0}`), page)

	// Upcoming pages count listed concerts (Gig 0, 1, 2, 4) and carry next too.
	page = EventsJSON(0, 2, true)
	uassert.True(t, strings.Contains(page, `"title":"Gig 1"`), page)
	uassert.True(t, strings.HasSuffix(page, `],"next":2}`), page)
	page = EventsJSON(2, 2, true)
	uassert.True(t, strings.Contains(page, `"title":"Gig 4"`), page)
	uassert.True(t, strings.HasSuffix(page, `],"next":0}`), page)
}
