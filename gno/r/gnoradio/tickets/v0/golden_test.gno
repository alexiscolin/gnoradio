package tickets

import (
	"testing"

	"gno.land/p/gnoradio/svg/v0"
)

// Pins the ticket SVG byte for byte, so moving the canvas to a package changes nothing.
func TestTicketGolden(t *testing.T) {
	e := &Event{ID: 7, ArtistID: 99, Title: "Rock & Roll Night", Venue: "Bar & Grill, Lyon", Start: 1795000000, Price: 2000000, Capacity: 100}
	out := drawTicket(e, 12, false).Data() + drawTicket(e, 3, true).Data()
	e.Cancelled = true
	out += drawTicket(e, 1, false).Data()
	if svg.FNV(out) != 3078800029 || len(out) != 14486 {
		t.Fatalf("ticket art changed: %d %d", svg.FNV(out), len(out))
	}
}
