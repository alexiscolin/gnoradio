// PKGPATH: gno.land/r/gnoradio/pointers
package pointers

// A station of Audius or Jamendo pointers airs them: they store no title, and
// the schedule once skipped every track without one, leaving the station silent.

import (
	"strings"
	"testing"

	catalog "gno.land/r/gnoradio/catalog/v1"
	radio "gno.land/r/gnoradio/radio/v1"
)

func main(cur realm) {
	testing.SetRealm(testing.NewUserRealm(catalog.Admin()))
	a := itoa(catalog.CreateArtist(cross(cur), catalog.OriginJamendo, "", "", "jamendo-artist:7"))
	radio.ImportTracks(cross(cur), a+"\t\t3\t3:30\tCC-BY-SA-3.0\t\tjamendo:1886257\t\t\t\t\t\n"+
		a+"\t\t3\t3:30\tCC-BY-SA-3.0\t\tjamendo:1886258\t\t\t\t\t")
	js := radio.ScheduleJSON(3, 3600)
	println(strings.Count(js, `"title":"Jamendo track"`) > 0)
}

func itoa(n int) string {
	s := ""
	for n > 0 {
		s = string(rune('0'+n%10)) + s
		n /= 10
	}
	return s
}

// Output:
// true
