package gnoradio

import (
	"encoding/base64"
	"strconv"
	"strings"
)

// All artwork is generated on-chain as SVG and embedded by gnoweb as data-URI
// images. Every string drawn here passed validText, so it holds no XML specials.
// SVG is written with a plain strings.Builder: it is several times cheaper in
// gas than a generic element tree, which matters because vm/qrender has a
// fixed gas budget per page.

// palette is derived from a hue taken from the seed, so every track gets its
// own colors (HSL is valid in SVG).
type palette struct{ bg, a, b, c string }

func hsl(h, s, l int) string {
	return "hsl(" + itoa(h%360) + "," + itoa(s) + "%," + itoa(l) + "%)"
}

func paletteOf(seed string) palette {
	h := int(fnv(seed) % 360)
	return palette{bg: hsl(h, 45, 10), a: hsl(h+150, 90, 62), b: hsl(h+30, 70, 42), c: hsl(h, 30, 92)}
}

type canvas struct{ b strings.Builder }

func newCanvas(w, h, vw, vh int) *canvas {
	c := &canvas{}
	c.b.WriteString(`<svg xmlns="http://www.w3.org/2000/svg" width="` + itoa(w) + `" height="` + itoa(h) +
		`" viewBox="0 0 ` + itoa(vw) + ` ` + itoa(vh) + `"><style>text{font-family:system-ui,-apple-system,'Segoe UI',Roboto,Helvetica,Arial,sans-serif;font-weight:800}.m{font-weight:500}.l{font-weight:700;letter-spacing:.12em}</style>`)
	return c
}

func (c *canvas) raw(s string) { c.b.WriteString(s) }

// gradient defines a diagonal gradient with the given id.
func (c *canvas) gradient(id, from, to string) {
	c.b.WriteString(`<defs><linearGradient id="` + id + `" x2="1" y2="1"><stop stop-color="` + from +
		`"/><stop offset="1" stop-color="` + to + `"/></linearGradient></defs>`)
}

func (c *canvas) rect(x, y, w, h, rx int, fill, extra string) {
	c.b.WriteString(`<rect x="` + itoa(x) + `" y="` + itoa(y) + `" width="` + itoa(w) + `" height="` + itoa(h) +
		`" rx="` + itoa(rx) + `" fill="` + fill + `"` + extra + `/>`)
}

func (c *canvas) circle(cx, cy, r int, fill, extra string) {
	c.b.WriteString(`<circle cx="` + itoa(cx) + `" cy="` + itoa(cy) + `" r="` + itoa(r) + `" fill="` + fill + `"` + extra + `/>`)
}

// text writes s; anchor is start, middle or end. class is "", "m" (medium)
// or "l" (spaced label).
func (c *canvas) text(x, y int, s, fill string, size int, anchor string) {
	c.textc(x, y, s, fill, size, anchor, "")
}

func (c *canvas) textc(x, y int, s, fill string, size int, anchor, class string) {
	cls := ""
	if class != "" {
		cls = ` class="` + class + `"`
	}
	c.b.WriteString(`<text x="` + itoa(x) + `" y="` + itoa(y) + `" fill="` + fill + `" font-size="` + itoa(size) +
		`" text-anchor="` + anchor + `"` + cls + `>` + s + `</text>`)
}

// image returns the markdown image embedding the SVG.
func (c *canvas) image(alt string) string {
	c.b.WriteString("</svg>")
	return "![" + md(alt) + "](data:image/svg+xml;base64," + base64.StdEncoding.EncodeToString([]byte(c.b.String())) + ")"
}

func op(o string) string { return ` opacity="` + o + `"` }

func fnv(s string) uint32 {
	h := uint32(2166136261)
	for i := 0; i < len(s); i++ {
		h ^= uint32(s[i])
		h *= 16777619
	}
	return h
}

// bytesOf derives a stream of pseudo-random bytes from a seed string.
func bytesOf(seed string, n int) []int {
	out := make([]int, n)
	h := fnv(seed)
	for i := range out {
		h ^= uint32(i + 1)
		h *= 16777619
		out[i] = int(h >> 24)
	}
	return out
}

func clip(s string, n int) string {
	r := []rune(s)
	if len(r) <= n {
		return s
	}
	return string(r[:n-1]) + "…"
}

func trackSeed(t *Track) string { return strconv.Itoa(t.ID) + t.Title + t.CID }

// coverSVG draws a cover unique to the track: one of four motifs, colors from
// the track's hue, title on a dark band so it stays readable at 150px.
func coverSVG(t *Track, size int, withText bool) string {
	seed := trackSeed(t)
	p := paletteOf(seed)
	r := bytesOf(seed, 48)
	c := newCanvas(size, size, 300, 300)
	c.raw(`<defs><linearGradient id="g" x1="` + itoa(r[40]%2) + `" y1="0" x2="` + itoa(1-r[40]%2) +
		`" y2="1"><stop stop-color="` + p.bg + `"/><stop offset="1" stop-color="` + p.b + `"/></linearGradient></defs>`)
	c.rect(0, 0, 300, 300, 18, "url(#g)", "")

	switch r[3] % 4 {
	case 0: // vinyl
		cx, cy, rad := 110+r[0]%80, 120+r[1]%80, 70+r[2]%30
		c.circle(cx, cy, rad+40, p.a, op("0.15"))
		c.circle(cx, cy, rad, "#0b0b0f", op("0.92"))
		c.raw(`<g fill="none" stroke="#fff" opacity="0.1">`)
		for i := 1; i < 6; i++ {
			c.circle(cx, cy, rad-i*rad/7, "none", "")
		}
		c.raw(`</g>`)
		c.circle(cx, cy, rad/3, p.a, "")
		c.circle(cx, cy, 4, "#0b0b0f", "")
	case 1: // sun with stripes
		cx, cy := 150, 150+r[0]%40
		c.circle(cx, cy, 110, p.a, "")
		for i := 0; i < 6; i++ {
			c.rect(0, cy-10+i*18, 300, 6+i, 0, p.bg, op("0.9"))
		}
	case 2: // dot grid
		for y := 0; y < 9; y++ {
			for x := 0; x < 9; x++ {
				v := r[(x+y*9)%40]
				if v%3 == 0 {
					continue
				}
				fill := p.a
				if v%5 == 0 {
					fill = p.c
				}
				c.circle(22+x*32, 22+y*32, 4+v%9, fill, op("0.8"))
			}
		}
	default: // concentric waves
		c.raw(`<g fill="none" stroke="` + p.a + `" stroke-width="6" opacity="0.8">`)
		for i := 0; i < 7; i++ {
			c.circle(r[0]%300, 300, 40+i*38, "none", "")
		}
		c.raw(`</g>`)
	}
	// Waveform.
	c.raw(`<g opacity="0.75">`)
	for i := 0; i < 30; i++ {
		h := 6 + r[(i+6)%40]%30
		c.rect(18+i*9, 288-h, 5, h, 2, p.c, "")
	}
	c.raw(`</g>`)
	if withText {
		c.raw(`<defs><linearGradient id="s" x2="0" y2="1"><stop stop-opacity=".6"/><stop offset="1" stop-opacity="0"/></linearGradient></defs>`)
		c.rect(0, 0, 300, 90, 18, "url(#s)", "")
		c.text(18, 40, clip(t.Title, 18), "#fff", 26, "start")
		if a := getArtist(t.Artist); a != nil {
			c.textc(18, 66, clip(a.Name, 24), p.c, 17, "start", "m")
		}
	}
	return c.image("pochette de " + t.Title)
}

// bannerSVG is the "on air" header of the home page.
func bannerSVG(t *Track, offset int64, queued bool) string {
	seed := "idle"
	if t != nil {
		seed = trackSeed(t)
	}
	p := paletteOf(seed)
	c := newCanvas(720, 190, 720, 190)
	c.gradient("b", p.bg, p.b)
	c.rect(0, 0, 720, 190, 20, "url(#b)", "")
	r := bytesOf(seed, 30)
	c.raw(`<g opacity="0.3">`)
	for i := 0; i < 30; i++ {
		h := 10 + r[i]%90
		c.rect(400+i*10, 95-h/2, 6, h, 3, p.a, "")
	}
	c.raw(`</g>`)
	if t == nil {
		c.textc(28, 44, "GNORADIO", p.a, 14, "start", "l")
		c.text(28, 104, "Silence radio. Publie le premier morceau !", "#fff", 26, "start")
		return c.image("GnoRadio, rien à l'antenne")
	}
	c.rect(28, 26, 112, 26, 13, "#ff1744", "")
	c.textc(84, 44, "EN DIRECT", "#fff", 12, "middle", "l")
	src := "ROTATION"
	if queued {
		src = "PROGRAMMÉ PAR UN AUDITEUR"
	}
	c.textc(152, 44, src, p.c, 12, "start", "l")
	c.text(28, 104, clip(t.Title, 26), "#fff", 36, "start")
	if a := getArtist(t.Artist); a != nil {
		c.textc(28, 134, clip(a.Name, 40), p.c, 18, "start", "m")
	}
	w := int(offset * 560 / t.Duration)
	c.rect(28, 158, 560, 6, 3, "#fff", op("0.25"))
	c.rect(28, 158, w, 6, 3, p.a, "")
	c.circle(28+w, 161, 8, "#fff", "")
	c.textc(692, 166, clock(offset)+" / "+clock(t.Duration), "#fff", 14, "end", "m")
	return c.image("En direct : " + t.Title)
}

// avatarSVG is a symmetric identicon for an artist address.
func avatarSVG(addr address, size int) string {
	seed := addr.String()
	p := paletteOf(seed)
	r := bytesOf(seed, 15)
	c := newCanvas(size, size, 100, 100)
	c.gradient("a", p.bg, p.b)
	c.rect(0, 0, 100, 100, 50, "url(#a)", "")
	for y := 0; y < 5; y++ {
		for x := 0; x < 3; x++ {
			v := r[y*3+x]
			if v%2 == 0 {
				continue
			}
			fill := p.a
			if v%3 == 0 {
				fill = p.c
			}
			c.rect(20+x*12, 20+y*12, 12, 12, 2, fill, "")
			if x < 2 {
				c.rect(20+(4-x)*12, 20+y*12, 12, 12, 2, fill, "")
			}
		}
	}
	return c.image("avatar")
}

// ticketSVG draws the NFT ticket; the perforation is cut out with a mask so
// it reads as holes on light and dark backgrounds. serial 0 is a specimen.
func ticketSVG(e *Event, serial int, attended bool) string {
	seed := "event" + itoa(e.ID) + e.Title
	p := paletteOf(seed)
	r := bytesOf(seed, 48)
	c := newCanvas(640, 250, 640, 250)
	c.gradient("t", p.bg, p.b)
	c.raw(`<mask id="h"><rect width="640" height="250" fill="#fff"/>`)
	for y := 14; y < 250; y += 18 {
		c.circle(470, y, 4, "#000", "")
	}
	c.circle(470, 0, 16, "#000", "")
	c.circle(470, 250, 16, "#000", "")
	c.raw(`</mask><g mask="url(#h)">`)
	c.rect(0, 0, 640, 250, 22, "url(#t)", "")
	c.raw(`<g opacity="0.14">`)
	for i := 0; i < 5; i++ {
		c.circle(120+r[i]%280, 40+r[i+5]%170, 30+r[i+10]%70, p.a, "")
	}
	c.raw(`</g></g>`)

	c.textc(30, 44, "GNORADIO LIVE", p.a, 13, "start", "l")
	c.text(30, 96, clip(e.Title, 24), "#fff", 32, "start")
	if a := getArtist(e.Artist); a != nil {
		c.textc(30, 128, clip(a.Name, 34), p.c, 18, "start", "m")
	}
	c.textc(30, 182, clip(e.Venue, 34), "#fff", 15, "start", "m")
	c.textc(30, 206, date(e.Start), "#fff", 15, "start", "m")
	price := "ENTRÉE LIBRE"
	if e.Price > 0 {
		price = gnot(e.Price)
	}
	c.textc(440, 206, price, p.a, 15, "end", "l")

	// Stub.
	c.textc(555, 46, "ADMIT ONE", p.c, 12, "middle", "l")
	num := "SPECIMEN"
	if serial > 0 {
		num = "#" + itoa(serial) + "/" + itoa(e.Capacity)
	}
	c.text(555, 82, num, "#fff", 20, "middle")
	for i := 0; i < 24; i++ {
		c.rect(500+i*5, 110, 1+r[24+i]%4, 90, 0, "#fff", "")
	}
	c.textc(555, 226, "on gno.land", p.c, 11, "middle", "m")
	if e.Cancelled {
		c.raw(`<g transform="rotate(-12 240 125)">`)
		c.rect(90, 95, 300, 60, 8, "none", ` stroke="#ff1744" stroke-width="5"`)
		c.textc(240, 138, "ANNULÉ", "#ff1744", 34, "middle", "l")
		c.raw(`</g>`)
	} else if attended {
		c.raw(`<g transform="rotate(-12 240 125)">`)
		c.rect(80, 95, 320, 60, 8, "none", ` stroke="`+p.a+`" stroke-width="5"`)
		c.textc(240, 138, "J'Y ÉTAIS", p.a, 34, "middle", "l")
		c.raw(`</g>`)
	}
	return c.image("billet pour " + e.Title)
}

// badgeSVG is the "premier auditeur" badge for a track.
func badgeSVG(t *Track, rank int) string {
	p := paletteOf(trackSeed(t))
	c := newCanvas(120, 120, 120, 120)
	c.gradient("e", p.a, p.b)
	c.raw(`<polygon points="60,4 74,20 96,16 98,38 116,52 104,72 112,94 90,100 80,118 60,108 40,118 30,100 8,94 16,72 4,52 22,38 24,16 46,20" fill="url(#e)"/>`)
	c.circle(60, 60, 38, p.bg, ` stroke="`+p.c+`" stroke-width="2"`)
	c.textc(60, 52, "1ER·E·S", p.c, 10, "middle", "l")
	c.text(60, 78, "#"+itoa(rank), "#fff", 22, "middle")
	return c.image("premier auditeur #" + itoa(rank) + " de " + t.Title)
}

// gaugeSVG is a thin progress bar (tickets sold, split shares).
func gaugeSVG(parts []int64, colors []string, label string) string {
	c := newCanvas(640, 18, 640, 18)
	c.rect(0, 0, 640, 18, 9, "#8888", "")
	var total, x int64
	for _, v := range parts {
		total += v
	}
	if total == 0 {
		total = 1
	}
	for i, v := range parts {
		w := v * 640 / total
		if i == len(parts)-1 {
			w = 640 - x
		}
		if w > 0 {
			c.rect(int(x), 0, int(w), 18, 9, colors[i%len(colors)], "")
		}
		x += w
	}
	return c.image(label)
}

type bar struct {
	label string
	value int64
}

// barsSVG draws a horizontal bar chart (charts page).
func barsSVG(rows []bar, unit func(int64) string) string {
	h := 40 + len(rows)*44
	p := paletteOf("charts")
	c := newCanvas(640, h, 640, h)
	c.gradient("c", p.a, p.b)
	c.rect(0, 0, 640, h, 16, p.bg, "")
	var max int64 = 1
	for _, r := range rows {
		if r.value > max {
			max = r.value
		}
	}
	for i, r := range rows {
		y := 24 + i*44
		w := int(r.value * 330 / max)
		if w < 4 {
			w = 4
		}
		c.textc(20, y+22, clip(r.label, 18), "#fff", 14, "start", "m")
		c.rect(200, y+6, w, 24, 6, "url(#c)", "")
		c.textc(210+w, y+23, unit(r.value), p.c, 13, "start", "m")
	}
	return c.image("graphique")
}
