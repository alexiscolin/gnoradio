package gnoradio

import (
	"encoding/base64"
	"strings"
)

// Read API for the GnoRadio app (vm/qeval). All strings in these documents
// passed validText/validCID/validURL, so they hold no quotes or backslashes
// and are safe to emit without escaping.

func q(s string) string { return `"` + s + `"` }

// Info returns realm-wide facts.
func Info() string {
	return `{"version":` + q(version) + `,"artists":` + itoa(artists.Size()) + `,"tracks":` + itoa(nTracks) +
		`,"events":` + itoa(nEvents) + `,"tickets":` + itoa(nTickets) + `,"listeners":` + itoa(listeners.Size()) +
		`,"now":` + itoa64(now()) + `,"frozen":` + boolStr(frozen) + `,"successor":` + q(successor) + `,"admin":` + q(admin.String()) + `}`
}

func trackJSON(t *Track) string {
	var b strings.Builder
	a := getArtist(t.Artist)
	name := ""
	if a != nil {
		name = a.Name
	}
	b.WriteString(`{"id":` + itoa(t.ID) + `,"title":` + q(t.Title) + `,"artist":` + q(t.Artist.String()) +
		`,"artistName":` + q(name) + `,"genre":` + q(t.Genre) + `,"credits":` + q(t.Credits) + `,"cid":` + q(t.CID) +
		`,"license":` + q(t.License) + `,"cmo":` + q(t.CMO) + `,"duration":` + itoa64(t.Duration) +
		`,"likes":` + itoa(t.Likes) + `,"tips":` + itoa64(t.Tips) + `,"supporters":` + itoa(t.Supporters) +
		`,"created":` + itoa64(t.Created) + `,"splits":[`)
	for i, s := range t.Splits {
		if i > 0 {
			b.WriteString(",")
		}
		b.WriteString(`{"to":` + q(s.To.String()) + `,"pct":` + itoa64(s.Pct) + `}`)
	}
	b.WriteString(`]}`)
	return b.String()
}

// TrackJSON returns one playable track.
func TrackJSON(id int) string { return trackJSON(mustTrack(id)) }

// TracksJSON pages through playable tracks, newest first. limit <= 50.
func TracksJSON(offset, limit int) string {
	if limit < 1 || limit > 50 {
		limit = 50
	}
	if offset < 0 {
		offset = 0
	}
	var b strings.Builder
	b.WriteString(`{"total":` + itoa(tracks.Size()) + `,"tracks":[`)
	n := 0
	tracks.ReverseIterateByOffset(offset, limit, func(_ string, v any) bool {
		t := v.(*Track)
		if playable(t) {
			if n > 0 {
				b.WriteString(",")
			}
			b.WriteString(trackJSON(t))
			n++
		}
		return false
	})
	b.WriteString(`]}`)
	return b.String()
}

// ScheduleJSON returns what plays from now until now+horizon seconds
// (<= 7200, at most 60 entries): programmed slots and the rotation between
// them. Clients play entry i from max(0, clock-start) and resync with "now".
func ScheduleJSON(horizon int) string {
	if horizon < 60 || horizon > 7200 {
		horizon = 3600
	}
	ts := now()
	end := ts + int64(horizon)
	var b strings.Builder
	b.WriteString(`{"now":` + itoa64(ts) + `,"entries":[`)
	n := 0
	emit := func(id int, start, stop, offset int64, queued bool, by string) {
		t := getTrack(id)
		if n > 0 {
			b.WriteString(",")
		}
		b.WriteString(`{"track":` + itoa(id) + `,"cid":` + q(t.CID) + `,"title":` + q(t.Title) +
			`,"start":` + itoa64(start) + `,"end":` + itoa64(stop) + `,"offset":` + itoa64(offset) +
			`,"queued":` + boolStr(queued) + `,"by":` + q(by) + `}`)
		n++
	}
	cur := ts
	for cur < end && n < 60 {
		// A programmed slot covering cur?
		var slot *Slot
		next := int64(-1)
		for i := range schedule {
			s := &schedule[i]
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
			if playable(getTrack(slot.Track)) {
				emit(slot.Track, slot.Start, stop, 0, true, slot.By.String())
			}
			cur = stop
			continue
		}
		id, off := rotationAt(cur)
		if id == 0 {
			if next < 0 {
				break
			}
			cur = next
			continue
		}
		t := getTrack(id)
		stop := cur + t.Duration - off
		if next >= 0 && next < stop {
			stop = next // the rotation pauses for the programmed slot
		}
		emit(id, cur-off, stop, off, false, "")
		cur = stop
	}
	b.WriteString(`]}`)
	return b.String()
}

// TicketsOfJSON lists the tickets held by owner.
func TicketsOfJSON(owner address) string {
	var b strings.Builder
	b.WriteString(`[`)
	for i, id := range ownedBy(owner) {
		tk := getTicket(id)
		if i > 0 {
			b.WriteString(",")
		}
		b.WriteString(`{"id":` + itoa(tk.ID) + `,"event":` + itoa(tk.Event) + `,"serial":` + itoa(tk.Serial) +
			`,"attended":` + boolStr(tk.Attended) + `}`)
	}
	b.WriteString(`]`)
	return b.String()
}

// TokenURI returns the GRC721 metadata of a ticket as a data URI, with the
// ticket artwork drawn on the fly (nothing extra is stored).
func TokenURI(tid string) string {
	tk := mustTicket(atoi(tid))
	e := getEvent(tk.Event)
	img := ticketSVG(e, tk.Serial, tk.Attended)
	// ticketSVG returns markdown ![alt](data:...); keep the URI only.
	img = img[strings.Index(img, "(data:")+1 : len(img)-1]
	meta := `{"name":` + q("GnoRadio · "+e.Title+" #"+itoa(tk.Serial)) +
		`,"description":"Billet GnoRadio, dessiné on-chain sur gno.land","image":` + q(img) +
		`,"attributes":[{"trait_type":"event","value":` + itoa(e.ID) + `},{"trait_type":"attended","value":` + boolStr(tk.Attended) + `}]}`
	return "data:application/json;base64," + base64.StdEncoding.EncodeToString([]byte(meta))
}

func boolStr(v bool) string {
	if v {
		return "true"
	}
	return "false"
}
