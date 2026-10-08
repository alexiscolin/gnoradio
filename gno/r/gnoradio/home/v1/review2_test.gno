package home

import (
	"strings"
	"testing"

	"gno.land/p/gnoradio/store/v0"
	"gno.land/p/nt/testutils/v0"
	"gno.land/p/nt/uassert/v0"
	"gno.land/p/nt/urequire/v0"

	"gno.land/p/gnoradio/text/v0"
	"gno.land/r/gnoradio/catalog/v1"
	"gno.land/r/gnoradio/data"
	"gno.land/r/gnoradio/radio/v1"
)

// M4: an upper-case address is the same wallet under another string: home
// treats it as no address, so it never shows the wallet as a stranger.
func TestUpperCaseAddress(t *testing.T) {
	fan := testutils.TestAddress("rv_fan")
	up := address(strings.ToUpper(fan.String()))
	uassert.True(t, up.IsValid())
	uassert.True(t, strings.HasPrefix(Render("listener/"+fan.String()), "# "))
	urequire.True(t, strings.Contains(Render("listener/"+up.String()), "This page does not exist"))
	uassert.False(t, strings.Contains(who(up), "listener/"))
	uassert.Equal(t, "GnoRadio (moderator)", role(up, "GnoRadio (moderator)"))
}

// L30: a nickname is easy to grind, so a nickname label carries the short
// address too.
func TestNicknameShowsShortAddress(t *testing.T) {
	fan := testutils.TestAddress("rv_nick")
	w := who(fan)
	uassert.True(t, strings.Contains(w, md(nickname(fan))), w)
	uassert.True(t, strings.Contains(w, short(fan)), w)
}

// M6 and L3: the proof host stands next to every ✓, and pending claims are
// listed on the moderation page.
func TestProofHostAndPendingClaims(cur realm, t *testing.T) {
	singer, claimer := testutils.TestAddress("rv_singer"), testutils.TestAddress("rv_claimer")
	testing.SetRealm(testing.NewUserRealm(singer))
	aid := catalog.RegisterArtist(cross(cur), "Rv Singer", "")
	tr := radio.PublishTrack(cross(cur), "Rv Song", 3, "3:30", "cc by", "none", "", ipfs, "", "", "", "", "yes")
	verify(cur, aid)
	ap := Render("artist/" + text.Itoa(aid))
	urequire.True(t, strings.Contains(ap, "Verified by the GnoRadio moderator"), ap)

	testing.SetRealm(testing.NewCodeRealm(catalogPath))
	data.Set(cross(cur), "catalog/proofs", store.Pad(aid), "https://rv-singer.example/.well-known/gnoradio.txt")
	ap = Render("artist/" + text.Itoa(aid))
	urequire.True(t, strings.Contains(ap, "Verified via **rv\\-singer\\.example**"), ap)
	urequire.True(t, strings.Contains(Render("track/"+text.Itoa(tr)), "✓ via rv\\-singer\\.example"))

	testing.SetRealm(testing.NewUserRealm(claimer))
	cid := catalog.RegisterArtist(cross(cur), "Rv Claimed", "")
	gen, _ := data.Get("catalog/config", "gen")
	if gen == "" {
		gen = "0"
	}
	testing.SetRealm(testing.NewCodeRealm(catalogPath))
	data.Set(cross(cur), "catalog/claims", store.Pad(cid), store.Rec(claimer.String(), "https://claim.example/p", "1", gen))
	mp := Render("moderation")
	urequire.True(t, strings.Contains(mp, "## Pending verifications"), mp)
	urequire.True(t, strings.Contains(mp, "Rv Claimed"), mp)
	urequire.True(t, strings.Contains(mp, "claim\\.example"), mp)
}

func TestProofHostOf(t *testing.T) {
	uassert.Equal(t, "evil.com", proofHostOf("https://evil.com?@realartist.com/x"))
	uassert.Equal(t, "evil.com", proofHostOf("https://evil.com#@realartist.com/x"))
	uassert.Equal(t, "?", proofHostOf("https://realartist.com@evil.com/x"))
}
