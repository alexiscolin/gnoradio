package radio

import (
	"crypto/ed25519"
	"encoding/hex"
	"strings"
	"testing"

	"gno.land/p/gnoradio/text/v0"
	"gno.land/p/nt/testutils/v0"
	"gno.land/p/nt/uassert/v0"
	"gno.land/p/nt/urequire/v0"
	"gno.land/r/gnoradio/catalog/v1"
	"gno.land/r/gnoradio/data"
)

// The robot's test key (app/netlify/bot.ts signCertificate, seed 0x07 * 32)
// and its real signatures of NoteMessage(alice, 5, "for Marie", 1234568000)
// on the test chain "dev", for this deployment and for a staging one on the
// same chain. Accepted and refused calls with real certificates are in
// filetests/z_note_cert_filetest.gno (a filetest's clock is fixed).
const (
	modPub     = "ea4a6c63e29c520abef5507b132ec5f9954776aebebe7b92421eea691446d22c"
	modCert    = "336f546ae1741c61c5a450e68179bf16fe819b054e379f28b1ccc9f873a4d8a2f51e568de15adc66d175a55b59090eb98e846d975b2352004079d954ea924105"
	modStaging = "1fc2ed66fd407decfcb55eb169d07bd1b003b5b7807e7b459db9e0a17bf9d37eb380f0944718dc25e356ac3149c75bfa93c3cf42f7226373525a71da23e35f0b"
)

// dedicate queues a pick with a dedication the robot approved, as
// QueueWithNote does once the certificate checks out (the certificate
// itself is the filetest's).
func dedicate(cur realm, by address, stationID, trackID int, note string) {
	testing.SetRealm(testing.NewCodeRealm(self))
	queue(cur, by, stationID, trackID, false, false, note, 0)
}

// picked gives a test listener the reputation reporting needs.
func picked(cur realm, who string) { trust(cur, testutils.TestAddress(who)) }

// noteAt is the start of a station's slot of track.
func noteAt(stationID, track int) Slot {
	for _, s := range sta(stationID).slots() {
		if s.Track == track {
			return s
		}
	}
	return Slot{}
}

func TestRealNoteCertificate(t *testing.T) {
	key, _ := hex.DecodeString(modPub)
	sig, _ := hex.DecodeString(modCert)
	msg := "gnoradio-note|dev|gno.land/r/gnoradio/data|" + alice.String() + "|5|for Marie|1234568000"
	uassert.Equal(t, msg, NoteMessage(alice, 5, "for Marie", 1234568000))
	uassert.True(t, ed25519.Verify(key, []byte(msg), sig))
	uassert.False(t, ed25519.Verify(key, []byte(NoteMessage(bob, 5, "for Marie", 1234568000)), sig))   // another wallet
	uassert.False(t, ed25519.Verify(key, []byte(NoteMessage(alice, 6, "for Marie", 1234568000)), sig)) // another station
	uassert.False(t, ed25519.Verify(key, []byte(NoteMessage(alice, 5, "for Marie!", 1234568000)), sig))
	// TestCertOtherDeployment: signed for a staging data realm on this chain.
	staging, _ := hex.DecodeString(modStaging)
	uassert.False(t, ed25519.Verify(key, []byte(msg), staging))
}

// Without the robot's approval, an expired one or with dedications off, a
// dedication is refused; a pick without one still works.
func TestNoteCertificateGuards(cur realm, t *testing.T) {
	reset(cur)
	testing.SetRealm(testing.NewUserRealm(testutils.TestAddress("cert_artist")))
	catalog.RegisterArtist(cross(cur), "Cert Artist", "")
	a := publish(cur, "Cert A", 5, "3:00")
	testing.SetRealm(testing.NewUserRealm(carol))
	Sync(cross(cur), 50)
	testing.SetRealm(testing.NewUserRealm(alice))
	good := strings.Repeat("ab", 64)
	uassert.AbortsContains(t, cur, "dedications are paused", func() { QueueWithNote(cross(cur), 5, a, "hi", now()+60, good) })
	uassert.AbortsContains(t, cur, "admin only", func() { SetModBot(cross(cur), modPub) })
	testing.SetRealm(testing.NewUserRealm(erin))
	uassert.AbortsContains(t, cur, "32-byte", func() { SetModBot(cross(cur), "abcd") })
	SetModBot(cross(cur), modPub)
	testing.SetRealm(testing.NewUserRealm(alice))
	uassert.AbortsContains(t, cur, "expired", func() { QueueWithNote(cross(cur), 5, a, "hi", now(), good) })
	uassert.AbortsContains(t, cur, "expired", func() { QueueWithNote(cross(cur), 5, a, "hi", now()+noteCertLife+1, good) })
	uassert.AbortsContains(t, cur, "not approved", func() { QueueWithNote(cross(cur), 5, a, "hi", now()+60, strings.Repeat("cd", 64)) })
	uassert.AbortsContains(t, cur, "not approved", func() { QueueWithNote(cross(cur), 5, a, "hi", now()+60, "zz") })
	uassert.Equal(t, int64(900), int64(noteCertLife))
	Queue(cross(cur), 5, a) // without one
	testing.SetRealm(testing.NewUserRealm(erin))
	SetModBot(cross(cur), "")
	v, _ := data.Get(cConfig, "modbot")
	uassert.Equal(t, "", v)
}

// A dedication airs with the pick; bad ones are refused; three reports hide
// it and pause its author's dedications.
func TestDedications(cur realm, t *testing.T) {
	reset(cur)
	testing.SetRealm(testing.NewUserRealm(testutils.TestAddress("note_artist")))
	catalog.RegisterArtist(cross(cur), "Note Artist", "")
	tracks := []int{publish(cur, "Note A", 3, "3:00"), publish(cur, "Note B", 3, "3:00")}
	testing.SetRealm(testing.NewUserRealm(carol))
	Sync(cross(cur), 50)
	// p/gnoradio/safe judges the text before the certificate.
	testing.SetRealm(testing.NewUserRealm(alice))
	uassert.AbortsContains(t, cur, "dedication: no links", func() { QueueWithNote(cross(cur), 3, tracks[0], "go to x.com", now()+60, "") })
	uassert.AbortsContains(t, cur, "please rephrase", func() { QueueWithNote(cross(cur), 3, tracks[0], "f u c k you", now()+60, "") })
	dedicate(cur, alice, 3, tracks[0], "for Marie, happy birthday!")
	s := noteAt(3, tracks[0])
	uassert.Equal(t, "for Marie, happy birthday!", s.Note)
	uassert.True(t, strings.Contains(ScheduleJSON(3, 600), `"note":"for Marie, happy birthday!"`))

	testing.SetRealm(testing.NewUserRealm(alice))
	uassert.AbortsContains(t, cur, "your own", func() { ReportNote(cross(cur), 3, s.Start) })
	testing.SetRealm(testing.NewUserRealm(testutils.TestAddress("r1")))
	uassert.AbortsContains(t, cur, "reporting needs", func() { ReportNote(cross(cur), 3, s.Start) })
	for i, who := range []string{"r1", "r2", "r3"} {
		picked(cur, who)
		testing.SetRealm(testing.NewUserRealm(testutils.TestAddress(who)))
		ReportNote(cross(cur), 3, s.Start)
		if i == 0 {
			uassert.AbortsContains(t, cur, "already reported", func() { ReportNote(cross(cur), 3, s.Start) })
		}
	}
	uassert.True(t, noteAt(3, tracks[0]).NoteHidden)
	uassert.False(t, strings.Contains(ScheduleJSON(3, 600), "for Marie"))
	// A first hidden dedication is only a strike: the author can still dedicate.
	uassert.False(t, data.Has(cMuted, alice.String()))
	uassert.Equal(t, int64(0), MutedUntil(alice))
	testing.SkipHeights(720) // an hour: alice may pick here again
	dedicate(cur, alice, 3, tracks[1], "hello")
	s = noteAt(3, tracks[1])
	for _, who := range []string{"r1", "r2", "r3"} {
		testing.SetRealm(testing.NewUserRealm(testutils.TestAddress(who)))
		ReportNote(cross(cur), 3, s.Start)
	}
	// The second within a week mutes them.
	testing.SetRealm(testing.NewUserRealm(alice))
	uassert.AbortsContains(t, cur, "paused after reports", func() { QueueWithNote(cross(cur), NewStation, tracks[0], "hello", now()+60, "") })
	uassert.Equal(t, now()+muteFor, MutedUntil(alice)) // the robot reads it before signing

	uassert.AbortsWithMessage(t, cur, "radio: admin only", func() { Unmute(cross(cur), alice) })
	testing.SetRealm(testing.NewUserRealm(erin))
	Unmute(cross(cur), alice)
	uassert.False(t, data.Has(cMuted, alice.String()))
	uassert.Equal(t, int64(0), MutedUntil(alice))
	uassert.AbortsContains(t, cur, "not muted", func() { Unmute(cross(cur), alice) })
}

// Reports on an unqueued slot do not carry over to the next pick at its start.
func TestStaleReports(cur realm, t *testing.T) {
	reset(cur)
	testing.SetRealm(testing.NewUserRealm(testutils.TestAddress("stale_artist")))
	catalog.RegisterArtist(cross(cur), "Stale Artist", "")
	a, b := publish(cur, "Stale A", 4, "3:00"), publish(cur, "Stale B", 4, "3:00")
	testing.SetRealm(testing.NewUserRealm(carol))
	Sync(cross(cur), 50)
	dedicate(cur, carol, 4, a, "bait")
	x := sta(4).slots()[0].Start
	for _, who := range []string{"s1", "s2"} {
		picked(cur, who)
		testing.SetRealm(testing.NewUserRealm(testutils.TestAddress(who)))
		ReportNote(cross(cur), 4, x)
	}
	testing.SetRealm(testing.NewUserRealm(erin))
	Unqueue(cross(cur), 4, a)
	dedicate(cur, alice, 4, b, "for Marie")
	uassert.Equal(t, x, sta(4).slots()[0].Start)
	picked(cur, "s3")
	testing.SetRealm(testing.NewUserRealm(testutils.TestAddress("s3")))
	ReportNote(cross(cur), 4, x)
	uassert.Equal(t, "for Marie", sta(4).slots()[0].Note)
	uassert.False(t, sta(4).slots()[0].NoteHidden)
}

// PublishTrack puts the track on the air in the same transaction: its genre
// station (which Main simulcasts) and New, with nothing left for Sync, which never ingests it
// again. Nobody publishes for another wallet.
func TestPublishJoinsStations(cur realm, t *testing.T) {
	reset(cur)
	w := testutils.TestAddress("ingest_artist")
	testing.SetRealm(testing.NewUserRealm(w))
	catalog.RegisterArtist(cross(cur), "Ingest Artist", "")
	a := publish(cur, "Ingest A", 6, "3:00")
	uassert.Equal(t, catalog.TrackCount(), synced())
	uassert.Equal(t, 0, Pending())
	_, onMain := sta(MainStation).slot(a)
	uassert.False(t, onMain) // Main keeps no rotation
	for _, id := range []int{6, NewStation} {
		i, ok := sta(id).slot(a)
		urequire.True(t, ok, text.Itoa(id))
		got, d := sta(id).rotSlot(i)
		uassert.Equal(t, a, got)
		uassert.Equal(t, int64(180), d)
	}
	_, other := sta(7).slot(a)
	uassert.False(t, other)
	uassert.True(t, rd().hasLive(6)) // Main may relay its genre
	n := catalog.TrackCount()
	testing.SetRealm(testing.NewUserRealm(carol))
	uassert.Equal(t, 0, Sync(cross(cur), 50))
	uassert.Equal(t, 1, sta(6).count())

	// The profile is always the signer's: a wallet without one, a realm, or
	// the catalog called directly cannot publish for w.
	testing.SetRealm(testing.NewUserRealm(carol))
	uassert.AbortsContains(t, cur, "create your artist profile first", func() { publish(cur, "Forged", 6, "3:00") })
	testing.SetRealm(testing.NewCodeRealm("gno.land/r/evil/proxy"))
	uassert.AbortsContains(t, cur, "directly from your wallet", func() { publish(cur, "Forged", 6, "3:00") })
	testing.SetRealm(testing.NewUserRealm(w))
	uassert.AbortsContains(t, cur, "only the GnoRadio radio realm", func() {
		catalog.PublishFor(cross(cur), w, "Forged", 6, "3:00", "CC-BY", "none", "", "ipfs://"+cid, "", "", "", "", "yes")
	})
	uassert.Equal(t, n, catalog.TrackCount())
}

// Sync stays the safety net: a track the catalog added without the radio (a
// later catalog release, say) joins on the next one, and the radio refuses
// to publish past such a gap rather than misfile Main. A pick no longer
// ingests: it leaves the gap alone.
func TestSyncCatchesUp(cur realm, t *testing.T) {
	reset(cur)
	w := testutils.TestAddress("gap_artist")
	testing.SetRealm(testing.NewUserRealm(w))
	catalog.RegisterArtist(cross(cur), "Gap Artist", "")
	a := publish(cur, "Gap A", 6, "3:00")
	testing.SetRealm(testing.NewCodeRealm(self))
	catalog.PublishFor(cross(cur), w, "Gap B", 6, "3:00", "CC-BY", "none", "", "ipfs://"+cid, "", "", "", "", "yes")
	uassert.Equal(t, catalog.TrackCount()-1, synced())
	testing.SetRealm(testing.NewUserRealm(w))
	uassert.AbortsContains(t, cur, "call Sync first", func() { publish(cur, "Gap C", 6, "3:00") })
	testing.SetRealm(testing.NewUserRealm(alice))
	gap := synced()
	Queue(cross(cur), 6, a)
	uassert.Equal(t, gap, synced()) // a pick leaves the gap to Sync
	urequire.True(t, gap < catalog.TrackCount())
	Sync(cross(cur), 50)
	uassert.Equal(t, catalog.TrackCount(), synced())
	testing.SetRealm(testing.NewUserRealm(w))
	publish(cur, "Gap C", 6, "3:00")
	uassert.Equal(t, catalog.TrackCount(), synced())
}

// A track picked on a station cannot come back there for replayGap, whoever
// picks it: many wallets cannot loop one song.
func TestReplayGap(cur realm, t *testing.T) {
	reset(cur)
	testing.SetRealm(testing.NewUserRealm(testutils.TestAddress("loop_artist")))
	catalog.RegisterArtist(cross(cur), "Loop Artist", "")
	a := publish(cur, "Loop A", 7, "3:00")
	testing.SetRealm(testing.NewUserRealm(carol))
	Sync(cross(cur), 50)
	Queue(cross(cur), 7, a)
	testing.SkipHeights(4 * 60 / 5 * 3) // 12 minutes: the pick has played
	testing.SetRealm(testing.NewUserRealm(alice))
	uassert.AbortsContains(t, cur, "less than 3 hours ago", func() { Queue(cross(cur), 7, a) })
	Queue(cross(cur), NewStation, a) // another station is another audience
}

// Genre stations take only their genre; New takes only new tracks.
func TestPickBelongs(cur realm, t *testing.T) {
	reset(cur)
	testing.SetRealm(testing.NewUserRealm(testutils.TestAddress("genre_artist")))
	catalog.RegisterArtist(cross(cur), "Genre Artist", "")
	a := publish(cur, "Genre A", 7, "3:00")
	testing.SetRealm(testing.NewUserRealm(carol))
	Sync(cross(cur), 50)
	uassert.AbortsContains(t, cur, "does not belong", func() { Queue(cross(cur), 8, a) })
	edit(cur, func(t *tx) { t.setFlowAt(fSynced, 4, t.synced()+newCap) }) // a newCap tracks later, a is no longer new
	testing.SetRealm(testing.NewUserRealm(carol))
	uassert.AbortsContains(t, cur, "only new tracks", func() { Queue(cross(cur), NewStation, a) })
}

// Audit (open question): a dedication moved to where another one started
// keeps its own reports, and so does the other.
func TestMoveNotesKeepsReports(cur realm, t *testing.T) {
	reset(cur)
	a, b := int64(1_000_000), int64(1_000_300)
	edit(cur, func(x *tx) {
		x.set(cNotes, noteKey(4, a), "ra,")
		x.set(cNotes, noteKey(4, b), "rb,")
		x.station(4).moveNotes([]int64{a, b, b, b + 600}) // a moves to b's start, b later
	})
	ra, _ := data.Get(cNotes, noteKey(4, b))
	rb, _ := data.Get(cNotes, noteKey(4, b+600))
	uassert.Equal(t, "ra,", ra)
	uassert.Equal(t, "rb,", rb)
	uassert.False(t, data.Has(cNotes, noteKey(4, a)))
}
