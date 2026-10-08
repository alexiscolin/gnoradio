package catalog

import (
	"testing"

	"gno.land/p/gnoradio/store/v0"
	"gno.land/p/gnoradio/text/v0"
	"gno.land/p/nt/uassert/v0"
)

// Review R28: no global cap on open reports, so spam wallets never block an
// honest reporter, and the admin closes a run of reports in one call.
func TestBulkResolveReports(cur realm, t *testing.T) {
	alice, _ := artist(cur, "alice")
	id := publish(cur, alice, "Reported")
	open := ReportCount()
	for _, w := range []string{"spam1", "spam2"} {
		testing.SetRealm(testing.NewUserRealm(who(w)))
		for i := 0; i < maxUserReports; i++ {
			Report(cross(cur), "track", id, "spam spam")
		}
	}
	testing.SetRealm(testing.NewUserRealm(who("honest")))
	Report(cross(cur), "track", id, "copyright")
	first := ReportPage(0, 1)[0] - 2*maxUserReports // newest first: the honest one, then the spam runs
	uassert.AbortsWithMessage(t, cur, "catalog: admin only", func() { ResolveReports(cross(cur), first, 10) })
	testing.SetRealm(testing.NewUserRealm(boss))
	uassert.AbortsContains(t, cur, "1 to 50", func() { ResolveReports(cross(cur), first, 51) })
	ResolveReports(cross(cur), first, 10) // the two spam runs
	uassert.Equal(t, open+1, ReportCount())
	ResolveReports(cross(cur), first, 10) // already closed: skipped
	uassert.Equal(t, open+1, ReportCount())
	testing.SetRealm(testing.NewUserRealm(who("spam1")))
	Report(cross(cur), "track", id, "spam again") // its slots came back
}

// Review R22: hiding albums and playlists is the admin's, with a reason;
// hidden ones cannot be reported, and restoring brings them back.
func TestHideAlbumAndPlaylist(cur realm, t *testing.T) {
	alice, aid := artist(cur, "alice")
	tr := publish(cur, alice, "Album Song")
	testing.SetRealm(testing.NewUserRealm(alice))
	al := CreateAlbum(cross(cur), aid, "Hide Me", "", "", 2024, text.Itoa(tr))
	pl := PublishPlaylist(cross(cur), "Hide List", text.Itoa(tr))
	uassert.AbortsWithMessage(t, cur, "catalog: admin only", func() { HideAlbum(cross(cur), al, true, "duplicate album") })
	uassert.AbortsWithMessage(t, cur, "catalog: admin only", func() { HidePlaylist(cross(cur), pl, true, "spam playlist") })
	testing.SetRealm(testing.NewUserRealm(boss))
	uassert.AbortsContains(t, cur, "reason", func() { HideAlbum(cross(cur), al, true, "no") })
	uassert.AbortsContains(t, cur, "unknown album", func() { HideAlbum(cross(cur), 9_999_999, true, "duplicate album") })
	uassert.AbortsContains(t, cur, "unknown playlist", func() { HidePlaylist(cross(cur), 9_999_999, true, "spam playlist") })
	HideAlbum(cross(cur), al, true, "duplicate album")
	HidePlaylist(cross(cur), pl, true, "spam playlist")
	a, _ := GetAlbum(al)
	p, _ := GetPlaylist(pl)
	uassert.True(t, a.Hidden && p.Hidden)
	testing.SetRealm(testing.NewUserRealm(who("reporter")))
	uassert.AbortsContains(t, cur, "unknown album", func() { Report(cross(cur), "album", al, "broken link") })
	uassert.AbortsContains(t, cur, "unknown playlist", func() { Report(cross(cur), "playlist", pl, "broken link") })
	testing.SetRealm(testing.NewUserRealm(boss))
	HideAlbum(cross(cur), al, false, "")
	HidePlaylist(cross(cur), pl, false, "")
	a, _ = GetAlbum(al)
	p, _ = GetPlaylist(pl)
	uassert.False(t, a.Hidden || p.Hidden)
}

// Review R21: a profile the moderator hides during its 72-hour claim window
// cannot be finalized.
func TestClaimOnHiddenArtist(cur realm, t *testing.T) {
	w, aid := artist(cur, "claimhidden")
	_, gen := botKey(rd())
	seed(cur, cClaims, store.Pad(aid), store.Rec(w.String(), "https://claim.example/x", text.Itoa64(now()), text.Itoa(gen)))
	testing.SetRealm(testing.NewUserRealm(boss))
	HideArtist(cross(cur), aid, true, "impersonation")
	testing.SkipHeights(claimDelay/5 + 1)
	uassert.AbortsContains(t, cur, "unknown artist", func() { FinalizeClaim(cross(cur), aid) })
	uassert.False(t, ArtistVerified(aid))
	uassert.PanicsContains(t, cur, "hidden", func() { mustClaimable(rd(), &Artist{Hidden: true}, w) })
}

// Review R57: the per-artist track and album caps hold.
func TestPerArtistCaps(cur realm, t *testing.T) {
	alice, aid := artist(cur, "capped")
	tr := publish(cur, alice, "Cap Song")
	ids := make([]int, maxPerArtist)
	for i := range ids {
		ids[i] = 2_000_000 + i
	}
	seed(cur, cAlists, store.Pad(aid), store.Rec(store.Pack(ids), store.Pack(ids)))
	testing.SetRealm(testing.NewUserRealm(alice))
	uassert.AbortsContains(t, cur, "tracks per artist limit reached", func() {
		PublishTrack(cross(cur), "One More", 2, "3:30", "cc by", "none", "", ipfs, "", "", "", "", "yes")
	})
	uassert.AbortsContains(t, cur, "albums per artist limit reached", func() {
		CreateAlbum(cross(cur), aid, "One More", "", "", 2024, text.Itoa(tr))
	})
}

// A bulk resolve of 50 reports from distinct wallets writes over 64 keys
// (the reports, the reporters, the meta record): save splits the Batches.
func TestBulkResolveManyReporters(cur realm, t *testing.T) {
	alice, _ := artist(cur, "alice")
	id := publish(cur, alice, "Reported many")
	open := ReportCount()
	for i := 0; i < 50; i++ {
		testing.SetRealm(testing.NewUserRealm(who("many")))
		Report(cross(cur), "track", id, "spam spam")
	}
	first := ReportPage(0, 1)[0] - 49
	testing.SetRealm(testing.NewUserRealm(boss))
	ResolveReports(cross(cur), first, 50)
	uassert.Equal(t, open, ReportCount())
}
