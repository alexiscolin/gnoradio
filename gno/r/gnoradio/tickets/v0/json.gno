package tickets

import (
	"encoding/base64"
	"strconv"
	"strings"

	"gno.land/p/gnoradio/text/v0"

	"gno.land/r/gnoradio/catalog/v0"
)

// Read API for the home realm and the GnoRadio app.

// EventSVG returns the specimen ticket of a visible concert as a markdown
// image, or "" when the concert is not visible.
func EventSVG(id int) string {
	e := getEvent(id)
	if !visible(e) {
		return ""
	}
	return drawTicket(&e.Event, 0, false).Image("ticket for " + e.Title)
}

// TicketSVG returns a ticket as a markdown image, or "" if unknown.
func TicketSVG(id int) string {
	tk := getTicket(id)
	if tk == nil {
		return ""
	}
	e := shown(getEvent(tk.Event))
	return drawTicket(&e, tk.Serial, tk.Attended).Image("ticket for " + e.Title)
}

// removedTitle replaces the details of a concert hidden by moderation.
const removedTitle = "Removed by moderation"

// shown is what a ticket may display of its concert: everything while the
// concert and its artist are visible, a neutral placeholder otherwise.
func shown(e *event) Event {
	if visible(e) {
		return e.Event
	}
	out := Event{Title: removedTitle}
	if e != nil {
		out.ID, out.Start, out.Capacity, out.Cancelled = e.ID, e.Start, e.Capacity, e.Cancelled
	}
	return out
}

// TokenURI returns the GRC721 metadata of a ticket as a data URI, with the
// ticket artwork drawn on the fly (nothing extra is stored).
func TokenURI(tid string) string {
	tk := mustTicket(atoi(tid))
	e := shown(getEvent(tk.Event))
	img := drawTicket(&e, tk.Serial, tk.Attended).Data()
	meta := `{"name":` + text.Str("GnoRadio · "+e.Title+" #"+pad3(tk.Serial)) +
		`,"description":"GnoRadio concert ticket, drawn on-chain on gno.land","image":` + text.Str(img) +
		`,"attributes":[{"trait_type":"event","value":` + itoa(e.ID) +
		`},{"trait_type":"artist","value":` + text.Str(artistName(e.ArtistID)) +
		`},{"trait_type":"attended","value":` + strconv.FormatBool(tk.Attended) + `}]}`
	return "data:application/json;base64," + base64.StdEncoding.EncodeToString([]byte(meta))
}

func eventJSON(e Event) string {
	return `{"id":` + itoa(e.ID) + `,"artist":` + itoa(e.ArtistID) + `,"artistName":` + text.Str(artistName(e.ArtistID)) +
		`,"title":` + text.Str(e.Title) + `,"venue":` + text.Str(e.Venue) + `,"link":` + text.Str(e.Link) +
		`,"start":` + itoa64(e.Start) + `,"price":` + itoa64(e.Price) + `,"capacity":` + itoa(e.Capacity) +
		`,"sold":` + itoa(e.Sold) + `,"cancelled":` + strconv.FormatBool(e.Cancelled) + `,"fee":` + itoa64(serviceFee) + `}`
}

// EventsJSON pages through concerts, newest first (limit <= 50): offset and
// limit count stored concerts, hidden ones are left out of the page, and
// "next" gives the offset of the following page (0 at the end).
// upcoming=true lists future, not cancelled, visible concerts instead,
// soonest first, with offset and limit counting listed concerts ("next" is
// then a listed-concert offset, 0 when the scan ended).
func EventsJSON(offset, limit int, upcoming bool) string {
	if limit < 1 || limit > 50 {
		limit = 50
	}
	if offset < 0 {
		offset = 0
	}
	var b strings.Builder
	b.WriteString(`{"total":` + itoa(nEvents) + `,"events":[`)
	n, i := 0, 0
	add := func(e *event) bool {
		if i >= offset {
			if n > 0 {
				b.WriteString(",")
			}
			b.WriteString(eventJSON(e.Event))
			n++
		}
		i++
		return n >= limit
	}
	if upcoming {
		// One concert past a full page proves there is a next page.
		next := 0
		eachUpcoming(func(e *event) bool {
			if n >= limit {
				next = i
				return true
			}
			add(e)
			return false
		})
		b.WriteString(`],"next":` + itoa(next) + `}`)
		return b.String()
	}
	// All concerts, newest first. offset and limit count stored concerts,
	// hidden ones included, so the page is found in O(log n) instead of
	// scanning; hidden ones are left out, and "next" is the offset to ask next
	// (0 at the end).
	scanned := 0
	events.ReverseIterateByOffset(offset, limit, func(_ string, v any) bool {
		scanned++
		if e := v.(*event); visible(e) {
			if n > 0 {
				b.WriteString(",")
			}
			b.WriteString(eventJSON(e.Event))
			n++
		}
		return false
	})
	next := 0
	if offset+scanned < events.Size() {
		next = offset + scanned
	}
	b.WriteString(`],"next":` + itoa(next) + `}`)
	return b.String()
}

// TicketsOfJSON lists the tickets held by owner, newest first (<= 50).
func TicketsOfJSON(owner address) string {
	var b strings.Builder
	b.WriteString(`[`)
	for i, id := range TicketsOf(owner, 0, 50) {
		tk := getTicket(id)
		if i > 0 {
			b.WriteString(",")
		}
		b.WriteString(`{"id":` + itoa(tk.ID) + `,"event":` + itoa(tk.Event) + `,"serial":` + itoa(tk.Serial) +
			`,"attended":` + strconv.FormatBool(tk.Attended) + `}`)
	}
	b.WriteString(`]`)
	return b.String()
}

// FeesJSON returns the ticket service fee and where it goes.
func FeesJSON() string {
	return `{"serviceFee":` + itoa64(serviceFee) + `,"treasury":` + text.Str(catalog.Treasury().String()) + `}`
}
