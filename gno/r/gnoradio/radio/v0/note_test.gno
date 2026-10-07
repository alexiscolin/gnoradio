package radio

import (
	"crypto/ed25519"
	"encoding/hex"
	"strings"
	"testing"

	"gno.land/p/nt/testutils/v0"
	"gno.land/p/nt/uassert/v0"

	"gno.land/r/gnoradio/catalog/v0"
)

// modPub is the public key of a throwaway robot; modCert its real signature
// of NoteMessage(alice, 5, "for Marie", 1234568000) on the test chain "dev".
const (
	modPub   = "dcd36c4f2e0c3f477d9220f9dfd048faecc315af26ac5980115c517880e551f5"
	modCert  = "d2628e6f30e27fdf2f6441d8bf1bb930abce07ae11c99bd658b3da135764561868294bc23a181a841c50c9bb103990dfa384a63dec085864a4207004575a830f"
	approved = "ab"
)

// dedicate queues with a dedication the robot approved. Chain id and clock
// move in tests, so a stand-in checks the signature: the real check is
// TestRealNoteCertificate.
func dedicate(cur realm, stationID, trackID int, note string) {
	noteKey, _ = hex.DecodeString(modPub)
	verifySig = func(_, _, sig []byte) bool { return hex.EncodeToString(sig) == strings.Repeat(approved, 64) }
	QueueWithNote(cross(cur), stationID, trackID, note, now()+60, strings.Repeat(approved, 64))
}

// picked gives a test listener one pick, which reporting needs.
func picked(who string) { credit(testutils.TestAddress(who), MainStation, 1, 0, 0) }

func TestRealNoteCertificate(t *testing.T) {
	key, _ := hex.DecodeString(modPub)
	sig, _ := hex.DecodeString(modCert)
	msg := "gnoradio-note|dev|" + alice.String() + "|5|for Marie|1234568000"
	uassert.Equal(t, msg, NoteMessage(alice, 5, "for Marie", 1234568000))
	uassert.True(t, ed25519.Verify(key, []byte(msg), sig))
	uassert.False(t, ed25519.Verify(key, []byte(NoteMessage(bob, 5, "for Marie", 1234568000)), sig))   // another wallet
	uassert.False(t, ed25519.Verify(key, []byte(NoteMessage(alice, 6, "for Marie", 1234568000)), sig)) // another station
	uassert.False(t, ed25519.Verify(key, []byte(NoteMessage(alice, 5, "for Marie!", 1234568000)), sig))
}

// A certificate copied from a public transaction serves no other wallet nor
// station; one living longer than 15 minutes is refused.
func TestNoteCertificateBound(cur realm, t *testing.T) {
	reset()
	testing.SetRealm(testing.NewUserRealm(testutils.TestAddress("bound_artist")))
	catalog.RegisterArtist(cross(cur), "Bound Artist", "")
	a := publish(cur, "Bound A", 5, "3:00")
	testing.SetRealm(testing.NewUserRealm(carol))
	Sync(cross(cur), 50)
	noteKey, _ = hex.DecodeString(modPub)
	exp := now() + 60
	cert := strings.Repeat(approved, 64)
	verifySig = func(_, msg, _ []byte) bool { return string(msg) == NoteMessage(alice, 5, "hi", exp) }
	testing.SetRealm(testing.NewUserRealm(bob))
	uassert.AbortsContains(t, cur, "not approved", func() { QueueWithNote(cross(cur), 5, a, "hi", exp, cert) })
	testing.SetRealm(testing.NewUserRealm(alice))
	uassert.AbortsContains(t, cur, "not approved", func() { QueueWithNote(cross(cur), 0, a, "hi", exp, cert) })
	uassert.Equal(t, int64(900), int64(noteCertLife))
	QueueWithNote(cross(cur), 5, a, "hi", exp, cert)
}

// Without the robot's approval, an expired one or with dedications off, a
// dedication is refused; a pick without one still works.
func TestNoteCertificateGuards(cur realm, t *testing.T) {
	reset()
	testing.SetRealm(testing.NewUserRealm(testutils.TestAddress("cert_artist")))
	catalog.RegisterArtist(cross(cur), "Cert Artist", "")
	a := publish(cur, "Cert A", 5, "3:00")
	testing.SetRealm(testing.NewUserRealm(carol))
	Sync(cross(cur), 50)
	testing.SetRealm(testing.NewUserRealm(alice))
	good := strings.Repeat(approved, 64)
	uassert.AbortsContains(t, cur, "dedications are paused", func() { QueueWithNote(cross(cur), 5, a, "hi", now()+60, good) })
	uassert.AbortsContains(t, cur, "admin only", func() { SetModBot(cross(cur), modPub) })
	testing.SetRealm(testing.NewUserRealm(erin))
	uassert.AbortsContains(t, cur, "32-byte", func() { SetModBot(cross(cur), "abcd") })
	SetModBot(cross(cur), modPub)
	verifySig = func(_, _, sig []byte) bool { return hex.EncodeToString(sig) == good }
	testing.SetRealm(testing.NewUserRealm(alice))
	uassert.AbortsContains(t, cur, "expired", func() { QueueWithNote(cross(cur), 5, a, "hi", now(), good) })
	uassert.AbortsContains(t, cur, "expired", func() { QueueWithNote(cross(cur), 5, a, "hi", now()+noteCertLife+1, good) })
	uassert.AbortsContains(t, cur, "not approved", func() { QueueWithNote(cross(cur), 5, a, "hi", now()+60, strings.Repeat("cd", 64)) })
	uassert.AbortsContains(t, cur, "not approved", func() { QueueWithNote(cross(cur), 5, a, "hi", now()+60, "zz") })
	QueueWithNote(cross(cur), 5, a, "hi", now()+60, good)
	uassert.True(t, strings.Contains(ScheduleJSON(5, 600), `"note":"hi"`)) // on air at once
	testing.SetRealm(testing.NewUserRealm(erin))
	SetModBot(cross(cur), "")
	uassert.Equal(t, 0, len(noteKey))
}

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
	uassert.AbortsContains(t, cur, "dedication: no links", func() { dedicate(cur, MainStation, tracks[0], "go to x.com") })
	uassert.AbortsContains(t, cur, "please rephrase", func() { dedicate(cur, MainStation, tracks[0], "f u c k you") })
	dedicate(cur, MainStation, tracks[0], "for Marie, happy birthday!")
	s := stations[MainStation].schedule[slotOf(stations[MainStation], tracks[0])]
	uassert.Equal(t, "for Marie, happy birthday!", s.Note)
	uassert.True(t, strings.Contains(ScheduleJSON(MainStation, 600), `"note":"for Marie, happy birthday!"`))

	uassert.AbortsContains(t, cur, "your own", func() { ReportNote(cross(cur), MainStation, s.Start) })
	testing.SetRealm(testing.NewUserRealm(testutils.TestAddress("r1")))
	uassert.AbortsContains(t, cur, "pick a track first", func() { ReportNote(cross(cur), MainStation, s.Start) })
	for i, who := range []string{"r1", "r2", "r3"} {
		picked(who)
		testing.SetRealm(testing.NewUserRealm(testutils.TestAddress(who)))
		ReportNote(cross(cur), MainStation, s.Start)
		if i == 0 {
			uassert.AbortsContains(t, cur, "already reported", func() { ReportNote(cross(cur), MainStation, s.Start) })
		}
	}
	uassert.True(t, stations[MainStation].schedule[slotOf(stations[MainStation], tracks[0])].NoteHidden)
	uassert.False(t, strings.Contains(ScheduleJSON(MainStation, 600), "for Marie"))
	// A first hidden dedication is only a strike: the author can still dedicate.
	_, isMuted := muted.Get(alice.String())
	uassert.False(t, isMuted)
	testing.SkipHeights(720) // an hour: alice may pick on Main again
	testing.SetRealm(testing.NewUserRealm(alice))
	dedicate(cur, MainStation, tracks[1], "hello")
	s = stations[MainStation].schedule[slotOf(stations[MainStation], tracks[1])]
	for _, who := range []string{"r1", "r2", "r3"} {
		testing.SetRealm(testing.NewUserRealm(testutils.TestAddress(who)))
		ReportNote(cross(cur), MainStation, s.Start)
	}
	// The second within a week mutes them.
	testing.SetRealm(testing.NewUserRealm(alice))
	uassert.AbortsContains(t, cur, "paused after reports", func() { dedicate(cur, NewStation, tracks[0], "hello") })

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
	dedicate(cur, 4, a, "bait")
	x := stations[4].schedule[0].Start
	for _, who := range []string{"s1", "s2"} {
		picked(who)
		testing.SetRealm(testing.NewUserRealm(testutils.TestAddress(who)))
		ReportNote(cross(cur), 4, x)
	}
	testing.SetRealm(testing.NewUserRealm(erin))
	Unqueue(cross(cur), 4, a)
	testing.SetRealm(testing.NewUserRealm(alice))
	dedicate(cur, 4, b, "for Marie")
	uassert.Equal(t, x, stations[4].schedule[0].Start)
	picked("s3")
	testing.SetRealm(testing.NewUserRealm(testutils.TestAddress("s3")))
	ReportNote(cross(cur), 4, x)
	uassert.Equal(t, "for Marie", stations[4].schedule[0].Note)
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

// A track picked on a station cannot come back there for replayGap, whoever
// picks it: many wallets cannot loop one song.
func TestReplayGap(cur realm, t *testing.T) {
	reset()
	testing.SetRealm(testing.NewUserRealm(testutils.TestAddress("loop_artist")))
	catalog.RegisterArtist(cross(cur), "Loop Artist", "")
	a := publish(cur, "Loop A", 7, "3:00")
	testing.SetRealm(testing.NewUserRealm(carol))
	Sync(cross(cur), 50)
	Queue(cross(cur), 7, a)
	testing.SkipHeights(4 * 60 / 5 * 3) // 12 minutes: the pick has played
	testing.SetRealm(testing.NewUserRealm(alice))
	uassert.AbortsContains(t, cur, "less than 3 hours ago", func() { Queue(cross(cur), 7, a) })
	Queue(cross(cur), MainStation, a) // another station is another audience
}

// Genre stations take only their genre; New takes only new tracks.
func TestPickBelongs(cur realm, t *testing.T) {
	reset()
	testing.SetRealm(testing.NewUserRealm(testutils.TestAddress("genre_artist")))
	catalog.RegisterArtist(cross(cur), "Genre Artist", "")
	a := publish(cur, "Genre A", 7, "3:00")
	testing.SetRealm(testing.NewUserRealm(carol))
	Sync(cross(cur), 50)
	uassert.AbortsContains(t, cur, "does not belong", func() { Queue(cross(cur), 8, a) })
	synced += newCap // a newCap tracks later, a is no longer new
	uassert.AbortsContains(t, cur, "only new tracks", func() { Queue(cross(cur), NewStation, a) })
}
