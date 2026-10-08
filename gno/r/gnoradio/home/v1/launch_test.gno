package home

import (
	"strings"
	"testing"
	"time"

	"gno.land/p/nt/testutils/v0"
	"gno.land/p/nt/uassert/v0"

	"gno.land/p/gnoradio/text/v0"
	"gno.land/r/gnoradio/catalog/v1"
	"gno.land/r/gnoradio/radio/v1"
	"gno.land/r/gnoradio/tickets/v1"
)

// Free launch: with no treasury and no fee the pages show no support and no fee;
// with both set they come back.
func TestFeaturesFollowTreasuryAndFee(cur realm, t *testing.T) {
	seller := testutils.TestAddress("launch_seller")
	testing.SetRealm(testing.NewUserRealm(seller))
	aid := catalog.RegisterArtist(cross(cur), "Launch Seller", "")
	tr := radio.PublishTrack(cross(cur), "Launch Song", 2, "3:30", "cc by", "none", "", ipfs, "", "", "", "", "yes")
	verify(cur, aid)
	testing.SetRealm(testing.NewUserRealm(seller))
	start := time.Now().Add(72 * time.Hour).UTC().Format("2006-01-02 15:04")
	ev := tickets.CreateEvent(cross(cur), "Launch Night", "Club", "", start, "2", 50)

	check := func(on bool) {
		pages := map[string]string{"": Render(""), "track": Render("track/" + text.Itoa(tr)), "about": Render("about")}
		uassert.Equal(t, on, strings.Contains(pages[""], "Keep GnoRadio on air"))
		uassert.Equal(t, on, strings.Contains(pages[""], "func=SupportGnoRadio"))
		uassert.Equal(t, on, strings.Contains(pages["track"], "func=TipWithSupport"))
		uassert.Equal(t, on, strings.Contains(pages["track"], "10%"))
		uassert.Equal(t, on, strings.Contains(pages["about"], "fund GnoRadio"))
		uassert.Equal(t, on, strings.Contains(Render("event/"+text.Itoa(ev)), "service fee"))
	}

	check(false)

	testing.SetRealm(testing.NewUserRealm(catalog.Admin()))
	catalog.SetTreasury(cross(cur), testutils.TestAddress("launch_treasury"))
	testing.SetRealm(testing.NewUserRealm(tickets.Admin()))
	tickets.SetServiceFee(cross(cur), 500_000)
	check(true)

	tickets.SetServiceFee(cross(cur), 0)
	testing.SetRealm(testing.NewUserRealm(catalog.Admin()))
	catalog.SetTreasury(cross(cur), "")
	check(false)
}
