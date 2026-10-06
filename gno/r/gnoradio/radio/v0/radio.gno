// Package radio runs GnoRadio's live stations: a main station that plays the
// whole catalog and one station per genre. Everyone tuned to a station hears
// the same track at the same second, computed from block time; no streaming
// server is involved.
//
// Each station has a rotation (every playable track of its genre, looping)
// stored in fixed-size blocks so that every operation costs the same whatever
// the catalog size, and a short queue of tracks programmed by listeners.
// While a programmed track plays the rotation pauses, then resumes where it
// was. Adding, removing or editing a track never makes listeners jump.
package radio

import (
	"chain"
	"chain/runtime/unsafe"
	"strconv"
	"strings"
	"time"

	"gno.land/p/gnoradio/blocks/v0"
	"gno.land/p/nt/avl/v0"
	"gno.land/r/gnoradio/catalog/v0"
)

const (
	MainStation   = 0
	maxQueue      = 30 // upcoming slots per station
	maxPerArtistQ = 2  // upcoming slots per artist and station
	maxSyncBatch  = 200
	foldAfter     = 3600 // programmed slots ended this long ago fold into the epoch
	queueCooldown = 3600 // a listener may queue once per station per hour
	maxAheadAir   = 7200 // listener-programmed airtime ahead on a station, seconds
)

// Slot is a track programmed on a station by a listener. Dur is captured when
// queued so later catalog edits cannot move the timeline.
type Slot struct {
	Track int
	Start int64
	Dur   int64
	By    address
}

type station struct {
	id       int
	genre    int // 0 = every genre
	rot      *blocks.List
	slotOf   avl.Tree // padded track id -> int slot index in rot
	live     int      // slots with a duration > 0
	epoch    int64
	schedule []Slot // sorted by Start, short (folded as it ages)
}

var (
	admin    address
	frozen   bool
	stations []*station // index = station id: 0 main, 1..NumGenres genres
	synced   int        // catalog track ids 1..synced have been ingested
	lastQ    avl.Tree   // caller address + "/" + station id -> int64 last queue time
)

func init() {
	admin = unsafe.OriginCaller()
	for i := 0; i <= catalog.NumGenres; i++ {
		stations = append(stations, &station{id: i, genre: i, rot: blocks.New()})
	}
}

// ---- Catalog ingestion (permissionless) ----

// Sync ingests up to max catalog tracks published since the last sync into the
// main station and the station of their genre. Anyone may call it; a track
// that is not playable yet is added silent (duration 0) and Refresh turns it on.
func Sync(cur realm, max int) int {
	noPayment()
	notFrozen()
	if max < 1 || max > maxSyncBatch {
		max = maxSyncBatch
	}
	ts := now()
	from := synced + 1
	last := catalog.TrackCount()
	if last > synced+max {
		last = synced + max
	}
	for id := from; id <= last; id++ {
		_, genre, dur, playable := catalog.TrackBrief(id)
		if !playable {
			dur = 0
		}
		stations[MainStation].add(id, dur, ts)
		if genre >= 1 && genre <= catalog.NumGenres {
			stations[genre].add(id, dur, ts)
		}
	}
	n := last - synced
	if n > 0 {
		synced = last
		chain.Emit("Synced", "from", itoa(from), "to", itoa(last))
	}
	return n
}

// Refresh re-reads a track from the catalog and updates its rotation slots:
// a hidden track goes silent, a restored one comes back, an edited duration is
// applied. Programmed slots of a track that is no longer playable are dropped.
// Anyone may call it. Prune is the same call, kept for readability.
func Refresh(cur realm, trackID int) {
	noPayment()
	notFrozen()
	refresh(trackID)
}

func Prune(cur realm, trackID int) {
	noPayment()
	notFrozen()
	refresh(trackID)
}

func refresh(trackID int) {
	if trackID < 1 || trackID > synced {
		panic("radio: track not synced yet")
	}
	_, genre, dur, playable := catalog.TrackBrief(trackID)
	if !playable {
		dur = 0
	}
	ts := now()
	// Visit every station holding the track, not only its current genre: a
	// genre edit must not leave a slot nobody can silence.
	for _, st := range stations {
		belongs := st.id == MainStation || st.id == genre
		if i, ok := st.slotOf.Get(key(trackID)).(int); ok {
			d := dur
			if !belongs {
				d = 0
			}
			st.setDuration(i, d, ts)
		} else if belongs && st.id != MainStation && dur > 0 {
			st.add(trackID, dur, ts)
		}
		if !playable || !belongs {
			st.dropSlots(trackID, ts)
		}
	}
	chain.Emit("Refreshed", "track", itoa(trackID), "playable", strconv.FormatBool(playable))
}

// ---- Programming ----

// Queue programs a track on a station. It starts after the last programmed
// track, or when the song on air ends: nothing is cut. Limits per station: one
// waiting slot per listener, two per artist, a track at most once, 30 upcoming.
func Queue(cur realm, stationID, trackID int) {
	queue(userCaller(cur), stationID, trackID, false)
}

// CuratorQueue programs a track like Queue but without the per-listener and
// per-artist quotas (the duplicate, genre and queue-size rules still apply).
// Radio admin only.
func CuratorQueue(cur realm, stationID, trackID int) {
	onlyAdmin(cur)
	queue(cur.Previous().Address(), stationID, trackID, true)
}

func queue(caller address, stationID, trackID int, curator bool) {
	noPayment()
	notFrozen()
	st := mustStation(stationID)
	artistID, genre, dur, playable := catalog.TrackBrief(trackID)
	if !playable {
		panic("radio: unknown track")
	}
	if st.genre != 0 && genre != st.genre {
		panic("radio: this track does not belong to this station")
	}
	ts := now()
	st.fold(ts)
	upcoming, perArtist := 0, 0
	for _, s := range st.schedule {
		if s.Start+s.Dur <= ts {
			continue
		}
		upcoming++
		if !curator && s.Start > ts && s.By == caller {
			panic("radio: you already have a track waiting on this station")
		}
		if s.Track == trackID {
			panic("radio: this track is already programmed")
		}
		if a, _, _, _ := catalog.TrackBrief(s.Track); a == artistID {
			perArtist++
		}
	}
	if upcoming >= maxQueue {
		panic("radio: the queue is full, try again later")
	}
	if !curator {
		ck := caller.String() + "/" + itoa(st.id)
		if last, ok := lastQ.Get(ck).(int64); ok && ts-last < queueCooldown {
			panic("radio: you can queue one track per station per hour")
		}
		var ahead int64
		for _, s := range st.schedule {
			if end := s.Start + s.Dur; end > ts {
				if s.Start > ts {
					ahead += s.Dur
				} else {
					ahead += end - ts
				}
			}
		}
		if ahead+dur > maxAheadAir {
			panic("radio: this station is programmed two hours ahead, try again later")
		}
		lastQ.Set(ck, ts)
	}
	if !curator && perArtist >= maxPerArtistQ {
		panic("radio: this artist already has 2 tracks in the queue")
	}
	start := ts
	if n := len(st.schedule); n > 0 && st.schedule[n-1].Start+st.schedule[n-1].Dur > ts {
		start = st.schedule[n-1].Start + st.schedule[n-1].Dur
	} else if _, _, off, slotDur, ok := st.rotationAt(ts); ok {
		start = ts + slotDur - off
	}
	st.schedule = append(st.schedule, Slot{Track: trackID, Start: start, Dur: dur, By: caller})
	kind := "queue"
	if curator {
		kind = "curator"
	}
	recordActivity(kind, caller, trackID, st.id, start)
	chain.Emit("Queued", "curator", strconv.FormatBool(curator), "station", itoa(st.id), "track", itoa(trackID), "by", caller.String(), "start", itoa64(start))
}

// ---- Reads ----

// NowPlaying returns what a station plays at the last block: the track, the
// offset into it in seconds, and whether a listener programmed it. trackID is
// 0 when nothing plays. Clients should prefer ScheduleJSON and their clock.
func NowPlaying(stationID int) (trackID int, offset int64, queued bool) {
	return mustStation(stationID).onAir(now())
}

// UpNext returns the programmed slots of a station that have not started yet.
func UpNext(stationID int) []Slot {
	st := mustStation(stationID)
	ts := now()
	var out []Slot
	for _, s := range st.schedule {
		if s.Start > ts {
			if _, _, _, ok := catalog.TrackBrief(s.Track); ok {
				out = append(out, s)
			}
		}
	}
	return out
}

// StationCount returns the number of stations (ids 0..StationCount()-1).
func StationCount() int { return len(stations) }

// StationName is "Main" for the main station, else the genre name.
func StationName(stationID int) string {
	st := mustStation(stationID)
	if st.genre == 0 {
		return "Main"
	}
	return catalog.GenreName(st.genre)
}

// StationInfo returns how many tracks rotate on a station and the loop length.
func StationInfo(stationID int) (tracks int, loop int64, queued int) {
	st := mustStation(stationID)
	ts := now()
	for _, s := range st.schedule {
		if s.Start+s.Dur > ts {
			queued++
		}
	}
	return st.live, st.rot.Total(), queued
}

// Pending returns how many catalog tracks are waiting for Sync.
func Pending() int { return catalog.TrackCount() - synced }

// ---- Admin ----

// DropSlot silences a track in one station's rotation (moderation of last
// resort; Refresh brings it back if it still belongs there). Radio admin only.
func DropSlot(cur realm, stationID, trackID int) {
	onlyAdmin(cur)
	st := mustStation(stationID)
	i, ok := st.slotOf.Get(key(trackID)).(int)
	if !ok {
		panic("radio: track not in this station's rotation")
	}
	ts := now()
	st.setDuration(i, 0, ts)
	st.dropSlots(trackID, ts)
	chain.Emit("SlotDropped", "station", itoa(st.id), "track", itoa(trackID))
}

// Unqueue removes a track's programmed slots from a station; one on air ends
// now. Radio admin (curator) only.
func Unqueue(cur realm, stationID, trackID int) {
	onlyAdmin(cur)
	st := mustStation(stationID)
	st.dropSlots(trackID, now())
	chain.Emit("Unqueued", "station", itoa(st.id), "track", itoa(trackID))
}

func TransferAdmin(cur realm, to address) {
	onlyAdmin(cur)
	if !to.IsValid() {
		panic("radio: invalid address")
	}
	chain.Emit("AdminTransferred", "from", admin.String(), "to", to.String())
	admin = to
}

// Freeze stops every write, e.g. during a migration.
func Freeze(cur realm, on bool) {
	onlyAdmin(cur)
	frozen = on
	chain.Emit("Frozen", "on", strconv.FormatBool(on))
}

// ---- Station internals ----

// paused is the airtime taken by programmed slots before ts.
func (st *station) paused(ts int64) int64 {
	var p int64
	for _, s := range st.schedule {
		if ts <= s.Start {
			break
		}
		if ts >= s.Start+s.Dur {
			p += s.Dur
		} else {
			p += ts - s.Start
		}
	}
	return p
}

// pos is the position in the rotation loop at ts.
func (st *station) pos(ts int64) int64 {
	total := st.rot.Total()
	if total == 0 {
		return 0
	}
	p := (ts - st.epoch - st.paused(ts)) % total
	if p < 0 {
		p += total
	}
	return p
}

// anchor sets the epoch so that the rotation is at position p at ts.
func (st *station) anchor(ts, p int64) {
	st.epoch = ts - st.paused(ts) - p
}

func (st *station) rotationAt(ts int64) (slot, track int, offset, dur int64, ok bool) {
	if st.rot.Total() == 0 {
		return 0, 0, 0, 0, false
	}
	slot, track, offset, ok = st.rot.Find(st.pos(ts))
	if !ok {
		return 0, 0, 0, 0, false
	}
	_, dur = st.rot.Slot(slot)
	return slot, track, offset, dur, true
}

func (st *station) onAir(ts int64) (int, int64, bool) {
	for _, s := range st.schedule {
		if ts >= s.Start && ts < s.Start+s.Dur {
			if _, _, _, ok := catalog.TrackBrief(s.Track); ok {
				return s.Track, ts - s.Start, true
			}
			return 0, 0, false // a removed programmed slot plays silence until its end
		}
	}
	_, track, off, _, ok := st.rotationAt(ts)
	if !ok {
		return 0, 0, false
	}
	if _, _, _, playable := catalog.TrackBrief(track); !playable {
		return 0, 0, false // hidden but not refreshed yet: silence, never its title
	}
	return track, off, false
}

// add appends a track at the end of the loop; listeners do not move.
func (st *station) add(trackID int, dur int64, ts int64) {
	p := st.pos(ts)
	i := st.rot.Append(trackID, dur)
	st.slotOf.Set(key(trackID), i)
	if dur > 0 {
		st.live++
	}
	st.anchor(ts, p)
}

// setDuration changes slot i and re-anchors so the song on air keeps playing
// (or, if it is the one removed, the next one starts now). O(n/Size + Size).
func (st *station) setDuration(i int, d int64, ts int64) {
	_, old := st.rot.Slot(i)
	if old == d {
		return
	}
	p := st.pos(ts)
	prefix := st.rot.PrefixBefore(i)
	np := p
	switch {
	case st.rot.Total() == 0 || p < prefix:
		// the change is ahead of the listeners
	case p >= prefix+old:
		np = p - old + d // the change is behind them
	default:
		// the slot on air changes
		if p-prefix >= d {
			np = prefix + d // cut short: the next track starts now
		}
	}
	st.rot.SetDuration(i, d)
	if old == 0 && d > 0 {
		st.live++
	} else if old > 0 && d == 0 {
		st.live--
	}
	if total := st.rot.Total(); total > 0 {
		st.anchor(ts, np%total)
	}
}

// fold moves programmed slots that ended long ago into the epoch.
func (st *station) fold(ts int64) {
	i := 0
	for i < len(st.schedule) && st.schedule[i].Start+st.schedule[i].Dur <= ts-foldAfter {
		st.epoch += st.schedule[i].Dur
		i++
	}
	if i > 0 {
		st.schedule = append([]Slot(nil), st.schedule[i:]...)
	}
}

// dropSlots removes a track's programmed slots; one on air ends now.
func (st *station) dropSlots(trackID int, ts int64) {
	var out []Slot
	changed := false
	for _, s := range st.schedule {
		if s.Track == trackID {
			if s.Start >= ts {
				changed = true
				continue
			}
			if s.Start+s.Dur > ts {
				s.Dur = ts - s.Start
				changed = true
			}
		}
		out = append(out, s)
	}
	if changed {
		st.schedule = out
	}
}

// ---- helpers ----

func now() int64 { return time.Now().Unix() }

func mustStation(id int) *station {
	if id < 0 || id >= len(stations) {
		panic("radio: unknown station")
	}
	return stations[id]
}

func userCaller(cur realm) address {
	if !cur.Previous().IsUserCall() {
		panic("radio: call this directly from your wallet")
	}
	return cur.Previous().Address()
}

func onlyAdmin(cur realm) {
	if cur.Previous().Address() != admin {
		panic("radio: admin only")
	}
	noPayment()
}

func notFrozen() {
	if frozen {
		panic("radio: GnoRadio is paused for maintenance")
	}
}

func noPayment() {
	if len(unsafe.OriginSend()) != 0 {
		panic("radio: this action does not take coins")
	}
}

func key(id int) string {
	s := strconv.Itoa(id)
	return strings.Repeat("0", 10-len(s)) + s
}

func itoa(n int) string     { return strconv.Itoa(n) }
func itoa64(n int64) string { return strconv.FormatInt(n, 10) }
