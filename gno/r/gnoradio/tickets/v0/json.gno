package tickets

import (
	"encoding/base64"
	"strings"

	"gno.land/r/gnoradio/catalog/v0"
)

// Read API for the home realm and the GnoRadio app. Every string emitted
// passed validText/validURL, so it holds no quotes or backslashes.

func catalogName(id int) string { return catalog.ArtistName(id) }

func q(s string) string { return `"` + s + `"` }

func boolStr(v bool) string {
	if v {
		return "true"
	}
	return "false"
}

// EventSVG returns the specimen ticket of a visible concert as a markdown
// image, or "" when the concert is not visible.
func EventSVG(id int) string {
	e := getEvent(id)
	if !visible(e) {
		return ""
	}
	return drawTicket(&e.Event, 0, false).image("ticket for " + e.Title)
}

// TicketSVG returns a ticket as a markdown image, or "" if unknown.
func TicketSVG(id int) string {
	tk := getTicket(id)
	if tk == nil {
		return ""
	}
	e := getEvent(tk.Event)
	return drawTicket(&e.Event, tk.Serial, tk.Attended).image("ticket for " + e.Title)
}

// TokenURI returns the GRC721 metadata of a ticket as a data URI, with the
// ticket artwork drawn on the fly (nothing extra is stored).
func TokenURI(tid string) string {
	tk := mustTicket(atoi(tid))
	e := getEvent(tk.Event)
	img := drawTicket(&e.Event, tk.Serial, tk.Attended).dataURI()
	meta := `{"name":` + q("GnoRadio · "+e.Title+" #"+pad3(tk.Serial)) +
		`,"description":"GnoRadio concert ticket, drawn on-chain on gno.land","image":` + q(img) +
		`,"attributes":[{"trait_type":"event","value":` + itoa(e.ID) +
		`},{"trait_type":"artist","value":` + q(artistName(e.ArtistID)) +
		`},{"trait_type":"attended","value":` + boolStr(tk.Attended) + `}]}`
	return "data:application/json;base64," + base64.StdEncoding.EncodeToString([]byte(meta))
}

func eventJSON(e Event) string {
	return `{"id":` + itoa(e.ID) + `,"artist":` + itoa(e.ArtistID) + `,"artistName":` + q(artistName(e.ArtistID)) +
		`,"title":` + q(e.Title) + `,"venue":` + q(e.Venue) + `,"link":` + q(e.Link) +
		`,"start":` + itoa64(e.Start) + `,"price":` + itoa64(e.Price) + `,"capacity":` + itoa(e.Capacity) +
		`,"sold":` + itoa(e.Sold) + `,"cancelled":` + boolStr(e.Cancelled) + `,"fee":` + itoa64(serviceFee) + `}`
}

// EventsJSON pages through visible concerts, newest first (limit <= 50).
// upcoming=true lists future, not cancelled concerts instead, soonest first.
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
		eachUpcoming(add)
	} else {
		scanned := 0
		events.ReverseIterate("", "", func(_ string, v any) bool {
			e := v.(*event)
			scanned++
			if visible(e) && add(e) {
				return true
			}
			return scanned >= 1000
		})
	}
	b.WriteString(`]}`)
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
			`,"attended":` + boolStr(tk.Attended) + `}`)
	}
	b.WriteString(`]`)
	return b.String()
}

// FeesJSON returns the ticket service fee and where it goes.
func FeesJSON() string {
	return `{"serviceFee":` + itoa64(serviceFee) + `,"treasury":` + q(catalog.Treasury().String()) + `}`
}
