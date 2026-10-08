// PKGPATH: gno.land/r/test/notecert
package notecert

// Dedications with real robot certificates. The vectors were signed by the
// robot's own code (app/netlify/bot.ts signCertificate, seed 0x07 * 32) over
// radio.NoteMessage: chain "dev", data realm gno.land/r/gnoradio/data, the
// wallet, the station, the note and the expiry (t0+600; a filetest's clock
// starts at t0).

import (
	"strings"
	"testing"

	"gno.land/p/nt/testutils/v0"
	catalog "gno.land/r/gnoradio/catalog/v1"
	radio "gno.land/r/gnoradio/radio/v1"
)

const (
	robotPub = "ea4a6c63e29c520abef5507b132ec5f9954776aebebe7b92421eea691446d22c"
	otherPub = "dcd36c4f2e0c3f477d9220f9dfd048faecc315af26ac5980115c517880e551f5"
	t0       = int64(1234567890)
	exp      = t0 + 600
	note     = "for Marie"
	ipfs     = "ipfs://bafybeigdyrzt5sfp7udm7hu76uh7y26nf3efuylqabf3oclgtqy55fbzdi"

	fan5     = "0d26fdcb5788bbc297200808a556cf82d5055af7ebff1168f0d63ba7dd223dcca74330af10cd777401dec5320ba8752afc88385dd6b301085a942738ebe02506" // fan, station 5
	fan6     = "1d444150be6bdb2beabd7ed85f2cf0742648277bd53cc66fbbbf32842f63da1a2969b6b6a5708cc2b817b634839a504faf72d815eb80b2b642d70237ec88cf0b" // fan, station 6
	fanStage = "74598f8d7f70019f3bfaffb0684369dfb1ba1b040f5635c99b1e65e918076089fb76598ed795842e61bdbf24e2e279b3f5312f5242d55be89ca39c511af3ca0a" // fan, station 5, gno.land/r/staging/gnoradio/data
)

var (
	fan    = testutils.TestAddress("fan")
	bob    = testutils.TestAddress("bob")
	artist = testutils.TestAddress("artist")
)

func check(ok bool, what string) {
	if !ok {
		println("FAIL:", what)
	}
}

// fails runs fn and checks that it aborts with a message holding want.
func fails(want string, fn func()) {
	r := revive(fn)
	s, _ := r.(string)
	if e, ok := r.(error); ok {
		s = e.Error()
	}
	if !strings.Contains(s, want) {
		println("FAIL: want abort", want, "got", s)
	}
}

func main(cur realm) {
	testing.SetRealm(testing.NewUserRealm(artist))
	catalog.RegisterArtist(cross(cur), "Cert Artist", "")
	a := radio.PublishTrack(cross(cur), "Cert A", 5, "3:00", "cc by", "none", "", ipfs, "", "", "", "", "yes")
	b := radio.PublishTrack(cross(cur), "Cert B", 6, "3:00", "cc by", "none", "", ipfs, "", "", "", "", "yes")
	radio.Sync(cross(cur), 10)
	check(radio.NoteMessage(fan, 5, note, exp) == "gnoradio-note|dev|gno.land/r/gnoradio/data|"+fan.String()+"|5|for Marie|1234568490", "message")

	// No robot key yet: dedications are off.
	testing.SetRealm(testing.NewUserRealm(fan))
	fails("dedications are paused", func() { radio.QueueWithNote(cross(cur), 5, a, note, exp, fan5) })
	testing.SetRealm(testing.NewUserRealm(radio.Admin()))
	radio.SetModBot(cross(cur), robotPub)

	// TestCertOtherWallet: fan's certificate is worthless to bob.
	testing.SetRealm(testing.NewUserRealm(bob))
	fails("not approved", func() { radio.QueueWithNote(cross(cur), 5, a, note, exp, fan5) })
	// TestCertOtherStation, other note: the same certificate elsewhere.
	testing.SetRealm(testing.NewUserRealm(fan))
	fails("not approved", func() { radio.QueueWithNote(cross(cur), 6, b, note, exp, fan5) })
	fails("not approved", func() { radio.QueueWithNote(cross(cur), 5, a, note+"!", exp, fan5) })
	// TestCertOtherDeployment: signed for a staging data realm on this chain.
	fails("not approved", func() { radio.QueueWithNote(cross(cur), 5, a, note, exp, fanStage) })
	// TestCertExpired: the expiry is part of what was signed, and checked.
	fails("expired", func() { radio.QueueWithNote(cross(cur), 5, a, note, t0, fan5) })
	fails("expired", func() { radio.QueueWithNote(cross(cur), 5, a, note, t0+901, fan5) })
	fails("not approved", func() { radio.QueueWithNote(cross(cur), 5, a, note, exp-1, fan5) })

	// A key rotation voids what the old key signed.
	testing.SetRealm(testing.NewUserRealm(radio.Admin()))
	radio.SetModBot(cross(cur), otherPub)
	testing.SetRealm(testing.NewUserRealm(fan))
	fails("not approved", func() { radio.QueueWithNote(cross(cur), 5, a, note, exp, fan5) })
	testing.SetRealm(testing.NewUserRealm(radio.Admin()))
	radio.SetModBot(cross(cur), robotPub)

	// The real thing: it airs with the pick, on both stations it was signed for.
	testing.SetRealm(testing.NewUserRealm(fan))
	radio.QueueWithNote(cross(cur), 5, a, note, exp, fan5)
	radio.QueueWithNote(cross(cur), 6, b, note, exp, fan6)
	check(strings.Contains(radio.ScheduleJSON(5, 3600), `"by":"`+fan.String()+`","note":"for Marie"`), "note on air 5")
	check(strings.Contains(radio.ScheduleJSON(6, 3600), `"note":"for Marie"`), "note on air 6")
	up := radio.UpNext(5)
	check(len(up) == 1 && up[0].Note == note && up[0].By == fan, "up next")
	println("ok")
}

// Output:
// ok
