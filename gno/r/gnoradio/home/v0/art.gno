package home

import (
	"encoding/base64"
	"strconv"
	"strings"
)

// Sober Swiss artwork, drawn on-chain as SVG and embedded by gnoweb as
// data-URI images: off-white cards, black, warm greys and one red accent.
// Written with a strings.Builder to keep vm/qrender gas low.

const (
	ink   = "#0d0d0d"
	paper = "#fafaf8"
	cream = "#f2efe9"
	grey  = "#c4c4c0"
	stone = "#8f8b84"
	line  = "#e3e3df"
	red   = "#e5432f"
	font  = "font-family:Geist,'Helvetica Neue',Helvetica,Arial,sans-serif"
)

type canvas struct{ b strings.Builder }

func newCanvas(w, h int) *canvas {
	c := &canvas{}
	c.b.WriteString(`<svg xmlns="http://www.w3.org/2000/svg" width="` + itoa(w) + `" height="` + itoa(h) +
		`" viewBox="0 0 ` + itoa(w) + ` ` + itoa(h) + `"><style>text{` + font + `}</style>`)
	return c
}

func (c *canvas) raw(s string) { c.b.WriteString(s) }

func (c *canvas) rect(x, y, w, h, rx int, fill string) {
	c.b.WriteString(`<rect x="` + itoa(x) + `" y="` + itoa(y) + `" width="` + itoa(w) + `" height="` + itoa(h) +
		`" rx="` + itoa(rx) + `" fill="` + fill + `"/>`)
}

func (c *canvas) circle(cx, cy, r int, fill string) {
	c.b.WriteString(`<circle cx="` + itoa(cx) + `" cy="` + itoa(cy) + `" r="` + itoa(r) + `" fill="` + fill + `"/>`)
}

// text writes s (escaped); weight 400–800; anchor start|middle|end.
func (c *canvas) text(x, y int, s, fill string, size, weight int, anchor, extra string) {
	c.b.WriteString(`<text x="` + itoa(x) + `" y="` + itoa(y) + `" fill="` + fill + `" font-size="` + itoa(size) +
		`" font-weight="` + itoa(weight) + `" text-anchor="` + anchor + `"` + extra + `>` + xml(s) + `</text>`)
}

func (c *canvas) image(alt string) string {
	c.b.WriteString("</svg>")
	return "![" + md(alt) + "](data:image/svg+xml;base64," + base64.StdEncoding.EncodeToString([]byte(c.b.String())) + ")"
}

// xml escapes the one special validText lets through (&), and < > for safety.
func xml(s string) string {
	s = strings.ReplaceAll(s, "&", "&amp;")
	s = strings.ReplaceAll(s, "<", "&lt;")
	return strings.ReplaceAll(s, ">", "&gt;")
}

func fnv(s string) uint32 {
	h := uint32(2166136261)
	for i := 0; i < len(s); i++ {
		h ^= uint32(s[i])
		h *= 16777619
	}
	return h
}

// coverSVG draws one of six geometric compositions, picked from the track.
func coverSVG(id int, title string, size int) string {
	h := fnv(strconv.Itoa(id) + title)
	c := newCanvas(size, size)
	s := size
	switch h % 6 {
	case 0:
		c.rect(0, 0, s, s, s/12, ink)
		c.circle(s/2, s/2, s*28/100, red)
	case 1:
		c.rect(0, 0, s, s, s/12, grey)
		c.circle(s/5, s*9/10, s*45/100, stone)
		c.circle(s*68/100, s*32/100, s*15/100, ink)
	case 2:
		c.rect(0, 0, s, s, s/12, red)
		c.raw(`<path d="M0 ` + itoa(s/2) + `H` + itoa(s) + `V` + itoa(s-s/12) + `Q` + itoa(s) + ` ` + itoa(s) + ` ` + itoa(s-s/12) + ` ` + itoa(s) +
			`H` + itoa(s/12) + `Q0 ` + itoa(s) + ` 0 ` + itoa(s-s/12) + `Z" fill="` + cream + `"/>`)
		c.circle(s/2, s/2, s*15/100, ink)
	case 3:
		c.rect(0, 0, s, s, s/12, cream)
		c.rect(s*14/100, s*14/100, s*44/100, s*72/100, s*22/100, stone)
		c.circle(s*74/100, s*27/100, s*13/100, red)
	case 4:
		c.rect(0, 0, s, s, s/12, stone)
		c.raw(`<path d="M` + itoa(s/12) + ` 0H` + itoa(s/2) + `V` + itoa(s) + `H` + itoa(s/12) + `Q0 ` + itoa(s) + ` 0 ` + itoa(s-s/12) +
			`V` + itoa(s/12) + `Q0 0 ` + itoa(s/12) + ` 0Z" fill="` + ink + `"/>`)
		c.circle(s/2, s/2, s/5, cream)
	default:
		c.rect(0, 0, s, s, s/12, ink)
		for i := 0; i < 21; i++ {
			th := s / 14
			if i%5 == 0 {
				th = s / 7
			}
			c.rect(s/10+i*(s*8/10)/20, s*62/100-th, 2, th, 0, paper)
		}
		c.rect(s/10+int(h%17)*(s*8/10)/20, s*36/100, 3, s*30/100, 0, red)
	}
	return c.image("cover of " + title)
}

// onAirSVG is the station banner: huge time numerals and a tick ruler with
// the red needle, as in the app.
func onAirSVG(station, title, artist string, offset, dur int64) string {
	const w, h = 720, 300
	c := newCanvas(w, h)
	c.rect(0, 0, w, h, 26, paper)
	c.rect(28, 26, 104, 30, 10, red)
	c.text(80, 46, "ON AIR", "#fff", 13, 600, "middle", ` letter-spacing="1.5"`)
	c.rect(142, 26, 18+len(station)*9, 30, 10, line)
	c.text(151, 46, station, ink, 13, 500, "start", "")
	if title == "" {
		c.text(w/2, 170, "Silence. Publish the first track.", stone, 26, 600, "middle", "")
		return c.image("nothing on air")
	}
	t := clock(offset)
	if offset < 600 {
		t = "0" + t
	}
	lead := 0
	for lead < len(t) && (t[lead] == '0' || t[lead] == ':') {
		lead++
	}
	c.raw(`<text x="` + itoa(w/2) + `" y="150" font-size="96" font-weight="500" text-anchor="middle" letter-spacing="-4">` +
		`<tspan fill="` + grey + `">` + t[:lead] + `</tspan><tspan fill="` + ink + `">` + t[lead:] + `</tspan></text>`)
	c.text(w/2, 178, "of "+clock(dur)+" · synced to the last block", stone, 13, 400, "middle", "")
	frac := 0
	if dur > 0 {
		frac = int(offset * 1000 / dur)
	}
	for i := 0; i <= 80; i++ {
		th, col := 10, grey
		if i%10 == 0 {
			th = 26
		} else if i%5 == 0 {
			th = 17
		}
		if i*1000/80 <= frac {
			col = ink
		}
		c.rect(40+i*8, 238-th, 2, th, 0, col)
	}
	c.rect(40+frac*640/1000, 196, 2, 50, 0, red)
	c.text(40, 276, artist, stone, 13, 400, "start", "")
	c.text(680, 276, title, ink, 15, 600, "end", "")
	return c.image("on air: " + title)
}

// avatarSVG is a symmetric identicon in the sober palette.
func avatarSVG(seed string, size int) string {
	h := fnv(seed)
	c := newCanvas(size, size)
	c.rect(0, 0, size, size, size/2, cream)
	cell := size / 9
	for y := 0; y < 5; y++ {
		for x := 0; x < 3; x++ {
			h ^= uint32(y*3 + x + 1)
			h *= 16777619
			if (h>>24)%2 == 0 {
				continue
			}
			col := ink
			if (h>>20)%7 == 0 {
				col = red
			}
			c.rect(cell*2+x*cell, cell*2+y*cell, cell, cell, 2, col)
			if x < 2 {
				c.rect(cell*2+(4-x)*cell, cell*2+y*cell, cell, cell, 2, col)
			}
		}
	}
	return c.image("avatar")
}

// badgeSVG is the early-listener badge.
func badgeSVG(title string, rank int) string {
	c := newCanvas(120, 120)
	c.circle(60, 60, 58, ink)
	c.raw(`<circle cx="60" cy="60" r="50" fill="none" stroke="` + paper + `" stroke-width="1" stroke-dasharray="3 4"/>`)
	c.text(60, 50, "EARLY", grey, 11, 600, "middle", ` letter-spacing="2"`)
	c.text(60, 82, "#"+itoa(rank), paper, 30, 500, "middle", "")
	c.circle(60, 100, 4, red)
	return c.image("early listener #" + itoa(rank) + " of " + title)
}

type bar struct {
	label string
	value int64
}

// barsSVG draws a horizontal bar chart.
func barsSVG(rows []bar, unit func(int64) string) string {
	h := 30 + len(rows)*40
	c := newCanvas(640, h)
	c.rect(0, 0, 640, h, 20, paper)
	var max int64 = 1
	for _, r := range rows {
		if r.value > max {
			max = r.value
		}
	}
	for i, r := range rows {
		y := 20 + i*40
		w := int(r.value * 300 / max)
		if w < 4 {
			w = 4
		}
		col := ink
		if i == 0 {
			col = red
		}
		c.text(20, y+20, clip(r.label, 20), ink, 14, 500, "start", "")
		c.rect(210, y+6, w, 18, 9, col)
		c.text(220+w, y+20, unit(r.value), stone, 13, 400, "start", "")
	}
	return c.image("chart")
}

func clip(s string, n int) string {
	r := []rune(s)
	if len(r) <= n {
		return s
	}
	return string(r[:n-1]) + "…"
}
