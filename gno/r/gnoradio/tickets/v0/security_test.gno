package tickets

import (
	"strings"
	"testing"

	"gno.land/p/nt/uassert/v0"
	"gno.land/p/nt/urequire/v0"
)

// Y5: upcoming reads the start-ordered index, skips hidden, cancelled and
// past concerts; an artist holds at most 10 open future concerts.
func TestUpcomingIndexAndOpenCap(cur realm, t *testing.T) {
	reset()
	ensureArtist(cur, t)
	testing.SetRealm(testing.NewUserRealm(alice))
	var ids []int
	for i := 0; i < maxOpenAhead; i++ {
		ids = append(ids, CreateEvent(cross(cur), "Show", "Club", "", inHours(48-i*2), "0", 10))
	}
	uassert.AbortsContains(t, cur, "upcoming concerts at a time", func() {
		CreateEvent(cross(cur), "Show", "Club", "", inHours(100), "0", 10)
	})

	up := Upcoming(50)
	urequire.Equal(t, maxOpenAhead, len(up))
	uassert.Equal(t, ids[maxOpenAhead-1], up[0].ID) // soonest first

	CancelEvent(cross(cur), ids[0])
	testing.SetRealm(testing.NewUserRealm(bob))
	HideEvent(cross(cur), ids[1], true, "duplicate listing")
	uassert.Equal(t, maxOpenAhead-2, len(Upcoming(50)))
	js := EventsJSON(0, 50, true)
	uassert.False(t, strings.Contains(js, `"id":`+itoa(ids[1])+`,`))
	uassert.True(t, strings.Contains(js, `"id":`+itoa(ids[2])+`,`))
	HideEvent(cross(cur), ids[1], false, "")
	uassert.Equal(t, maxOpenAhead-1, len(Upcoming(50)))

	// The cancelled slot is free again; then a concert passing frees another.
	testing.SetRealm(testing.NewUserRealm(alice))
	CreateEvent(cross(cur), "Late", "Club", "", inHours(200), "0", 10)
	uassert.AbortsContains(t, cur, "upcoming concerts at a time", func() {
		CreateEvent(cross(cur), "Show", "Club", "", inHours(201), "0", 10)
	})
	testing.SkipHeights(31 * 720) // 31 hours: the soonest concert (in 30h) is over
	uassert.Equal(t, maxOpenAhead-1, len(Upcoming(50)))
	CreateEvent(cross(cur), "Next", "Club", "", inHours(202), "0", 10)
}

// A hidden artist's concerts leave the Upcoming index once anyone refreshes
// the artist, so hidden spam cannot fill the scan; restored, they come back.
func TestRefreshArtistPrunesUpcoming(cur realm, t *testing.T) {
	reset()
	ensureArtist(cur, t)
	testing.SetRealm(testing.NewUserRealm(alice))
	a := CreateEvent(cross(cur), "Show", "Club", "", inHours(48), "0", 10)
	b := CreateEvent(cross(cur), "Gone", "Club", "", inHours(50), "0", 10)
	CancelEvent(cross(cur), b)
	aid := getEvent(a).ArtistID
	uassert.Equal(t, 1, upcoming.Size())

	artistVisible = func(int) bool { return false } // moderators hid the profile
	testing.SetRealm(testing.NewUserRealm(carol))
	RefreshArtist(cross(cur), aid)
	uassert.Equal(t, 0, upcoming.Size())
	uassert.Equal(t, 0, len(Upcoming(50)))

	artistVisible = func(int) bool { return true }
	RefreshArtist(cross(cur), aid)
	uassert.Equal(t, 1, upcoming.Size()) // the cancelled one stays out
	uassert.Equal(t, a, Upcoming(50)[0].ID)
}
