package home

import (
	"strings"
	"testing"
	"time"

	"gno.land/p/nt/markdown/sanitize/v0"
	"gno.land/p/nt/testutils/v0"
	"gno.land/p/nt/uassert/v0"
	"gno.land/p/nt/urequire/v0"

	"gno.land/p/gnoradio/text/v0"
	"gno.land/r/gnoradio/catalog/v1"
	"gno.land/r/gnoradio/radio/v1"
	"gno.land/r/gnoradio/tickets/v1"
)

// Same names as the app (app/src/lib/nickname.ts) for the same addresses.
func TestNicknameMatchesApp(t *testing.T) {
	uassert.Equal(t, "Indigo Beat 90", nickname("g1jg8mtutu9khhfwc4nxmuhcpftf0pajdhfvsqf5"))
	uassert.Equal(t, "Ochre Dial 6D", nickname("g1hplnue27uazg4pa7vfhzga64na9skvglqatedj"))
	uassert.Equal(t, "Amber Cassette 77", nickname("g1u7y667z64x2h7vc6fmpcprgey4ck233jaww9zq"))
	uassert.Equal(t, "1 track", plural(1, "track"))
	uassert.Equal(t, "0 tracks", plural(0, "track"))
}

// No path panics, echoes raw input or shows another page's content by accident.
func TestHostilePaths(t *testing.T) {
	for _, p := range []string{
		"track/-1", "track/99999999999999999999", "artist/<script>alert(1)</script>", "artist/[x](javascript:y)",
		"listener/notanaddress", "listener/g1<b>", "station/-1", "station/99", "station/1e3", "catalog?p=-5&g=999",
		"catalog?p=99999999999999&g=-1", "event/0", "ticket/-3", "album/x", "playlist/%00", "a/b/c", "moderation?p=abc",
		"??", "/", "artist/", "concerts?p=0", "join?x=<img>",
	} {
		out := Render(p)
		urequire.True(t, len(out) > 0, p)
		uassert.False(t, strings.Contains(out, "<script"), p)
		uassert.False(t, strings.Contains(out, "<img"), p)
		uassert.False(t, strings.Contains(out, "javascript:"), p)
	}
}

// Hidden content says why instead of "does not exist"; a cancelled free
// concert never talks about payments; tickets and lists carry their state.
func TestRemovedAndCancelled(cur realm, t *testing.T) {
	singer := testutils.TestAddress("rm_singer")
	fan := testutils.TestAddress("rm_fan")
	testing.SetRealm(testing.NewUserRealm(singer))
	aid := catalog.RegisterArtist(cross(cur), "Rm Singer", "")
	tr := radio.PublishTrack(cross(cur), "Rm Song", 3, "3:30", "cc by", "none", "", ipfs, "", "", "", "", "yes")
	al := catalog.CreateAlbum(cross(cur), aid, "Rm Album", "", "", 2026, text.Itoa(tr))
	start := time.Now().Add(72 * time.Hour).UTC().Format("2006-01-02 15:04")
	ev := tickets.CreateEvent(cross(cur), "Rm Night", "Club", "", start, "0", 10)
	testing.SetRealm(testing.NewUserRealm(fan))
	tickets.BuyTicket(cross(cur), ev)
	testing.SetRealm(testing.NewUserRealm(singer))
	tickets.CancelEvent(cross(cur), ev)

	out := Render("event/" + text.Itoa(ev))
	urequire.True(t, strings.Contains(out, "This free concert will not take place"), out)
	uassert.False(t, strings.Contains(out, "refund"))
	urequire.True(t, strings.Contains(strings.SplitN(Render("concerts"), "## Cancelled", 2)[1], "Rm Night"))
	uassert.True(t, strings.Contains(Render("listener/"+fan.String()), "Rm Night #1](/r/gnoradio/home/v1:ticket/"))
	uassert.True(t, strings.Contains(Render("listener/"+fan.String()), "· **cancelled**"))
	uassert.True(t, strings.Contains(Render("artist/"+text.Itoa(aid)), "Rm Night](/r/gnoradio/home/v1:event/"+text.Itoa(ev)+") · Club · **cancelled**"))

	catalog.HideOwn(cross(cur), "album", al, true)
	out = Render("album/" + text.Itoa(al))
	urequire.True(t, strings.Contains(out, "# Removed"), out)
	uassert.True(t, strings.Contains(out, "Hidden by the artist"))
	uassert.False(t, strings.Contains(out, "does not exist"))
	catalog.HideOwn(cross(cur), "album", al, false)
	uassert.Equal(t, "Removed · spam", removedNote("Removed by moderation: spam"))
}

// The feed merges the radio's picks with the catalog's actions.
func TestFeedMergesRadio(cur realm, t *testing.T) {
	testing.SetRealm(testing.NewUserRealm(testutils.TestAddress("feed_singer")))
	catalog.RegisterArtist(cross(cur), "Feed Singer", "")
	tr := radio.PublishTrack(cross(cur), "Feed Song", 4, "3:30", "cc by", "none", "", ipfs, "", "", "", "", "yes")
	testing.SetRealm(testing.NewUserRealm(testutils.TestAddress("feed_fan")))
	radio.Sync(cross(cur), 200)
	testing.SkipHeights(1)
	radio.Queue(cross(cur), 4, tr)
	feed := activityFeed(8)
	urequire.True(t, strings.Contains(feed, "picked [Feed Song]("+page("track/"+text.Itoa(tr))+") on [Techno]"), feed)
	uassert.True(t, strings.Index(feed, "picked [Feed Song]") < strings.Index(feed, "published [Feed Song]"), feed)
}

// The track page shows one primary action line, folds the rest, books a
// time and shows the promo share; the on-air block tips through the radio.
func TestTrackActionsAndTipOnAir(cur realm, t *testing.T) {
	singer := testutils.TestAddress("act_singer")
	testing.SetRealm(testing.NewUserRealm(singer))
	aid := catalog.RegisterArtist(cross(cur), "Act Singer", "")
	tr := radio.PublishTrack(cross(cur), "Act Song", 5, "3:30", "cc by", "none", "", ipfs, "", "", "", "", "yes")
	verify(cur, aid)
	uassert.False(t, strings.Contains(Render("track/"+text.Itoa(tr)), "Promo share:")) // opt-in: none until set
	testing.SetRealm(testing.NewUserRealm(singer))
	catalog.SetPromoShare(cross(cur), 5)
	out := Render("track/" + text.Itoa(tr))
	urequire.True(t, strings.Contains(out, "**[▶ Listen]("), out)
	uassert.True(t, strings.Contains(out, "> [!NOTE]- More actions and proof"))
	uassert.True(t, strings.Contains(out, "func=QueueAt"))
	uassert.True(t, strings.Contains(out, "Promo share: **5%**"))
	uassert.True(t, strings.Contains(onAir(radio.MainStation)+onAir(5), "func=TipOnAir") || !playing(5, tr))

	uassert.Equal(t, page("track/7"), listenURL(7, "audius:123", "", 30))
	uassert.Equal(t, "https://x.org/a.mp3#t=5", listenURL(1, "https://x.org/a.mp3#t=5", "", 30))
	// Records a later release might write are checked again here.
	uassert.Equal(t, page("track/3"), listenURL(3, "javascript:alert(1)", "", 0))
	uassert.Equal(t, "", sourceLink("Source", "data:text/html,x"))
	uassert.Equal(t, "CC\\-BY\\-4\\.0\\)\\[x\\]", licenseLink("CC-BY-4.0)[x]"))
	uassert.Equal(t, md(nickname("x)[y](z")), who("x)[y](z"))
	uassert.Equal(t, "GnoRadio (moderator)", role("", "GnoRadio (moderator)"))
	uassert.Equal(t, "Audio ``a`b``", "Audio "+sanitize.InlineCode("a`b"))
}

// The notice path needs no email: the on-chain Report, plus an optional
// contact line only the catalog admin sets.
func TestNoticeContact(cur realm, t *testing.T) {
	uassert.False(t, strings.Contains(noticeBlock(), "Contact:"))
	uassert.True(t, strings.Contains(noticeBlock(), "func=Report"))
	testing.SetRealm(testing.NewUserRealm(testutils.TestAddress("gw_stranger")))
	uassert.AbortsWithMessage(t, cur, "home: catalog admin only", func() { SetContact(cross(cur), "x") })
	testing.SetRealm(testing.NewUserRealm(catalog.Admin()))
	uassert.AbortsWithMessage(t, cur, "home: the contact is one line of at most 120 characters", func() { SetContact(cross(cur), "a\nb") })
	SetContact(cross(cur), "  [form](https://evil.example)  ")
	uassert.True(t, strings.Contains(noticeBlock(), "Contact: \\[form\\]"), noticeBlock())
	testing.SetRealm(testing.NewUserRealm(catalog.Admin()))
	SetContact(cross(cur), "")
	uassert.False(t, strings.Contains(noticeBlock(), "Contact:"))
}

// Every main path renders on a bigger catalog; gno test prints its gas.
func TestGasSeeded(cur realm, t *testing.T) {
	for a := 0; a < 6; a++ {
		testing.SetRealm(testing.NewUserRealm(testutils.TestAddress("gas_artist" + text.Itoa(a))))
		catalog.RegisterArtist(cross(cur), "Gas Artist "+text.Itoa(a), "")
		for i := 0; i < 30; i++ {
			radio.PublishTrack(cross(cur), "Gas "+text.Itoa(a)+" "+text.Itoa(i), 1+i%catalog.NumGenres, "3:30", "cc by", "none", "", ipfs, "", "", "", "", "yes")
		}
	}
	fan := testutils.TestAddress("gas_fan")
	testing.SetRealm(testing.NewUserRealm(fan))
	radio.Sync(cross(cur), 200)
	for i := 1; i <= 40; i++ {
		catalog.Like(cross(cur), catalog.TrackCount()-i)
	}
	for _, p := range []string{"", "stations", "station/0", "catalog", "artist/" + text.Itoa(catalog.ArtistCount()), "track/1", "concerts", "listener/" + fan.String(), "join"} {
		urequire.True(t, len(Render(p)) > 0, p)
	}
}

// The pick rules come from radio itself: a wrong getter shows "0 minutes to 0 hours".
func TestPickRulesFromRadio(t *testing.T) {
	out := Render("stations")
	uassert.True(t, strings.Contains(out, "booked 15 minutes to 24 hours ahead, 4 booked picks"), out)
	uassert.True(t, strings.Contains(out, "per station per hour (UTC) and 15 of the 30 waiting at most"), out)
	uassert.True(t, strings.Contains(out, "within 3 hours"), out)
}
