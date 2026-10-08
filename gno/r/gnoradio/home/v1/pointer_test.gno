package home

import (
	"strings"
	"testing"

	"gno.land/p/nt/testutils/v0"
	"gno.land/p/nt/urequire/v0"

	"gno.land/p/gnoradio/text/v0"
	"gno.land/r/gnoradio/catalog/v1"
	"gno.land/r/gnoradio/radio/v1"
)

// Audius and Jamendo pointers render with their platform label, an empty
// title falls back to "<Platform> track", and an unclaimed one has no tip link.
func TestPointerPages(cur realm, t *testing.T) {
	for _, c := range []struct{ kind, label, src, audio, owner string }{
		{catalog.OriginAudius, "Audius", "audius-user:hp1", "audius:hp1t", "Xq"},
		{catalog.OriginJamendo, "Jamendo", "jamendo-artist:777", "jamendo:777", "Zk"},
	} {
		testing.SetRealm(testing.NewUserRealm(catalog.Admin()))
		aid := catalog.CreateArtist(cross(cur), c.kind, "", "", c.src)
		tid := radio.ImportTrack(cross(cur), aid, "", 1, "3:41", "CC-BY-3.0", "", c.audio, "", "", "", "", "")
		tp, ap := "track/"+text.Itoa(tid), "artist/"+text.Itoa(aid)

		out := Render(tp)
		urequire.True(t, strings.Contains(out, "Read live from "+c.label), out)
		urequire.True(t, strings.Contains(out, c.label+" track"), out)
		urequire.False(t, strings.Contains(out, "Tip:"), out)
		out = Render(ap)
		urequire.True(t, strings.Contains(out, "Read live from "+c.label), out)
		urequire.True(t, strings.Contains(out, c.label+" artist"), out)
		urequire.False(t, strings.Contains(out, "Tip:"), out)

		// claimed: the owner names the artist and the track
		owner := testutils.TestAddress("owner" + c.label)
		catalog.AssignArtist(cross(cur), aid, owner)
		testing.SetRealm(testing.NewUserRealm(owner))
		catalog.RegisterArtist(cross(cur), "Pointer Owner "+c.owner, "A bio.")
		radio.EditTrack(cross(cur), tid, "Named Song", 1, "3:41", "", c.audio, "", "", "")
		out = Render(tp)
		urequire.True(t, strings.Contains(out, "Named Song") && strings.Contains(out, "Read live from "+c.label), out)
		out = Render(ap)
		urequire.True(t, strings.Contains(out, "Pointer Owner") && strings.Contains(out, "Wallet:"), out)
	}
}
