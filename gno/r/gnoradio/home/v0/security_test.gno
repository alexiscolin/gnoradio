package home

import (
	"strings"
	"testing"

	"gno.land/p/nt/testutils/v0"
	"gno.land/p/nt/urequire/v0"

	"gno.land/r/gnoradio/catalog/v0"
)

// The artist page pages its tracks (pageSize per page, covers first on page
// 1), and the tip line says where the artist share goes with collaborators.
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
	urequire.Equal(t, pageSize-maxCovers, strings.Count(out, "\n- [Take "))
	urequire.True(t, strings.Contains(out, "Next →"))
	urequire.Equal(t, pageSize, strings.Count(Render("artist/"+itoa(aid)+"?p=2"), "\n- [Take "))
	last3 := Render("artist/" + itoa(aid) + "?p=3")
	urequire.Equal(t, maxCovers+45-2*pageSize, strings.Count(last3, "\n- [Take "))
	urequire.False(t, strings.Contains(last3, "Next →"))
	urequire.True(t, strings.Contains(Render("track/"+itoa(last)), "100% of the artist share"))

	split := catalog.PublishTrack(cross(cur), "Duet", 2, "3:30", "cc by", "none", "", ipfs, "", "", "", collab.String()+":30", "yes")
	out = Render("track/" + itoa(split))
	urequire.True(t, strings.Contains(out, "split with 1 collaborator"), out)
	urequire.False(t, strings.Contains(out, "100% of the artist share"))
}
