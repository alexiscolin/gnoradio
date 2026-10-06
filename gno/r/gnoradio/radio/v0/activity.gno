package radio

import "strings"

const activitySize = 64

// Activity is one programming action on a station.
type Activity struct {
	Kind    string // queue | curator
	By      address
	Track   int
	Station int
	Start   int64
	At      int64
}

var (
	activity     [activitySize]Activity // ring buffer, fixed size
	activityHead int
	activityN    int
)

func recordActivity(kind string, by address, track, station int, start int64) {
	activity[activityHead] = Activity{Kind: kind, By: by, Track: track, Station: station, Start: start, At: now()}
	activityHead = (activityHead + 1) % activitySize
	if activityN < activitySize {
		activityN++
	}
}

// Activities returns up to limit entries, newest first.
func Activities(limit int) []Activity {
	if limit < 1 || limit > activitySize {
		limit = activitySize
	}
	if limit > activityN {
		limit = activityN
	}
	out := make([]Activity, 0, limit)
	for i := 1; i <= limit; i++ {
		out = append(out, activity[(activityHead-i+activitySize)%activitySize])
	}
	return out
}

// ActivityJSON returns the programming feed, newest first (limit <= 64).
func ActivityJSON(limit int) string {
	var b strings.Builder
	b.WriteString("[")
	for i, a := range Activities(limit) {
		if i > 0 {
			b.WriteString(",")
		}
		b.WriteString(`{"kind":` + q(a.Kind) + `,"by":` + q(a.By.String()) + `,"track":` + itoa(a.Track) +
			`,"station":` + itoa(a.Station) + `,"start":` + itoa64(a.Start) + `,"at":` + itoa64(a.At) + `}`)
	}
	b.WriteString("]")
	return b.String()
}
