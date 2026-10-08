// PKGPATH: gno.land/r/test/homenote
package homenote

// The dedication of the pick on air shows on the on-air line and in Up next,
// through the radio's real flow: the moderation robot's certificate for fan,
// station 5, "for Marie", expiring at t0+600 (radio/v1's
// z_note_cert_filetest vector; a filetest's clock starts at t0).

import (
	"strings"
	"testing"

	"gno.land/p/nt/testutils/v0"
	catalog "gno.land/r/gnoradio/catalog/v1"
	home "gno.land/r/gnoradio/home/v1"
	radio "gno.land/r/gnoradio/radio/v1"
)

const (
	robotPub = "ea4a6c63e29c520abef5507b132ec5f9954776aebebe7b92421eea691446d22c"
	fan5     = "0d26fdcb5788bbc297200808a556cf82d5055af7ebff1168f0d63ba7dd223dcca74330af10cd777401dec5320ba8752afc88385dd6b301085a942738ebe02506"
	t0       = int64(1234567890)
	ipfs     = "ipfs://bafybeigdyrzt5sfp7udm7hu76uh7y26nf3efuylqabf3oclgtqy55fbzdi"
)

func main(cur realm) {
	testing.SetRealm(testing.NewUserRealm(testutils.TestAddress("artist")))
	catalog.RegisterArtist(cross(cur), "Note Singer", "")
	a := radio.PublishTrack(cross(cur), "Note Song", 5, "3:00", "cc by", "none", "", ipfs, "", "", "", "", "yes")
	radio.Sync(cross(cur), 10)
	testing.SetRealm(testing.NewUserRealm(radio.Admin()))
	radio.SetModBot(cross(cur), robotPub)
	testing.SetRealm(testing.NewUserRealm(testutils.TestAddress("fan")))
	radio.QueueWithNote(cross(cur), 5, a, "for Marie", t0+600, fan5)

	next := strings.SplitN(home.Render("station/5"), "## Up next", 2)[1]
	println(strings.Contains(next, "[Note Song]") && strings.Contains(next, "· ♥ *for Marie*"))
	for i := 0; i < 100; i++ {
		if id, _, queued := radio.NowPlaying(5); id == a && queued {
			break
		}
		testing.SkipHeights(12) // a minute
	}
	on := strings.SplitN(home.Render("station/5"), "## Up next", 2)[0]
	println(strings.Contains(on, "queued by a listener · ♥ *for Marie*"))
}

// Output:
// true
// true
