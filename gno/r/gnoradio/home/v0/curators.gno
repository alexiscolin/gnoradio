package home

import (
	"strings"

	"gno.land/p/gnoradio/text/v0"

	"gno.land/r/gnoradio/radio/v0"
)

// topCurators lists a station's best pickers this week (radio/curators.gno).
func topCurators(st int) string {
	top := radio.TopCurators(st)
	if len(top) == 0 {
		return ""
	}
	var b strings.Builder
	b.WriteString("## Top curators this week\n\nA pick and a tip received while it is on air score one point each. Pickers earn the artist's promo share of those tips.\n\n")
	for i, c := range top {
		b.WriteString(itoa(i+1) + ". " + who(c.Address) + " · " + plural(c.Picks, "pick") + " · " + plural(c.Tips, "tip") + " · earned " + text.GNOT(c.Earned) + "\n")
	}
	return b.String() + "\n"
}
