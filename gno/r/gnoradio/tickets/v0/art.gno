package tickets

import (
	"encoding/base64"
	"strings"

	"gno.land/p/nt/markdown/sanitize/v0"
)

// Tickets are drawn on-chain as SVG in the GnoRadio sober style: white,
// black and greys with a single red accent. The perforation is cut out with a
// mask so it reads as holes on any page background. Every string drawn here
// passed validText, so it holds no XML specials.

const (
	ink    = "#0d0d0d"
	paper  = "#fafaf8"
	grey   = "#9a9a96"
	accent = "#e5432f"
)

type canvas struct{ b strings.Builder }

func newCanvas(w, h int) *canvas {
	c := &canvas{}
	c.b.WriteString(`<svg xmlns="http://www.w3.org/2000/svg" width="` + itoa(w) + `" height="` + itoa(h) +
		`" viewBox="0 0 ` + itoa(w) + ` ` + itoa(h) + `"><style>text{font-family:system-ui,-apple-system,'Segoe UI',Roboto,Helvetica,Arial,sans-serif;font-weight:600}.m{font-weight:500}.l{font-weight:600;letter-spacing:.08em}.n{font-family:ui-monospace,Menlo,monospace;font-weight:500}</style>`)
	return c
}

func (c *canvas) raw(s string) { c.b.WriteString(s) }

func (c *canvas) rect(x, y, w, h, rx int, fill, extra string) {
	c.b.WriteString(`<rect x="` + itoa(x) + `" y="` + itoa(y) + `" width="` + itoa(w) + `" height="` + itoa(h) +
		`" rx="` + itoa(rx) + `" fill="` + fill + `"` + extra + `/>`)
}

func (c *canvas) circle(cx, cy, r int, fill string) {
	c.b.WriteString(`<circle cx="` + itoa(cx) + `" cy="` + itoa(cy) + `" r="` + itoa(r) + `" fill="` + fill + `"/>`)
}

func (c *canvas) text(x, y int, s, fill string, size int, anchor, class string) {
	cls := ""
	if class != "" {
		cls = ` class="` + class + `"`
	}
	c.b.WriteString(`<text x="` + itoa(x) + `" y="` + itoa(y) + `" fill="` + fill + `" font-size="` + itoa(size) +
		`" text-anchor="` + anchor + `"` + cls + `>` + s + `</text>`)
}

func (c *canvas) image(alt string) string {
	c.b.WriteString("</svg>")
	return "![" + sanitize.InlineText(alt) + "](data:image/svg+xml;base64," + base64.StdEncoding.EncodeToString([]byte(c.b.String())) + ")"
}

// dataURI returns the bare SVG data URI (for NFT metadata).
func (c *canvas) dataURI() string {
	c.b.WriteString("</svg>")
	return "data:image/svg+xml;base64," + base64.StdEncoding.EncodeToString([]byte(c.b.String()))
}

func clip(s string, n int) string {
	r := []rune(s)
	if len(r) <= n {
		return s
	}
	return string(r[:n-1]) + "…"
}

func fnv(s string) uint32 {
	h := uint32(2166136261)
	for i := 0; i < len(s); i++ {
		h ^= uint32(s[i])
		h *= 16777619
	}
	return h
}

// drawTicket draws a ticket; serial 0 is the specimen shown before purchase.
func drawTicket(e *Event, serial int, attended bool) *canvas {
	c := newCanvas(640, 250)
	// Black ticket with perforation and side notches cut out.
	c.raw(`<mask id="h"><rect width="640" height="250" fill="#fff"/>`)
	for y := 18; y < 250; y += 16 {
		c.circle(470, y, 3, "#000")
	}
	c.circle(470, 0, 14, "#000")
	c.circle(470, 250, 14, "#000")
	c.raw(`</mask><g mask="url(#h)">`)
	c.rect(0, 0, 640, 250, 24, ink, "")
	c.raw(`</g>`)

	c.text(30, 44, "GNORADIO · ADMIT ONE", grey, 12, "start", "l")
	c.text(30, 96, clip(e.Title, 24), paper, 32, "start", "")
	c.text(30, 128, clip(artistName(e.ArtistID), 34), grey, 18, "start", "m")
	c.text(30, 182, clip(e.Venue, 34), paper, 15, "start", "m")
	c.text(30, 206, date(e.Start), paper, 15, "start", "m")
	price := "FREE"
	if e.Price > 0 {
		price = gnot(e.Price)
	}
	c.text(440, 206, price, grey, 14, "end", "l")

	// Stub: serial, barcode, red dot.
	num := "SPECIMEN"
	if serial > 0 {
		num = "#" + pad3(serial) + "/" + itoa(e.Capacity)
	}
	c.text(555, 54, num, paper, 16, "middle", "n")
	h := fnv("event" + itoa(e.ID) + e.Title)
	for i := 0; i < 22; i++ {
		h ^= uint32(i + 1)
		h *= 16777619
		c.rect(502+i*5, 80, 1+int(h>>24)%3, 80, 0, paper, "")
	}
	c.circle(555, 200, 14, accent)

	if e.Cancelled {
		stamp(c, "CANCELLED", accent)
	} else if attended {
		stamp(c, "I WAS THERE", accent)
	}
	return c
}

func stamp(c *canvas, label, color string) {
	c.raw(`<g transform="rotate(-10 240 125)">`)
	c.rect(70, 95, 340, 60, 8, "none", ` stroke="`+color+`" stroke-width="4"`)
	c.text(240, 137, label, color, 30, "middle", "l")
	c.raw(`</g>`)
}

func pad3(n int) string {
	s := itoa(n)
	for len(s) < 3 {
		s = "0" + s
	}
	return s
}

func artistName(id int) string {
	name := catalogName(id)
	if !validText(name, 1, 64) {
		return ""
	}
	return name
}
