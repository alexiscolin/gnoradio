package home

import (
	"strconv"
	"testing"

	"gno.land/p/gnoradio/svg/v0"
)

// Pins the SVG art byte for byte, so moving the canvas to a package changes nothing.
func TestArtGolden(t *testing.T) {
	out := coverSVG(1, "Air", 120) + coverSVG(2, "Blood", 120) + coverSVG(3, "R & B", 120) +
		coverSVG(4, "x", 64) + coverSVG(5, "y", 64) + coverSVG(6, "z", 64) +
		onAirSVG("Main", "Air & Fire", "Scott Buckley", 30, 145) + avatarSVG("g1abc", 64) +
		badgeSVG("Early listener", 3) + barsSVG([]bar{{"Pop", 3}, {"Jazz & Soul", 7}}, func(v int64) string { return strconv.FormatInt(v, 10) })
	if svg.FNV(out) != 479829342 || len(out) != 20091 {
		t.Fatalf("home art changed: %d %d", svg.FNV(out), len(out))
	}
}
