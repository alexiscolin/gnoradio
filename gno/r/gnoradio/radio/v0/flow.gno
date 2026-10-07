package radio

import "gno.land/r/gnoradio/catalog/v0"

// The main station's flow works like a radio music log: Sync writes the next
// three hours of the main station in advance as programmed slots with an empty By.
// Tracks come in sets of 3 to 5 from one genre; each set moves one step along
// an energy line toward the target of the time of day (UTC dayparts: calm at
// night, peak in the evening). Inside a genre the flow walks that station's
// rotation, so a track comes back only after its whole genre has played; it
// never plays the same artist twice in a row nor a track still in the log.
// Listener and curator picks go before the flow, which waits for them. When
// nothing tops it up for three hours, the main station falls back to its
// rotation. Listener picks top it up for free to GnoRadio; the robot sends
// Sync only when NeedsSync says so.

const (
	fillAhead = 3 * 3600 // seconds of flow written ahead
	maxFill   = 24       // flow slots written per call
	maxTries  = 4        // rotation slots tried per pick
)

// energy orders the genres from calm to intense; neighbours blend well.
var energy = [catalog.NumGenres]int{
	3,  // Ambient
	11, // Cinematic & Classical
	10, // Folk & Acoustic
	9,  // Jazz & Soul
	5,  // Lo-fi & Chill
	6,  // Hip-hop & Beats
	12, // World
	8,  // Pop
	7,  // Rock & Indie
	2,  // Synthwave
	1,  // Electronic
	4,  // Techno & House
}

// dayparts is the target index in energy for each 3-hour block of the UTC day.
var dayparts = [8]int{3, 0, 4, 6, 7, 8, 10, 11}

var (
	setGenre int                        // genre of the set being written
	setLeft  int                        // tracks left in that set
	cursor   [catalog.NumGenres + 1]int // next slot of each genre rotation
)

// program tops up the station's flow until fillAhead seconds after ts.
func (st *station) program(ts int64) {
	st.fold(ts)
	start, prev := ts, 0
	if n := len(st.schedule); n > 0 && st.schedule[n-1].Start+st.schedule[n-1].Dur > ts {
		start, prev = st.schedule[n-1].Start+st.schedule[n-1].Dur, st.schedule[n-1].Track
	} else if _, track, off, d, ok := st.rotationAt(ts); ok {
		start, prev = ts+d-off, track
	}
	prevArtist, _, _, _ := catalog.TrackBrief(prev)
	failed := false
	for n := 0; n < maxFill && start < ts+fillAhead; n++ {
		if setLeft <= 0 {
			if setGenre = nextGenre(setGenre, start); setGenre == 0 {
				return
			}
			setLeft = 3 + int(start/60%3)
		}
		id, artist, d, ok := st.pick(setGenre, prevArtist)
		if !ok {
			if failed {
				return // two genres in a row with nothing fit: the catalog is too small
			}
			failed, setLeft = true, 0 // move on to the next genre
			continue
		}
		failed = false
		st.schedule = append(st.schedule, Slot{Track: id, Start: start, Dur: d})
		start += d
		prevArtist = artist
		setLeft--
	}
}

// ahead is how many seconds of the station are programmed after ts.
func (st *station) ahead(ts int64) int64 {
	if n := len(st.schedule); n > 0 {
		if end := st.schedule[n-1].Start + st.schedule[n-1].Dur; end > ts {
			return end - ts
		}
	}
	return 0
}

// pick takes the next track of a genre rotation that is live, not dropped
// from this station, not by the previous artist and not already in the log.
func (st *station) pick(genre, prevArtist int) (id, artist int, dur int64, ok bool) {
	rot := stations[genre].rot
	for k := 0; k < maxTries && rot.Len() > 0; k++ {
		i := cursor[genre] % rot.Len()
		cursor[genre] = i + 1
		id, dur = rot.Slot(i)
		if dur == 0 || st.programmed(id) || dropped.Size() > 0 && dropped.Has(dropKey(st.id, id)) {
			continue
		}
		if a, _, _, playable := catalog.TrackBrief(id); playable && a != prevArtist {
			return id, a, dur, true
		}
	}
	return 0, 0, 0, false
}

func (st *station) programmed(trackID int) bool {
	for _, s := range st.schedule {
		if s.Track == trackID {
			return true
		}
	}
	return false
}

// nextGenre steps from genre g toward the daypart target on the energy line
// (around the target it wanders one step either way), skipping empty genres.
// It returns 0 when no genre station has a live track.
func nextGenre(g int, at int64) int {
	t := dayparts[at%86400/10800]
	i := t
	for j, x := range energy {
		if x == g {
			i = j
		}
	}
	d := 1
	if i > t || i == t && at/60%2 == 0 {
		d = -1
	}
	for k := 1; k < len(energy); k++ {
		if j := i + d*k; j >= 0 && j < len(energy) && stations[energy[j]].live > 0 {
			return energy[j]
		}
		if j := i - d*k; j >= 0 && j < len(energy) && stations[energy[j]].live > 0 {
			return energy[j]
		}
	}
	if stations[energy[i]].live > 0 {
		return energy[i]
	}
	return 0
}
