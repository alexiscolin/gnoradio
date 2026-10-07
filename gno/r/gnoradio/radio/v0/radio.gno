// Package radio runs GnoRadio's live stations: a main station that plays the
// whole catalog and one station per genre. Everyone tuned to a station hears
// the same track at the same second, computed from block time; no streaming
// server is involved. The main station follows a flow of genre sets (flow.gno).
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

	"gno.land/p/gnoradio/text/v0"

	"gno.land/p/gnoradio/blocks/v0"
	"gno.land/p/gnoradio/safe/v0"
	"gno.land/p/gnoradio/store/v0"
	"gno.land/p/nt/avl/v0"
	"gno.land/r/gnoradio/catalog/v0"
)

const (
	MainStation     = 0
	maxQueue        = 30 // upcoming slots per station
	maxPerArtistQ   = 2  // upcoming slots per artist and station
	maxSyncBatch    = 200
	maxRefreshBatch = 50
	pickIngest      = 5    // new catalog tracks a listener pick brings to the stations
	foldAfter       = 3600 // programmed slots ended this long ago fold into the epoch
	queueCooldown   = 3600 // a listener may queue once per station per hour
	maxAheadAir     = 7200 // listener-programmed airtime ahead on a station, seconds
	maxNote         = 40   // characters of a dedication
	noteGrace       = 90   // seconds a dedication waits for the moderation robot (it runs every minute) before it shows
	maxBotHides     = 100  // dedications the moderation robot may hide per day
	hideAfter       = 3    // distinct listeners reporting a dedication hide it
	muteFor         = 7 * 24 * 3600
)

// Slot is a track programmed on a station by a listener, or by the main
// station's flow when By is empty. Dur is captured when queued so later
// catalog edits cannot move the timeline.
type Slot struct {
	Track      int
	Start      int64
	Dur        int64
	By         address
	Note       string // the picker's dedication, checked by p/gnoradio/safe
	NoteAt     int64  // when it was written: it shows noteGrace seconds later
	NoteHidden bool   // hidden by reports, the moderation robot or the admin
}

type station struct {
	id       int
	genre    int // 0 = every genre
	rot      *blocks.List
	live     int // slots with a duration > 0
	epoch    int64
	schedule []Slot // sorted by Start, short (folded as it ages)
}

// Per-track state is compact (an avl node costs about 2KB of deposit): slot
// positions live in one dense record per synced track, queue cooldowns in a
// hashed map.
var (
	admin       address
	frozen      bool
	stations    []*station           // index = station id: 0 main, 1..NumGenres genres
	synced      int                  // catalog track ids 1..synced have been ingested
	noteReports = store.NewMap(1024) // station/start -> reporter addresses (until hidden)
	muted       = store.NewMap(1024) // address -> unix time its dedications are refused until
	modBot      address              // moderation robot (SetModBot); can only HideNote
	hideDay     int64
	hides       int
	lastQ       = store.NewMap(128) // caller address + "/" + station id -> last queue time
	dropped     avl.Tree            // padded station + "/" + padded track -> true (DropSlot, rare)
	homes       = store.NewSeq(128) // track id-1-mainBase -> genre slots "station:slot[,station:slot]"
	mainBase    int                 // ids up to mainBase predate the main rotation (always 0 on chain)
)

func init() {
	admin = unsafe.OriginCaller()
	for i := 0; i <= catalog.NumGenres; i++ {
		stations = append(stations, &station{id: i, genre: i, rot: blocks.New()})
	}
}

// ---- Catalog ingestion (permissionless) ----

// Sync ingests up to max catalog tracks published since the last sync into the
// main station and the station of their genre, then writes the next hour of the
// main station's flow. Anyone may call it; a track that is not playable yet is
// added silent (duration 0) and Refresh turns it on.
func Sync(cur realm, max int) int {
	noPayment()
	notFrozen()
	if max < 1 || max > maxSyncBatch {
		max = maxSyncBatch
	}
	ts := now()
	n := ingest(ts, max)
	stations[MainStation].program(ts)
	return n
}

// ingest adds up to max newly published tracks to the stations.
func ingest(ts int64, max int) int {
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
		home := ""
		if genre >= 1 && genre <= catalog.NumGenres {
			home = itoa(genre) + ":" + itoa(stations[genre].add(id, dur, ts))
		}
		homes.Append(home)
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
// Anyone may call it. A slot the admin dropped stays silent.
func Refresh(cur realm, trackID int) {
	noPayment()
	notFrozen()
	refresh(trackID)
}

// RefreshArtist refreshes up to maxRefreshBatch synced tracks of an artist,
// from offset in the artist's track list, so hiding (or restoring) a whole
// artist takes a few calls instead of one per track. It returns the offset to
// pass next, or 0 when the list is done. Anyone may call it.
func RefreshArtist(cur realm, artistID, offset int) int {
	noPayment()
	notFrozen()
	n := catalog.ArtistTrackCount(artistID)
	if n == 0 && catalog.ArtistName(artistID) == "" {
		panic("radio: unknown artist")
	}
	if offset < 0 || offset > n {
		offset = 0
	}
	for _, id := range catalog.ArtistTrackPage(artistID, offset, maxRefreshBatch) {
		if id >= 1 && id <= synced {
			refresh(id)
		}
	}
	if end := offset + maxRefreshBatch; end < n {
		return end
	}
	return 0
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
	// Only the main station and the genre stations listed in homes hold the
	// track in their rotation, so only those need a slot lookup. Programmed
	// slots are checked on every station: a genre edit must not leave a slot
	// nobody can silence.
	held := homesOf(trackID)
	inGenre := false
	for _, st := range stations {
		belongs := st.id == MainStation || st.id == genre
		if st.id == MainStation || held[st.id] > 0 {
			i, ok := held[st.id]-1, true // homes was decoded once, above
			if st.id == MainStation {
				i, ok = st.slot(trackID)
			}
			if ok {
				d := dur
				if !belongs || dropped.Has(dropKey(st.id, trackID)) {
					d = 0
				}
				st.setDuration(i, d, ts)
				if st.id == genre {
					inGenre = true
				}
			}
		}
		if !playable || !belongs {
			st.dropSlots(trackID, ts)
		}
	}
	if !inGenre && genre >= 1 && genre <= catalog.NumGenres && dur > 0 {
		rec, _ := homes.Get(trackID - 1 - mainBase)
		if rec != "" {
			rec += ","
		}
		homes.Set(trackID-1-mainBase, rec+itoa(genre)+":"+itoa(stations[genre].add(trackID, dur, ts)))
	}
	chain.Emit("Refreshed", "track", itoa(trackID), "playable", strconv.FormatBool(playable))
}

// ---- Programming ----

// Queue programs a track on a station. It starts after the last track a
// listener programmed, or when the song on air ends: nothing is cut. The main
// station's flow moves back to make room. Limits per station: one
// waiting slot per listener, two per artist, a track at most once, 30 upcoming.
func Queue(cur realm, stationID, trackID int) {
	queue(userCaller(cur), stationID, trackID, false, "")
}

// QueueWithNote is Queue with a dedication shown on air ("for Marie!"). It
// must pass p/gnoradio/safe (plain text, no link, no blocked word); listeners
// can report it, and three reports hide it and mute its author for a week.
func QueueWithNote(cur realm, stationID, trackID int, note string) {
	caller := userCaller(cur)
	if until, ok := muted.Get(caller.String()); ok && now() < atoi64(until) {
		panic("radio: your dedications are paused after reports, pick without one")
	}
	if why := safe.Note(note, maxNote); why != "" {
		panic("radio: dedication: " + why)
	}
	queue(caller, stationID, trackID, false, note)
}

// ReportNote flags the dedication of the slot starting at start. The third
// listener to report it hides it at once, with no moderator involved.
func ReportNote(cur realm, stationID int, start int64) {
	caller := userCaller(cur)
	noPayment()
	notFrozen()
	st := mustStation(stationID)
	for i := range st.schedule {
		s := &st.schedule[i]
		if s.Start != start || s.Note == "" || s.NoteHidden {
			continue
		}
		if s.By == caller {
			panic("radio: you cannot report your own dedication")
		}
		key := itoa(st.id) + "/" + itoa64(start)
		by, _ := noteReports.Get(key)
		if strings.Contains(by, caller.String()) {
			panic("radio: you already reported this dedication")
		}
		by += caller.String() + ","
		if strings.Count(by, ",") < hideAfter {
			noteReports.Set(key, by)
			chain.Emit("NoteReported", "station", itoa(st.id), "start", itoa64(start), "by", caller.String())
			return
		}
		noteReports.Remove(key)
		s.NoteHidden = true
		muted.Set(s.By.String(), itoa64(now()+muteFor))
		chain.Emit("NoteHidden", "station", itoa(st.id), "start", itoa64(start), "author", s.By.String())
		return
	}
	panic("radio: no dedication at this time on this station")
}

// HideNote hides a dedication the moderation robot found abusive (it reads
// pending dedications with PendingNotesJSON and asks a moderation model,
// app/netlify/functions/moderate.mts). The robot can only hide, at most
// maxBotHides a day; it cannot mute anyone. reason is shown in the event.
func HideNote(cur realm, stationID int, start int64, reason string) {
	if modBot == "" || cur.Previous().Address() != modBot {
		panic("radio: moderation robot only")
	}
	noPayment()
	if d := now() / 86400; d != hideDay {
		hideDay, hides = d, 0
	}
	if hides >= maxBotHides {
		panic("radio: moderation limit reached for today")
	}
	s := noteSlot(stationID, start)
	hides++
	s.NoteHidden = true
	if len(reason) > 40 {
		reason = reason[:40]
	}
	chain.Emit("NoteHidden", "station", itoa(stationID), "start", itoa64(start), "author", s.By.String(), "by", "robot", "reason", reason)
}

// RestoreNote shows again a dedication hidden by mistake (robot or reports).
// Radio admin only.
func RestoreNote(cur realm, stationID int, start int64) {
	onlyAdmin(cur)
	s := noteSlot(stationID, start)
	s.NoteHidden = false
	noteReports.Remove(itoa(stationID) + "/" + itoa64(start))
	chain.Emit("NoteRestored", "station", itoa(stationID), "start", itoa64(start))
}

// SetModBot names the moderation robot ("" disables it). Radio admin only.
func SetModBot(cur realm, addr address) {
	onlyAdmin(cur)
	modBot = addr
	chain.Emit("ModBotSet", "bot", addr.String())
}

func noteSlot(stationID int, start int64) *Slot {
	st := mustStation(stationID)
	for i := range st.schedule {
		if s := &st.schedule[i]; s.Start == start && s.Note != "" {
			return s
		}
	}
	panic("radio: no dedication at this time on this station")
}

// shownNote is the dedication listeners see: not hidden, past its grace.
func (s Slot) shownNote(ts int64) string {
	if s.Note == "" || s.NoteHidden || ts < s.NoteAt+noteGrace {
		return ""
	}
	return s.Note
}

// CuratorQueue programs a track like Queue but without the per-listener and
// per-artist quotas (the duplicate, genre and queue-size rules still apply).
// Radio admin only.
func CuratorQueue(cur realm, stationID, trackID int) {
	onlyAdmin(cur)
	queue(cur.Previous().Address(), stationID, trackID, true, "")
}

func queue(caller address, stationID, trackID int, curator bool, note string) {
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
		// A track the flow only suggested can be picked: it leaves the flow.
		if s.Track == trackID && s.Start+s.Dur > ts && (s.By != "" || s.Start <= ts) {
			panic("radio: this track is already programmed")
		}
		if s.Start+s.Dur <= ts || s.By == "" {
			continue
		}
		upcoming++
		if !curator && s.Start > ts && s.By == caller {
			panic("radio: you already have a track waiting on this station")
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
		if last, ok := lastQ.Get(ck); ok && ts-atoi64(last) < queueCooldown {
			panic("radio: you can queue one track per station per hour")
		}
		var ahead int64
		for _, s := range st.schedule {
			if end := s.Start + s.Dur; end > ts && s.By != "" {
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
		lastQ.Set(ck, itoa64(ts))
	}
	if !curator && perArtist >= maxPerArtistQ {
		panic("radio: this artist already has 2 tracks in the queue")
	}
	start := ts
	if _, _, off, slotDur, ok := st.rotationAt(ts); ok {
		start = ts + slotDur - off
	}
	// The flow is only a suggestion: the pick airs at once if the flow is on
	// air (after the picks already waiting otherwise), takes the place of the
	// flow's next track (and of this track if the flow had it), and the rest
	// of the flow follows. Played and picked slots stay as they are.
	var kept, flow []Slot
	for _, s := range st.schedule {
		if s.By == "" && s.Start > ts {
			flow = append(flow, s)
			continue
		}
		if s.By == "" && s.Start+s.Dur > ts {
			// A suggested track on air ends now: the app crossfades into the pick.
			s.Dur, start = ts-s.Start, ts
		}
		kept = append(kept, s)
		if end := s.Start + s.Dur; end > ts {
			start = end
		}
	}
	kept = append(kept, Slot{Track: trackID, Start: start, Dur: dur, By: caller, Note: note, NoteAt: ts})
	at, replaced := start+dur, false
	for _, s := range flow {
		if s.Track == trackID || !replaced {
			replaced = replaced || s.Track != trackID
			continue
		}
		s.Start, at = at, at+s.Dur
		kept = append(kept, s)
	}
	st.schedule = kept
	kind := "queue"
	if curator {
		kind = "curator"
	}
	recordActivity(kind, caller, trackID, st.id, start)
	// Picks keep the radio running at no cost to GnoRadio: a few new tracks
	// join the stations and the main flow is topped up (no-ops when current).
	ingest(ts, pickIngest)
	stations[MainStation].program(ts)
	chain.Emit("Queued", "curator", strconv.FormatBool(curator), "station", itoa(st.id), "track", itoa(trackID), "by", caller.String(), "start", itoa64(start))
}

// ---- Reads ----

// NeedsSync reports whether Sync has work: tracks to ingest or less than an
// hour of main flow left. The robot reads it (free) before paying for a Sync.
func NeedsSync() bool {
	return synced < catalog.TrackCount() || stations[MainStation].ahead(now()) < fillAhead/3
}

// NowPlaying returns what a station plays at the last block: the track, the
// offset into it in seconds, and whether a listener programmed it. trackID is
// 0 when nothing plays. Clients should prefer ScheduleJSON and their clock.
func NowPlaying(stationID int) (trackID int, offset int64, queued bool) {
	return mustStation(stationID).onAir(now())
}

// OnAirNote returns the dedication of the programmed slot on air ("" when
// none, or once reports hid it).
func OnAirNote(stationID int) string {
	ts := now()
	for _, s := range mustStation(stationID).schedule {
		if ts >= s.Start && ts < s.Start+s.Dur {
			return s.shownNote(ts)
		}
	}
	return ""
}

// UpNext returns the slots listeners programmed on a station that have not
// started yet.
func UpNext(stationID int) []Slot {
	st := mustStation(stationID)
	ts := now()
	var out []Slot
	for _, s := range st.schedule {
		if s.Start > ts && s.By != "" {
			if _, _, _, ok := catalog.TrackBrief(s.Track); ok {
				s.Note = s.shownNote(ts)
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

// RotationPage lists a station's rotation in order (track ids and durations,
// 0 = silent), paginated, so a successor realm can copy it.
func RotationPage(stationID, offset, limit int) (ids []int, durs []int64) {
	st := mustStation(stationID)
	if limit < 1 || limit > 100 {
		limit = 100
	}
	for i := offset; i >= 0 && i < st.rot.Len() && len(ids) < limit; i++ {
		id, d := st.rot.Slot(i)
		ids, durs = append(ids, id), append(durs, d)
	}
	return ids, durs
}

// StationInfo returns how many tracks rotate on a station and the loop length.
func StationInfo(stationID int) (tracks int, loop int64, queued int) {
	st := mustStation(stationID)
	ts := now()
	for _, s := range st.schedule {
		if s.Start+s.Dur > ts && s.By != "" {
			queued++
		}
	}
	return st.live, st.rot.Total(), queued
}

// Pending returns how many catalog tracks are waiting for Sync.
func Pending() int { return catalog.TrackCount() - synced }

// ---- Admin ----

// DropSlot silences a track in one station's rotation (moderation of last
// resort). It stays silent through Refresh until RestoreSlot. Radio admin only.
func DropSlot(cur realm, stationID, trackID int) {
	onlyAdmin(cur)
	st := mustStation(stationID)
	i, ok := st.slot(trackID)
	if !ok {
		panic("radio: track not in this station's rotation")
	}
	ts := now()
	dropped.Set(dropKey(st.id, trackID), true)
	st.setDuration(i, 0, ts)
	st.dropSlots(trackID, ts)
	chain.Emit("SlotDropped", "station", itoa(st.id), "track", itoa(trackID))
}

// RestoreSlot undoes DropSlot: the track plays again on that station if the
// catalog still allows it. Radio admin only.
func RestoreSlot(cur realm, stationID, trackID int) {
	onlyAdmin(cur)
	st := mustStation(stationID)
	if _, ok := dropped.Remove(dropKey(st.id, trackID)); !ok {
		panic("radio: this slot was not dropped")
	}
	refresh(trackID)
	chain.Emit("SlotRestored", "station", itoa(st.id), "track", itoa(trackID))
}

func dropKey(stationID, trackID int) string { return text.Key(stationID) + "/" + text.Key(trackID) }

// Unqueue removes a track's programmed slots from a station; one on air ends
// now. Radio admin (curator) only.
func Unqueue(cur realm, stationID, trackID int) {
	onlyAdmin(cur)
	st := mustStation(stationID)
	st.dropSlots(trackID, now())
	chain.Emit("Unqueued", "station", itoa(st.id), "track", itoa(trackID))
}

// Unmute lets a muted listener dedicate again before the week ends, e.g.
// after reports by throwaway wallets. Radio admin only.
func Unmute(cur realm, who address) {
	onlyAdmin(cur)
	if !muted.Remove(who.String()) {
		panic("radio: this address is not muted")
	}
	chain.Emit("Unmuted", "address", who.String())
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
				return s.Track, ts - s.Start, s.By != ""
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

// add appends a track at the end of the loop and returns its slot; listeners do not move.
func (st *station) add(trackID int, dur int64, ts int64) int {
	p := st.pos(ts)
	i := st.rot.Append(trackID, dur)
	if dur > 0 {
		st.live++
	}
	st.anchor(ts, p)
	return i
}

// slot returns a track's index in this station's rotation. The main station
// keeps no index: Sync appends every track there in id order, so track id
// sits at id-1. Genre stations look the slot up in homes.
func (st *station) slot(trackID int) (int, bool) {
	if st.id == MainStation {
		i := trackID - 1 - mainBase
		if i >= 0 && i < st.rot.Len() {
			return i, true
		}
		return 0, false
	}
	i, ok := homesOf(trackID)[st.id]
	return i - 1, ok
}

// homesOf maps the genre stations whose rotation holds a track to its slot+1.
func homesOf(trackID int) map[int]int {
	rec, _ := homes.Get(trackID - 1 - mainBase)
	out := map[int]int{}
	if rec == "" {
		return out
	}
	for _, p := range strings.Split(rec, ",") {
		st, slot, _ := strings.Cut(p, ":")
		out[atoi(st)] = atoi(slot) + 1
	}
	return out
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
		noteReports.Remove(itoa(st.id) + "/" + itoa64(st.schedule[i].Start))
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
				// a later pick may reuse this start: its reports go too
				noteReports.Remove(itoa(st.id) + "/" + itoa64(s.Start))
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

func itoa(n int) string     { return strconv.Itoa(n) }
func itoa64(n int64) string { return strconv.FormatInt(n, 10) }
func atoi(s string) int {
	n, _ := strconv.Atoi(s)
	return n
}

func atoi64(s string) int64 {
	n, _ := strconv.ParseInt(s, 10, 64)
	return n
}
