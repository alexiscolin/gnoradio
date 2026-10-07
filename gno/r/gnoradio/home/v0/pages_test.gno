package home

import (
	"strings"
	"testing"
	"time"

	"gno.land/p/nt/testutils/v0"
	"gno.land/p/nt/uassert/v0"
	"gno.land/p/nt/urequire/v0"

	"gno.land/r/gnoradio/catalog/v0"
	"gno.land/r/gnoradio/tickets/v0"
)

// Bare breadcrumb segments open their list page instead of "Not found".
func TestBreadcrumbAliases(t *testing.T) {
	cases := map[string]string{
		"track": "# Catalog", "artist": "# Artists", "album": "# Albums", "playlist": "# Playlists",
		"station": "# Stations", "event": "# Concerts", "ticket": "# Concerts", "listener": "# Charts",
	}
	for p, want := range cases {
		uassert.True(t, strings.HasPrefix(Render(p), want), p)
	}
	uassert.Equal(t, 6, strings.Count(nav(), "]("))
}

func TestGnowebPages(cur realm, t *testing.T) {
	fan := testutils.TestAddress("gw_fan")
	singer := testutils.TestAddress("gw_singer")
	testing.SetRealm(testing.NewUserRealm(singer))
	aid := catalog.RegisterArtist(cross(cur), "Gw Singer", "")
	tr := catalog.PublishTrack(cross(cur), "Gw Song", 7, "3:30", "cc by", "none", "", ipfs, "", "", "", "", "yes")
	al := catalog.CreateAlbum(cross(cur), aid, "Gw Album", "", "", 2026, itoa(tr))
	testing.SetRealm(testing.NewUserRealm(fan))
	catalog.Like(cross(cur), tr)
	catalog.Follow(cross(cur), aid)

	// Genre browsing, with artist names as links.
	g7 := Render("catalog?g=7")
	urequire.True(t, strings.Contains(g7, "# Catalog · "+catalog.GenreName(7)), g7)
	urequire.True(t, strings.Contains(g7, "Gw Song"))
	urequire.True(t, strings.Contains(g7, "[Gw Singer]("+page("artist/"+itoa(aid))+")"))
	urequire.False(t, strings.Contains(Render("catalog?g=8"), "Gw Song"))
	uassert.True(t, strings.Contains(genreBrowse(7), page("catalog?g=7")))

	// Track page: undo links, tip with support, fingerprints.
	tp := Render("track/" + itoa(tr))
	urequire.True(t, strings.Contains(tp, "func=Unlike"), tp)
	urequire.True(t, strings.Contains(tp, "func=TipWithSupport"))
	urequire.True(t, strings.Contains(tp, "5500000ugnot"))
	urequire.True(t, strings.Contains(tp, "**Fingerprints.**"))
	urequire.True(t, strings.Contains(Render("artist/"+itoa(aid)), "func=Unfollow"))
	urequire.True(t, strings.Contains(Render("album/"+itoa(al)), "kind=album"))

	// Listener page: likes, follows and the renamed badges section.
	lp := Render("listener/" + fan.String())
	urequire.True(t, strings.Contains(lp, "## Likes"), lp)
	urequire.True(t, strings.Contains(lp, "## Follows"))
	urequire.True(t, strings.Contains(lp, "## Early-listener badges"))
	urequire.True(t, strings.Contains(lp, "Gw Song"))
	urequire.False(t, strings.Contains(lp, "Recent likes"))

	// Home: support block and activity feed; About: $source links.
	home := Render("")
	urequire.True(t, strings.Contains(home, "Keep GnoRadio on air"), home)
	urequire.True(t, strings.Contains(home, "func=SupportGnoRadio"))
	urequire.True(t, strings.Contains(home, "## Recent activity"))
	urequire.True(t, strings.Contains(home, "liked [Gw Song]"))
	about := Render("about")
	urequire.True(t, strings.Contains(about, "$source&file=social.gno"), about)
	urequire.False(t, strings.Contains(about, "$help"))

	// Verification happens in the app (catalog/verify.gno), never through a report.
	uassert.False(t, strings.Contains(verifyLink(3), "func=Report"))
	uassert.True(t, strings.Contains(strings.ToLower(verifyLink(3)), "verify it"))
	urequire.True(t, strings.Contains(about, abuseEmail))

	// A hidden track's page says who hid it.
	testing.SetRealm(testing.NewUserRealm(singer))
	catalog.HideOwn(cross(cur), "track", tr, true)
	hp := Render("track/" + itoa(tr))
	uassert.True(t, strings.Contains(hp, "Hidden by the artist"), hp)
	catalog.HideOwn(cross(cur), "track", tr, false)
}

// Past concerts are listed under the upcoming ones.
func TestPastConcerts(cur realm, t *testing.T) {
	host := testutils.TestAddress("gw_host")
	testing.SetRealm(testing.NewUserRealm(host))
	catalog.RegisterArtist(cross(cur), "Gw Host", "")
	start := time.Now().Add(2 * time.Hour).UTC().Format("2006-01-02 15:04")
	tickets.CreateEvent(cross(cur), "Gw Past Show", "Club", "", start, "0", 10)
	urequire.False(t, strings.Contains(strings.SplitN(Render("concerts"), "## Past concerts", 2)[1], "Gw Past Show"))
	testing.SkipHeights(3 * 720) // three hours later
	past := strings.SplitN(Render("concerts"), "## Past concerts", 2)[1]
	urequire.True(t, strings.Contains(past, "Gw Past Show"), past)
}

// The app link is admin-set, validated, and drives "Open in the app" links.
func TestAppURL(cur realm, t *testing.T) {
	uassert.True(t, validAppURL("https://gnoradio.netlify.app"))
	uassert.True(t, validAppURL("https://app.example.org/radio/"))
	uassert.False(t, validAppURL("http://gnoradio.netlify.app"))
	uassert.False(t, validAppURL("https://x.org/?a=1"))
	uassert.False(t, validAppURL("https://x.org/\"onload"))
	uassert.False(t, validAppURL("https://"+strings.Repeat("a", 100)+".org"))

	testing.SetRealm(testing.NewUserRealm(testutils.TestAddress("gw_stranger")))
	uassert.AbortsWithMessage(t, cur, "home: catalog admin only", func() { SetAppURL(cross(cur), "https://evil.example") })

	uassert.Equal(t, "", inApp("track/1", "Open"))
	appURL = "https://gnoradio.netlify.app"
	defer func() { appURL = "" }()
	uassert.Equal(t, "[Open](https://gnoradio.netlify.app/track/1)", inApp("track/1", "Open"))
	urequire.True(t, strings.Contains(Render("track/1"), "https://gnoradio.netlify.app/track/1"))
	urequire.True(t, strings.Contains(Render(""), "Open the GnoRadio app"))
}

func TestEmptyStates(t *testing.T) {
	if len(catalog.TopFans()) == 0 {
		uassert.True(t, strings.Contains(Render("charts"), "No supporter yet"))
	}
	if catalog.ReportCount() == 0 {
		uassert.True(t, strings.Contains(Render("moderation"), "No open report"))
	}
}
