package home

import (
	"strings"
	"testing"
	"time"

	"gno.land/p/nt/testutils/v0"
	"gno.land/p/nt/uassert/v0"
	"gno.land/p/nt/urequire/v0"

	"gno.land/p/gnoradio/text/v0"
	"gno.land/r/gnoradio/catalog/v1"
	"gno.land/r/gnoradio/radio/v1"
	"gno.land/r/gnoradio/tickets/v1"
)

func TestLicenseLinks(t *testing.T) {
	cases := map[string]string{
		"CC0-1.0":         "(https://creativecommons.org/publicdomain/zero/1.0/)",
		"CC-BY-4.0":       "[CC BY 4\\.0](https://creativecommons.org/licenses/by/4.0/)",
		"CC-BY-3.0":       "[CC BY 3\\.0](https://creativecommons.org/licenses/by/3.0/)",
		"CC-BY-SA-3.0-DE": "[CC BY\\-SA 3\\.0 DE](https://creativecommons.org/licenses/by-sa/3.0/de/)",
		"CC-BY-NC-ND-4.0": "[CC BY\\-NC\\-ND 4\\.0](https://creativecommons.org/licenses/by-nc-nd/4.0/)",
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
	aid := catalog.RegisterArtist(cross(cur), "Fee Seller", "")
	verify(cur, aid)
	testing.SetRealm(testing.NewUserRealm(seller))
	start := time.Now().Add(72 * time.Hour).UTC().Format("2006-01-02 15:04")
	id := tickets.CreateEvent(cross(cur), "Paid Night", "Club", "", start, "2", 50)
	want := text.Itoa(int(2_000_000+tickets.ServiceFee())) + "ugnot"
	out := Render("event/" + text.Itoa(id))
	urequire.True(t, strings.Contains(out, want), out)
}

// moderation?p=N pages through open reports.
func TestModerationPager(cur realm, t *testing.T) {
	artist := testutils.TestAddress("modartist")
	testing.SetRealm(testing.NewUserRealm(artist))
	catalog.RegisterArtist(cross(cur), "Mod Artist", "")
	tr := radio.PublishTrack(cross(cur), "Mod Song", 2, "3:30", "cc by", "none", "", ipfs, "", "", "", "", "yes")
	for i := 0; catalog.ReportCount() <= pageSize; i++ {
		testing.SetRealm(testing.NewUserRealm(testutils.TestAddress("reporter" + text.Itoa(i))))
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

// A pick booked for a time shows in Up next with that time.
func TestBookedUpNext(cur realm, t *testing.T) {
	testing.SetRealm(testing.NewUserRealm(testutils.TestAddress("book_singer")))
	catalog.RegisterArtist(cross(cur), "Book Singer", "")
	tr := radio.PublishTrack(cross(cur), "Book Song", 11, "3:30", "cc by", "none", "", ipfs, "", "", "", "", "yes")
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
	urequire.False(t, strings.Contains(Render("event/"+text.Itoa(id)), "example.org"))

	tr := radio.PublishTrack(cross(cur), "Link Song", 2, "3:30", "cc by", "none", "", ipfs, "", "", "", "", "yes")
	testing.SetRealm(testing.NewUserRealm(testutils.TestAddress("link_reporter")))
	catalog.Report(cross(cur), "track", tr, "title says fuck you")
	mod := Render("moderation")
	urequire.False(t, strings.Contains(mod, "fuck"), mod)
	urequire.True(t, strings.Contains(mod, "hidden: quotes a blocked word"))
}
