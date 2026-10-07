package tickets

import (
	"gno.land/p/gnoradio/svg/v0"
	"gno.land/p/gnoradio/text/v0"
	"gno.land/r/gnoradio/catalog/v0"
)

// Tickets are drawn on-chain as SVG in the GnoRadio sober style: white,
// black and greys with a single red accent. The perforation is cut out with a
// mask so it reads as holes on any page background. Text is escaped by svg.Text.

const (
	ink    = "#0d0d0d"
	paper  = "#fafaf8"
	grey   = "#9a9a96"
	accent = "#e5432f"
)

func newCanvas(w, h int) *svg.Canvas {
	return svg.New(w, h, `text{font-family:system-ui,-apple-system,'Segoe UI',Roboto,Helvetica,Arial,sans-serif;font-weight:600}.m{font-weight:500}.l{font-weight:600;letter-spacing:.08em}.n{font-family:ui-monospace,Menlo,monospace;font-weight:500}`)
}

func drawText(c *svg.Canvas, x, y int, s, fill string, size int, anchor, class string) {
	attrs := ` text-anchor="` + anchor + `"`
	if class != "" {
		attrs += ` class="` + class + `"`
	}
	c.Text(x, y, s, fill, size, attrs)
}

// drawTicket draws a ticket; serial 0 is the specimen shown before purchase.
func drawTicket(e *Event, serial int, attended bool) *svg.Canvas {
	c := newCanvas(640, 250)
	// Black ticket with perforation and side notches cut out.
	c.Raw(`<mask id="h"><rect width="640" height="250" fill="#fff"/>`)
	for y := 18; y < 250; y += 16 {
		c.Circle(470, y, 3, "#000")
	}
	c.Circle(470, 0, 14, "#000")
	c.Circle(470, 250, 14, "#000")
	c.Raw(`</mask><g mask="url(#h)">`)
	c.Rect(0, 0, 640, 250, 24, ink, "")
	c.Raw(`</g>`)

	drawText(c, 30, 44, "GNORADIO · ADMIT ONE", grey, 12, "start", "l")
	drawText(c, 30, 96, svg.Clip(e.Title, 24), paper, 32, "start", "")
	drawText(c, 30, 128, svg.Clip(artistName(e.ArtistID), 34), grey, 18, "start", "m")
	drawText(c, 30, 182, svg.Clip(e.Venue, 34), paper, 15, "start", "m")
	drawText(c, 30, 206, date(e.Start), paper, 15, "start", "m")
	price := "FREE"
	if e.Price > 0 {
		price = text.GNOT(e.Price)
	}
	drawText(c, 440, 206, price, grey, 14, "end", "l")

	// Stub: serial, barcode, red dot.
	num := "SPECIMEN"
	if serial > 0 {
		num = "#" + pad3(serial) + "/" + itoa(e.Capacity)
	}
	drawText(c, 555, 54, num, paper, 16, "middle", "n")
	h := svg.FNV("event" + itoa(e.ID) + e.Title)
	for i := 0; i < 22; i++ {
		h ^= uint32(i + 1)
		h *= 16777619
		c.Rect(502+i*5, 80, 1+int(h>>24)%3, 80, 0, paper, "")
	}
	c.Circle(555, 200, 14, accent)

	if e.Cancelled {
		stamp(c, "CANCELLED", accent)
	} else if attended {
		stamp(c, "I WAS THERE", accent)
	}
	return c
}

func stamp(c *svg.Canvas, label, color string) {
	c.Raw(`<g transform="rotate(-10 240 125)">`)
	c.Rect(70, 95, 340, 60, 8, "none", ` stroke="`+color+`" stroke-width="4"`)
	drawText(c, 240, 137, label, color, 30, "middle", "l")
	c.Raw(`</g>`)
}

func pad3(n int) string {
	s := itoa(n)
	for len(s) < 3 {
		s = "0" + s
	}
	return s
}

func artistName(id int) string {
	if !catalog.ArtistVisible(id) {
		return ""
	}
	name := catalog.ArtistName(id)
	if !text.Valid(name, 1, 64) {
		return ""
	}
	return name
}
