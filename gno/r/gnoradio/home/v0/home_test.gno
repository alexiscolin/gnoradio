package home

import (
	"strings"
	"testing"
	"time"

	"gno.land/p/nt/testutils/v0"
	"gno.land/p/nt/urequire/v0"

	"gno.land/r/gnoradio/catalog/v0"
	"gno.land/r/gnoradio/radio/v0"
	"gno.land/r/gnoradio/tickets/v0"
)

const ipfs = "ipfs://bafybeigdyrzt5sfp7udm7hu76uh7y26nf3efuylqabf3oclgtqy55fbzdi"

var (
	alice = testutils.TestAddress("alice")
	carol = testutils.TestAddress("carol")
)

func TestPages(cur realm, t *testing.T) {
	testing.SetRealm(testing.NewUserRealm(alice))
	catalog.RegisterArtist(cross(cur), "Lea Kosmos", "Night synthwave & cassettes from Lyon.")
	for i := 0; i < 30; i++ {
		catalog.PublishTrack(cross(cur), "Neon Rivers "+itoa(i), 1+i%catalog.NumGenres, "3:30", "cc by", "none", "", ipfs, "", "", "", "", "yes")
	}
	catalog.CreateAlbum(cross(cur), 1, "First Light", "", "", 2026, "1,2,3")
	start := time.Now().Add(72 * time.Hour).UTC().Format("2006-01-02 15:04")
	tickets.CreateEvent(cross(cur), "Release Party", "La Station, Paris", "", start, "0", 100)
	testing.SetRealm(testing.NewUserRealm(carol))
	radio.Sync(cross(cur), 200)
	catalog.Like(cross(cur), 2)
	catalog.PublishPlaylist(cross(cur), "Late night", "3,2,1")
	radio.Queue(cross(cur), 0, 5)
	tickets.BuyTicket(cross(cur), 1)
	catalog.Report(cross(cur), "track", 4, "broken link")

	for _, p := range []string{"", "stations", "station/0", "station/2", "track/2", "artist/1", "artist/lea kosmos",
		"album/1", "playlist/1", "catalog", "catalog?p=2", "artists", "albums", "playlists", "concerts", "event/1",
		"ticket/1", "listener/" + carol.String(), "charts", "join", "about", "moderation", "nope", "track/999", "station/99"} {
		out := Render(p)
		urequire.True(t, len(out) > 0, p)
	}
	urequire.True(t, strings.Contains(Render(""), "ON AIR") || strings.Contains(Render(""), "data:image/svg+xml"))
	urequire.True(t, strings.Contains(Render("track/2"), "Queue on"))
	urequire.True(t, strings.Contains(Render("nope"), "Not found"))
	urequire.True(t, strings.Contains(Render(""), "Listeners' choice"))
	urequire.True(t, strings.Contains(Render("station/"+itoa(radio.NewStation)), "New this week"))
	urequire.True(t, strings.Contains(Render("station/0"), "## Top curators this week\n\n"), Render("station/0"))
	urequire.True(t, strings.Contains(Render("station/0"), "picks 1 · tips 0 · earned 0 GNOT"))
}

func TestGasHome(cur realm, t *testing.T) { Render("") }
