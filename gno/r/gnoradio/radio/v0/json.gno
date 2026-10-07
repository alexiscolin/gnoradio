package radio

import (
	"strconv"
	"strings"

	"gno.land/p/gnoradio/text/v0"

	"gno.land/r/gnoradio/catalog/v0"
)

// Read API for the GnoRadio app (vm/qeval).

// ScheduleJSON returns what a station plays from now until now+horizon seconds
// (60..7200, at most 60 entries): programmed slots and the rotation between
// them. A client plays entry i from offset+max(0, clock-start) and resyncs on
// "now". "sponsored" is the refund its artist pays the picker (0: a normal
// pick), "at" the time a booked pick asked for (0: none). "booked" lists every
// booked pick still to air, whatever the horizon (at most maxQueue):
// {"track","start","end","at","by","note"}. Fetch it again every few minutes, not
// every second.
func ScheduleJSON(stationID, horizon int) string {
	st := mustStation(stationID)
	if horizon < 60 || horizon > 7200 {
		horizon = 3600
	}
	ts := now()
	end := ts + int64(horizon)
	var b strings.Builder
	b.WriteString(`{"station":` + itoa(st.id) + `,"now":` + itoa64(ts) + `,"entries":[`)
	n := 0
	emit := func(track int, start, stop, offset int64, queued bool, by, note string, pay, at int64) {
		if n > 0 {
			b.WriteString(",")
		}
		b.WriteString(`{"track":` + itoa(track) + `,"title":` + text.Str(catalog.TrackTitle(track)) +
			`,"start":` + itoa64(start) + `,"end":` + itoa64(stop) + `,"offset":` + itoa64(offset) +
			`,"queued":` + strconv.FormatBool(queued) + `,"by":` + text.Str(by) + `,"note":` + text.Str(note) + `,"sponsored":` + itoa64(pay) + `,"at":` + itoa64(at) + `}`)
		n++
	}
	cur := ts
	for cur < end && n < 60 {
		var slot *Slot
		next := int64(-1)
		for i := range st.schedule {
			s := &st.schedule[i]
			if cur >= s.Start && cur < s.Start+s.Dur {
				slot = s
				break
			}
			if s.Start > cur && (next < 0 || s.Start < next) {
				next = s.Start
			}
		}
		if slot != nil {
			stop := slot.Start + slot.Dur
			if _, _, _, ok := catalog.TrackBrief(slot.Track); ok {
				emit(slot.Track, slot.Start, stop, 0, slot.By != "", slot.By.String(), slot.shownNote(), slot.Pay, slot.At)
			}
			cur = stop
			continue
		}
		_, track, off, dur, ok := st.rotationAt(cur)
		if !ok {
			if next < 0 {
				break
			}
			cur = next
			continue
		}
		stop := cur + dur - off
		if next >= 0 && next < stop {
			stop = next // the rotation pauses for the programmed slot
		}
		if _, _, _, playable := catalog.TrackBrief(track); playable {
			emit(track, cur-off, stop, off, false, "", "", 0, 0)
		}
		cur = stop
	}
	b.WriteString(`],"booked":[`)
	n = 0
	for _, s := range st.schedule {
		if s.At > 0 && s.Start+s.Dur > ts {
			if n > 0 {
				b.WriteString(",")
			}
			b.WriteString(`{"track":` + itoa(s.Track) + `,"start":` + itoa64(s.Start) + `,"end":` + itoa64(s.Start+s.Dur) + `,"at":` + itoa64(s.At) + `,"by":` + text.Str(s.By.String()) + `,"note":` + text.Str(s.shownNote()) + `}`)
			n++
		}
	}
	b.WriteString(`]}`)
	return b.String()
}

// StationsJSON lists every station with what it plays now.
func StationsJSON() string {
	var b strings.Builder
	// newFloor: only tracks above this id may be picked on New this week.
	floor := synced - newCap
	if floor < 0 {
		floor = 0
	}
	b.WriteString(`{"pending":` + itoa(Pending()) + `,"newFloor":` + itoa(floor) + `,"stations":[`)
	for i, st := range stations {
		if i > 0 {
			b.WriteString(",")
		}
		tracks, loop, queued := StationInfo(st.id)
		track, offset, isQueued := st.onAir(now())
		b.WriteString(`{"id":` + itoa(st.id) + `,"name":` + text.Str(StationName(st.id)) + `,"genre":` + itoa(st.genre) +
			`,"tracks":` + itoa(tracks) + `,"loop":` + itoa64(loop) + `,"queued":` + itoa(queued) +
			`,"now":{"track":` + itoa(track) + `,"offset":` + itoa64(offset) + `,"queued":` + strconv.FormatBool(isQueued) + `}}`)
	}
	b.WriteString(`]}`)
	return b.String()
}
