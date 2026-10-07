package home

import (
	"strings"
	"testing"

	"gno.land/p/nt/testutils/v0"
	"gno.land/p/nt/uassert/v0"
	"gno.land/r/gnoradio/catalog/v0"
)

// The catalog admin is unreachable under gno test, so artists cannot be
// verified here: render tests treat every claimed artist as verified.
func init() { tippable = func(owner address, _ bool) bool { return owner != "" } }

func TestUnverifiedHasNoTip(cur realm, t *testing.T) {
	testing.SetRealm(testing.NewUserRealm(testutils.TestAddress("seam_artist")))
	catalog.RegisterArtist(cross(cur), "Seam Artist", "")
	tr := catalog.PublishTrack(cross(cur), "Seam Song", 2, "3:30", "cc by", "none", "", ipfs, "", "", "", "", "yes")
	tippable = func(owner address, verified bool) bool { return owner != "" && verified }
	defer func() { tippable = func(owner address, _ bool) bool { return owner != "" } }()
	out := Render("track/" + itoa(tr))
	uassert.False(t, strings.Contains(out, "func=TipWithSupport"))
	uassert.True(t, strings.Contains(out, "verifies this profile"))
}
