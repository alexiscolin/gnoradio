package home

import (
	"strings"
	"testing"
	"time"

	"gno.land/p/nt/testutils/v0"
	"gno.land/p/nt/uassert/v0"
	"gno.land/p/nt/urequire/v0"

	"gno.land/r/gnoradio/catalog/v0"
	"gno.land/r/gnoradio/radio/v0"
	"gno.land/r/gnoradio/tickets/v0"
)

func TestLicenseLinks(t *testing.T) {
	cases := map[string]string{
		"CC0-1.0":         "(https://creativecommons.org/publicdomain/zero/1.0/)",
		"CC-BY-4.0":       "[CC BY 4.0](https://creativecommons.org/licenses/by/4.0/)",
		"CC-BY-3.0":       "[CC BY 3.0](https://creativecommons.org/licenses/by/3.0/)",
		"CC-BY-SA-3.0-DE": "[CC BY-SA 3.0 DE](https://creativecommons.org/licenses/by-sa/3.0/de/)",
		"CC-BY-NC-ND-4.0": "[CC BY-NC-ND 4.0](https://creativecommons.org/licenses/by-nc-nd/4.0/)",
		"Audius-OML":      "[Audius Open Music License]",
	}
	for in, want := range cases {
		uassert.True(t, strings.Contains(licenseLink(in), want), in+" → "+licenseLink(in))
	}
	uassert.Equal(t, "All rights reserved", licenseLink("ALL-RIGHTS-RESERVED"))
}

// The buy link attaches the price plus the service fee BuyTicket requires.
func TestBuyLinkCarriesFee(cur realm, t *testing.T) {
	seller := testutils.TestAddress("feeseller")
	testing.SetRealm(testing.NewUserRealm(seller))
	catalog.RegisterArtist(cross(cur), "Fee Seller", "")
	start := time.Now().Add(72 * time.Hour).UTC().Format("2006-01-02 15:04")
	id := tickets.CreateEvent(cross(cur), "Paid Night", "Club", "", start, "2", 50)
	want := itoa(int(2_000_000+tickets.ServiceFee())) + "ugnot"
	out := Render("event/" + itoa(id))
	urequire.True(t, strings.Contains(out, want), out)
}

// moderation?p=N pages through open reports.
func TestModerationPager(cur realm, t *testing.T) {
	artist := testutils.TestAddress("modartist")
	testing.SetRealm(testing.NewUserRealm(artist))
	catalog.RegisterArtist(cross(cur), "Mod Artist", "")
	tr := catalog.PublishTrack(cross(cur), "Mod Song", 2, "3:30", "cc by", "none", "", ipfs, "", "", "", "", "yes")
	for i := 0; catalog.ReportCount() <= pageSize; i++ {
		testing.SetRealm(testing.NewUserRealm(testutils.TestAddress("reporter" + itoa(i))))
		catalog.Report(cross(cur), "track", tr, "broken link")
	}
	one := Render("moderation")
	urequire.True(t, strings.Contains(one, "Next →"), one)
	two := Render("moderation?p=2")
	urequire.True(t, strings.Contains(two, "← Previous"), two)
	urequire.True(t, one != two)
}

func playing(st, track int) bool {
	id, _, _ := radio.NowPlaying(st)
	return id == track
}

// A loop of an hour or more shows hours, not thousands of minutes.
func TestSpan(t *testing.T) {
	uassert.Equal(t, "59:59", span(3599))
	uassert.Equal(t, "1 h 00", span(3600))
	uassert.Equal(t, "291 h 12", span(291*3600+12*60+35))
}

// The dedication of the programmed track on air shows on the on-air line.
func TestOnAirDedication(cur realm, t *testing.T) {
	testing.SetRealm(testing.NewUserRealm(testutils.TestAddress("note_singer")))
	catalog.RegisterArtist(cross(cur), "Note Singer", "")
	tr := catalog.PublishTrack(cross(cur), "Note Song", 9, "3:30", "cc by", "none", "", ipfs, "", "", "", "", "yes")
	testing.SetRealm(testing.NewUserRealm(testutils.TestAddress("note_fan")))
	radio.Sync(cross(cur), 200)
	radio.Queue(cross(cur), 9, tr)
	onAirNote = func(int) string { return "for Marie, happy birthday!" }
	for !playing(9, tr) {
		testing.SkipHeights(12) // a minute
	}
	out := Render("station/9")
	on := strings.SplitN(out, "## Up next", 2)[0]
	onAirNote = radio.OnAirNote
	urequire.True(t, strings.Contains(on, "queued by a listener · ♥ *"+md("for Marie, happy birthday!")+"*"), out)
}

// A pick booked for a time shows in Up next with that time.
func TestBookedUpNext(cur realm, t *testing.T) {
	testing.SetRealm(testing.NewUserRealm(testutils.TestAddress("book_singer")))
	catalog.RegisterArtist(cross(cur), "Book Singer", "")
	tr := catalog.PublishTrack(cross(cur), "Book Song", 11, "3:30", "cc by", "none", "", ipfs, "", "", "", "", "yes")
	testing.SetRealm(testing.NewUserRealm(testutils.TestAddress("book_fan")))
	radio.Sync(cross(cur), 200)
	at := time.Now().Unix() + 3600
	radio.QueueAt(cross(cur), 11, tr, at)
	start := radio.UpNext(11)[0].Start
	out := Render("station/11")
	urequire.True(t, strings.Contains(out, hour(start)+" UTC · [Book Song]"), out)
	urequire.True(t, strings.Contains(out, "· booked by "), out)
}

// Unverified profiles get no event link (phishing); report reasons quoting a
// blocked word are masked on /moderation.
func TestEventLinkAndReasonMask(cur realm, t *testing.T) {
	testing.SetRealm(testing.NewUserRealm(testutils.TestAddress("link_host")))
	catalog.RegisterArtist(cross(cur), "Link Host", "")
	start := time.Now().Add(72 * time.Hour).UTC().Format("2006-01-02 15:04")
	id := tickets.CreateEvent(cross(cur), "Link Night", "Club", "https://example.org/wallet", start, "0", 10)
	urequire.False(t, strings.Contains(Render("event/"+itoa(id)), "example.org"))

	tr := catalog.PublishTrack(cross(cur), "Link Song", 2, "3:30", "cc by", "none", "", ipfs, "", "", "", "", "yes")
	testing.SetRealm(testing.NewUserRealm(testutils.TestAddress("link_reporter")))
	catalog.Report(cross(cur), "track", tr, "title says fuck you")
	mod := Render("moderation")
	urequire.False(t, strings.Contains(mod, "fuck"), mod)
	urequire.True(t, strings.Contains(mod, "hidden: quotes a blocked word"))
}
