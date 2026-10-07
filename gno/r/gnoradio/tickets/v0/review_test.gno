package tickets

import (
	"encoding/base64"
	"strings"
	"testing"

	"gno.land/p/gnoradio/text/v0"

	"gno.land/p/nt/uassert/v0"
	"gno.land/p/nt/urequire/v0"
)

func decodeURI(t *testing.T, uri, prefix string) string {
	urequire.True(t, strings.HasPrefix(uri, prefix), uri)
	raw, err := base64.StdEncoding.DecodeString(strings.TrimPrefix(uri, prefix))
	urequire.NoError(t, err)
	return string(raw)
}

// A ticket for a concert hidden by moderation keeps no detail of it.
func TestHiddenConcertTicket(cur realm, t *testing.T) {
	reset()
	ensureArtist(cur, t)
	testing.SetRealm(testing.NewUserRealm(alice))
	id := CreateEvent(cross(cur), "Secret Gig", "Hidden Venue", "", inHours(48), "0", 10)
	testing.SetRealm(testing.NewUserRealm(carol))
	tk := BuyTicket(cross(cur), id)
	meta := decodeURI(t, TokenURI(itoa(tk)), "data:application/json;base64,")
	uassert.True(t, strings.Contains(meta, "Secret Gig"))

	testing.SetRealm(testing.NewUserRealm(bob))
	HideEvent(cross(cur), id, true, "fake concert")
	meta = decodeURI(t, TokenURI(itoa(tk)), "data:application/json;base64,")
	uassert.False(t, strings.Contains(meta, "Secret Gig"), meta)
	uassert.False(t, strings.Contains(meta, "Tickets Alice"), meta)
	uassert.True(t, strings.Contains(meta, removedTitle))
	img := TicketSVG(tk)
	svg := decodeURI(t, img[strings.Index(img, "(")+1:len(img)-1], "data:image/svg+xml;base64,")
	uassert.False(t, strings.Contains(svg, "Hidden Venue"))
	uassert.False(t, strings.Contains(svg, "Secret Gig"))
}

// Check-in refuses a cancelled concert; & is allowed in concert text.
func TestCheckInCancelledAndAmpersand(cur realm, t *testing.T) {
	reset()
	ensureArtist(cur, t)
	testing.SetRealm(testing.NewUserRealm(alice))
	id := CreateEvent(cross(cur), "Simon & Friends", "Bar & Club", "", inHours(6), "0", 10)
	uassert.True(t, strings.Contains(EventsJSON(0, 10, true), `"title":"Simon & Friends"`))
	testing.SetRealm(testing.NewUserRealm(carol))
	tk := BuyTicket(cross(cur), id)
	testing.SetRealm(testing.NewUserRealm(alice))
	CancelEvent(cross(cur), id)
	uassert.AbortsContains(t, cur, "cancelled", func() { CheckIn(cross(cur), tk) })
}

func TestTicketsJSONEscaping(t *testing.T) {
	uassert.False(t, text.Valid(`x"y`, 0, 100))
	uassert.False(t, text.Valid(`x\z`, 0, 100))
}

func TestRenderPointsHome(t *testing.T) {
	uassert.True(t, strings.Contains(Render(""), "(/r/gnoradio/home/v0)"))
}
