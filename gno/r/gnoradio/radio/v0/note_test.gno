package radio

import (
	"strings"
	"testing"

	"gno.land/p/nt/testutils/v0"
	"gno.land/p/nt/uassert/v0"

	"gno.land/r/gnoradio/catalog/v0"
)

// A dedication airs with the pick; bad ones are refused; three reports hide
// it and pause its author's dedications.
func TestDedications(cur realm, t *testing.T) {
	reset()
	testing.SetRealm(testing.NewUserRealm(testutils.TestAddress("note_artist")))
	catalog.RegisterArtist(cross(cur), "Note Artist", "")
	tracks := []int{publish(cur, "Note A", 3, "3:00"), publish(cur, "Note B", 3, "3:00")}
	testing.SetRealm(testing.NewUserRealm(carol))
	Sync(cross(cur), 50)
	testing.SetRealm(testing.NewUserRealm(alice))
	uassert.AbortsContains(t, cur, "dedication: no links", func() { QueueWithNote(cross(cur), MainStation, tracks[0], "go to x.com") })
	uassert.AbortsContains(t, cur, "please rephrase", func() { QueueWithNote(cross(cur), MainStation, tracks[0], "f u c k you") })
	QueueWithNote(cross(cur), MainStation, tracks[0], "for Marie, happy birthday!")
	s := stations[MainStation].schedule[slotOf(stations[MainStation], tracks[0])]
	uassert.Equal(t, "for Marie, happy birthday!", s.Note)
	// It waits noteGrace seconds for the moderation robot, then shows everywhere.
	uassert.False(t, strings.Contains(ScheduleJSON(MainStation, 600), "for Marie"))
	uassert.True(t, strings.Contains(PendingNotesJSON(), `"note":"for Marie, happy birthday!"`))
	testing.SkipHeights(noteGrace/5 + 1)
	uassert.True(t, strings.Contains(ScheduleJSON(MainStation, 600), `"note":"for Marie, happy birthday!"`))

	uassert.AbortsContains(t, cur, "your own", func() { ReportNote(cross(cur), MainStation, s.Start) })
	for i, who := range []string{"r1", "r2", "r3"} {
		testing.SetRealm(testing.NewUserRealm(testutils.TestAddress(who)))
		ReportNote(cross(cur), MainStation, s.Start)
		if i == 0 {
			uassert.AbortsContains(t, cur, "already reported", func() { ReportNote(cross(cur), MainStation, s.Start) })
		}
	}
	uassert.True(t, stations[MainStation].schedule[slotOf(stations[MainStation], tracks[0])].NoteHidden)
	uassert.False(t, strings.Contains(ScheduleJSON(MainStation, 600), "for Marie"))
	testing.SetRealm(testing.NewUserRealm(alice))
	uassert.AbortsContains(t, cur, "paused after reports", func() { QueueWithNote(cross(cur), MainStation, tracks[1], "hello") })

	uassert.AbortsWithMessage(t, cur, "radio: admin only", func() { Unmute(cross(cur), alice) })
	testing.SetRealm(testing.NewUserRealm(erin))
	Unmute(cross(cur), alice)
	_, still := muted.Get(alice.String())
	uassert.False(t, still)
}

// Reports on an unqueued slot do not carry over to the next pick at its start.
func TestStaleReports(cur realm, t *testing.T) {
	reset()
	testing.SetRealm(testing.NewUserRealm(testutils.TestAddress("stale_artist")))
	catalog.RegisterArtist(cross(cur), "Stale Artist", "")
	a, b := publish(cur, "Stale A", 4, "3:00"), publish(cur, "Stale B", 4, "3:00")
	testing.SetRealm(testing.NewUserRealm(carol))
	Sync(cross(cur), 50)
	QueueWithNote(cross(cur), 4, a, "bait")
	x := stations[4].schedule[0].Start
	for _, who := range []string{"s1", "s2"} {
		testing.SetRealm(testing.NewUserRealm(testutils.TestAddress(who)))
		ReportNote(cross(cur), 4, x)
	}
	testing.SetRealm(testing.NewUserRealm(erin))
	Unqueue(cross(cur), 4, a)
	testing.SetRealm(testing.NewUserRealm(alice))
	QueueWithNote(cross(cur), 4, b, "for Marie")
	uassert.Equal(t, x, stations[4].schedule[0].Start)
	testing.SetRealm(testing.NewUserRealm(testutils.TestAddress("s3")))
	ReportNote(cross(cur), 4, x)
	uassert.Equal(t, "for Marie", stations[4].schedule[0].Note)
}

// The moderation robot can only hide, within its daily cap; the admin restores.
func TestModerationRobot(cur realm, t *testing.T) {
	reset()
	robot := testutils.TestAddress("mod_robot")
	testing.SetRealm(testing.NewUserRealm(testutils.TestAddress("mod_artist")))
	catalog.RegisterArtist(cross(cur), "Mod Artist", "")
	a := publish(cur, "Mod A", 5, "3:00")
	testing.SetRealm(testing.NewUserRealm(carol))
	Sync(cross(cur), 50)
	testing.SetRealm(testing.NewUserRealm(alice))
	QueueWithNote(cross(cur), 5, a, "you are worthless")
	start := stations[5].schedule[0].Start

	uassert.AbortsContains(t, cur, "moderation robot only", func() { HideNote(cross(cur), 5, start, "harassment") })
	testing.SetRealm(testing.NewUserRealm(erin))
	SetModBot(cross(cur), robot)
	testing.SetRealm(testing.NewUserRealm(robot))
	HideNote(cross(cur), 5, start, "harassment")
	uassert.True(t, stations[5].schedule[0].NoteHidden)
	uassert.Equal(t, "[]", PendingNotesJSON())
	_, mutedNow := muted.Get(alice.String())
	uassert.False(t, mutedNow) // the robot never mutes
	uassert.AbortsContains(t, cur, "admin only", func() { RestoreNote(cross(cur), 5, start) })
	hides = maxBotHides
	uassert.AbortsContains(t, cur, "limit reached", func() { HideNote(cross(cur), 5, start, "x") })

	testing.SetRealm(testing.NewUserRealm(erin))
	RestoreNote(cross(cur), 5, start)
	s := stations[5].schedule[0]
	uassert.False(t, s.NoteHidden)
	uassert.Equal(t, "you are worthless", s.shownNote(s.NoteAt+noteGrace))
}

// A listener pick brings newly published tracks to the stations: the radio
// keeps up without a robot paying for Sync.
func TestPickIngests(cur realm, t *testing.T) {
	reset()
	testing.SetRealm(testing.NewUserRealm(testutils.TestAddress("ingest_artist")))
	catalog.RegisterArtist(cross(cur), "Ingest Artist", "")
	a := publish(cur, "Ingest A", 6, "3:00")
	testing.SetRealm(testing.NewUserRealm(carol))
	Sync(cross(cur), 50)
	testing.SetRealm(testing.NewUserRealm(testutils.TestAddress("ingest_artist")))
	publish(cur, "Ingest B", 6, "3:00")
	uassert.Equal(t, catalog.TrackCount()-1, synced)
	testing.SetRealm(testing.NewUserRealm(alice))
	Queue(cross(cur), 6, a)
	uassert.Equal(t, catalog.TrackCount(), synced)
	uassert.False(t, NeedsSync() && synced < catalog.TrackCount())
}
