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
// rotation. A listener pick tops it up for free to GnoRadio when less than an
// hour is programmed, a few slots at most so a pick's deposit stays small
// (folding the slots that aired gives most of it back); the robot sends Sync
// only when NeedsSync says so.

const (
	fillAhead = 3 * 3600 // seconds of flow written ahead
	maxFill   = 24       // flow slots written per call
	maxTries  = 4        // rotation slots tried per pick
)

// energy orders the genres from calm to intense; neighbours blend well.
var energy = [catalog.NumGenres]int{
	3,  // Ambient
	16, // Cinematic & Classical
	15, // Folk & Acoustic
	14, // Jazz & Blues
	8,  // Lo-fi Beats
	10, // R&B & Soul
	19, // Reggae & Dub
	17, // World
	18, // Latin
	20, // Funk & Disco
	13, // Pop
	9,  // Hip-hop & Rap
	11, // Rock & Indie
	2,  // Synthwave
	1,  // Electronic
	5,  // House
	4,  // Techno
	7,  // Dubstep & Trap
	6,  // Drum & Bass
	12, // Metal & Punk
}

// dayparts is the target index in energy for each 3-hour block of the UTC day:
// Jazz, Ambient, Lo-fi, World, Pop, Rock, House, then Drum & Bass at the peak.
var dayparts = [8]int{3, 0, 4, 7, 10, 12, 15, 18}

var (
	setGenre int                        // genre of the set being written
	setLeft  int                        // tracks left in that set
	cursor   [catalog.NumGenres + 1]int // next slot of each genre rotation
)

// program tops up the station's flow until fillAhead seconds after ts,
// writing at most max slots.
func (st *station) program(ts int64, max int) {
	st.fold(ts)
	start, prev := st.reach(ts)
	prevArtist, _, _, _ := catalog.TrackBrief(prev)
	failed := false
	for n := 0; n < max && start < ts+fillAhead && len(st.schedule) < maxSchedule; n++ {
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
		start = st.lay(Slot{Track: id, Dur: d}, start) // around booked picks
		prevArtist = artist
		setLeft--
	}
}

// ahead is how many seconds of the station are programmed after ts (a pick
// booked later, after a gap, does not count).
func (st *station) ahead(ts int64) int64 {
	t, _ := st.reach(ts)
	return t - ts
}

// reach is where the slots programmed from ts on end, without a gap (from
// the end of the rotation track on air when none plays), and their last track.
func (st *station) reach(ts int64) (int64, int) {
	t, prev := st.follow(ts, 0)
	if prev == 0 {
		if _, track, off, d, ok := st.rotationAt(ts); ok {
			t, prev = st.follow(ts+d-off, track)
		}
	}
	return t, prev
}

func (st *station) follow(t int64, prev int) (int64, int) {
	for _, s := range st.schedule {
		if s.Start <= t && s.Start+s.Dur > t {
			t, prev = s.Start+s.Dur, s.Track
		}
	}
	return t, prev
}

// pick takes the next track of a genre rotation that is live, not dropped
// from this station, not by the previous artist and not already in the log.
func (st *station) pick(genre, prevArtist int) (id, artist int, dur int64, ok bool) {
	rot := stations[genre].rot
	for k := 0; k < maxTries && rot.Len() > 0; k++ {
		i := cursor[genre] % rot.Len()
		cursor[genre] = i + 1
		id, dur = rot.Slot(i)
		if dur == 0 || st.programmed(id) || dropped.Len() > 0 && dropped.Has(dropKey(st.id, id)) {
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
