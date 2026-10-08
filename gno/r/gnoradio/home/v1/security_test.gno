package home

import (
	"strings"
	"testing"

	"gno.land/p/nt/testutils/v0"
	"gno.land/p/nt/uassert/v0"
	"gno.land/p/nt/urequire/v0"

	"gno.land/p/gnoradio/text/v0"
	"gno.land/r/gnoradio/catalog/v1"
	"gno.land/r/gnoradio/radio/v1"
)

// The artist page pages its tracks (pageSize per page, covers first on page
// 1), and the tip line says where the artist share goes with collaborators.
func TestArtistPageCapAndSplitText(cur realm, t *testing.T) {
	prolific := testutils.TestAddress("prolific")
	collab := testutils.TestAddress("collab")
	testing.SetRealm(testing.NewUserRealm(prolific))
	aid := catalog.RegisterArtist(cross(cur), "Prolific", "")
	verify(cur, aid)
	testing.SetRealm(testing.NewUserRealm(prolific))
	var last int
	for i := 0; i < maxCovers+45; i++ {
		last = radio.PublishTrack(cross(cur), "Take "+text.Itoa(i), 2, "3:30", "cc by", "none", "", ipfs, "", "", "", "", "yes")
	}
	out := Render("artist/" + text.Itoa(aid))
	urequire.Equal(t, pageSize-maxCovers, strings.Count(out, "\n- [Take "))
	urequire.True(t, strings.Contains(out, "Next →"))
	urequire.Equal(t, pageSize, strings.Count(Render("artist/"+text.Itoa(aid)+"?p=2"), "\n- [Take "))
	last3 := Render("artist/" + text.Itoa(aid) + "?p=3")
	urequire.Equal(t, maxCovers+45-2*pageSize, strings.Count(last3, "\n- [Take "))
	urequire.False(t, strings.Contains(last3, "Next →"))
	urequire.True(t, strings.Contains(Render("track/"+text.Itoa(last)), "100% of the artist share"))

	split := radio.PublishTrack(cross(cur), "Duet", 2, "3:30", "cc by", "none", "", ipfs, "", "", "", collab.String()+":30", "yes")
	out = Render("track/" + text.Itoa(split))
	urequire.True(t, strings.Contains(out, "split with 1 collaborator"), out)
	urequire.False(t, strings.Contains(out, "100% of the artist share"))
}

// Tips need a profile the catalog verified: until then the track page says
// how to verify instead.
func TestUnverifiedHasNoTip(cur realm, t *testing.T) {
	testing.SetRealm(testing.NewUserRealm(testutils.TestAddress("seam_artist")))
	catalog.RegisterArtist(cross(cur), "Seam Artist", "")
	tr := radio.PublishTrack(cross(cur), "Seam Song", 2, "3:30", "cc by", "none", "", ipfs, "", "", "", "", "yes")
	out := Render("track/" + text.Itoa(tr))
	uassert.False(t, strings.Contains(out, "func=TipWithSupport"))
	uassert.True(t, strings.Contains(out, "verifies this profile"))
}
