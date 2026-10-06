package home

import (
	"strings"
	"testing"

	"gno.land/p/nt/testutils/v0"
	"gno.land/p/nt/urequire/v0"

	"gno.land/r/gnoradio/catalog/v0"
)

// The artist page lists at most maxCovers+40 tracks, and the tip line says
// where the artist share goes when a track has collaborators.
func TestArtistPageCapAndSplitText(cur realm, t *testing.T) {
	prolific := testutils.TestAddress("prolific")
	collab := testutils.TestAddress("collab")
	testing.SetRealm(testing.NewUserRealm(prolific))
	aid := catalog.RegisterArtist(cross(cur), "Prolific", "")
	var last int
	for i := 0; i < maxCovers+45; i++ {
		last = catalog.PublishTrack(cross(cur), "Take "+itoa(i), 2, "3:30", "cc by", "none", "", ipfs, "", "", "", "", "yes")
	}
	out := Render("artist/" + itoa(aid))
	urequire.Equal(t, 40, strings.Count(out, "\n- [Take "))
	urequire.True(t, strings.Contains(Render("track/"+itoa(last)), "100% of the artist share"))

	split := catalog.PublishTrack(cross(cur), "Duet", 2, "3:30", "cc by", "none", "", ipfs, "", "", "", collab.String()+":30", "yes")
	out = Render("track/" + itoa(split))
	urequire.True(t, strings.Contains(out, "split with 1 collaborator"), out)
	urequire.False(t, strings.Contains(out, "100% of the artist share"))
}
