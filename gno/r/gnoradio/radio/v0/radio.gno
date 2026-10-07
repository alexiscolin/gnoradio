// Package radio runs GnoRadio's live stations: a main station that plays the
// whole catalog, one station per genre, "New this week" (the newest tracks)
// and "Listeners' choice" (the tracks listeners picked). Everyone tuned to a
// station hears the same track at the same second, computed from block time;
// no streaming server is involved. The main station follows a flow of genre
// sets (flow.gno).
//
// Each station has a rotation (every playable track of its genre, looping)
// stored in fixed-size blocks so that every operation costs the same whatever
// the catalog size, and a short queue of tracks programmed by listeners.
// While a programmed track plays the rotation pauses, then resumes where it
// was. Adding, removing or editing a track never makes listeners jump.
package radio

import (
	"chain"
	"chain/runtime"
	"chain/runtime/unsafe"
	"crypto/ed25519"
	"encoding/hex"
	"strconv"
	"strings"
	"time"

	"gno.land/p/gnoradio/text/v0"

	"gno.land/p/gnoradio/blocks/v0"
	"gno.land/p/gnoradio/safe/v0"
	"gno.land/p/gnoradio/store/v0"
	"gno.land/r/gnoradio/catalog/v0"
)

const (
	MainStation     = 0
	NewStation      = catalog.NumGenres + 1 // the newest newCap ingested tracks
	ChoiceStation   = catalog.NumGenres + 2 // the last choiceCap distinct listener picks
	newCap          = 300
	choiceCap       = 500
	maxQueue        = 30 // upcoming slots per station
	maxPerArtistQ   = 2  // upcoming slots per artist and station
	maxSyncBatch    = 200
	maxRefreshBatch = 50
	pickIngest      = 2             // new catalog tracks a listener pick brings to the stations
	pickFillBelow   = fillAhead / 3 // a pick tops up the main flow below this much programmed ahead (NeedsSync's mark: the robot is not needed while picks come)
	pickFill        = 4             // and writes at most this many flow slots (the storage a pick may pay for)
	foldAfter       = 3600          // programmed slots ended this long ago fold into the epoch
	queueCooldown   = 3600          // a listener may queue once per station per hour
	replayGap       = 3 * 3600      // a track picked on a station cannot be picked there again for 3 hours, by anyone
	maxAheadAir     = 7200          // listener-programmed airtime ahead on a station, seconds
	maxNote         = 40            // characters of a dedication
	noteCertLife    = 900           // seconds a moderation certificate may still have to live
	hideAfter       = 3             // distinct listeners who picked before reporting a dedication hide it
	muteFor         = 7 * 24 * 3600 // a second hidden dedication within this time mutes its author this long
	maxSchedule     = 120           // slots a station keeps (played, picked and flow); the flow stops filling there
	bookMin         = 15 * 60       // a pick booked for a time: at least this far ahead
	bookMax         = 24 * 3600     // and at most this far
	maxBookedHour   = 4             // booked picks per station and clock hour (UTC)
)

// Slot is a track programmed on a station by a listener, or by the main
// station's flow when By is empty. Dur is captured when queued so later
// catalog edits cannot move the timeline.
type Slot struct {
	Track      int
	Start      int64
	Dur        int64
	By         address
	Note       string // the picker's dedication, checked by p/gnoradio/safe and the moderation robot
	NoteHidden bool   // hidden by reports or the admin
	Pay        int64  // a sponsored pick: the ugnot its artist reserved to refund the picker (sponsor.gno)
	At         int64  // a booked pick: the time asked (unix); it starts at the first track boundary at or after it
}

type station struct {
	id       int
	genre    int // 0 = every genre
	rot      *blocks.List
	live     int // slots with a duration > 0
	epoch    int64
	schedule []Slot // sorted by Start, short (folded as it ages)
	ring     int    // New and Choice: joins so far; the slot reused next is ring % keep
}

// Per-track state is compact (an avl node costs about 2KB of deposit): slot
// positions live in one dense record per synced track, queue cooldowns in a
// hashed map.
var (
	admin       address
	frozen      bool
	successor   string               // realm path of the next version, once announced
	stations    []*station           // index = station id: 0 main, 1..NumGenres genres, then New, Choice
	synced      int                  // catalog track ids 1..synced have been ingested
	noteReports = store.NewMap(1024) // station/start -> reporter addresses (until hidden)
	muted       = store.NewMap(1024) // address -> unix time its dedications are refused until
	strikes     = store.NewMap(1024) // address -> unix time one of its dedications was last hidden
	noteKey     []byte               // Ed25519 public key of the moderation robot (SetModBot); none: no dedications
	verifySig   = ed25519.Verify     // a test seam
	// One short record per station rather than one entry per (station,
	// track): an entry costs a listener about 1.5KB of deposit, a few bytes
	// here. The per-listener cooldown lives in the curator record (lastPickAt).
	lastPick = store.NewMap(64) // station id -> track and time of its picks within replayGap (lastPicked)
	dropped  = store.NewMap(256)   // padded station + "/" + padded track -> "1" (DropSlot, rare)
	homes    = store.NewSeq(128)   // track id-1 -> genre, New and Choice slots "station:slot[,station:slot]"
)

func init() {
	admin = unsafe.OriginCaller()
	stations = newStations()
}

// newStations returns Main, the genre stations, New and Choice (genre 0: any
// track may be queued there).
func newStations() []*station {
	var out []*station
	for i := 0; i <= ChoiceStation; i++ {
		g := i
		if i > catalog.NumGenres {
			g = 0
		}
		out = append(out, &station{id: i, genre: g, rot: blocks.New()})
	}
	return out
}

// ---- Catalog ingestion (permissionless) ----

// Sync ingests up to max catalog tracks published since the last sync into the
// main station and the station of their genre, then writes the next hour of the
// main station's flow. The catalog's most liked tracks join Listeners' choice.
// Anyone may call it; a track that is not playable yet is added silent
// (duration 0) and Refresh turns it on.
func Sync(cur realm, max int) int {
	noPayment()
	notFrozen()
	if max < 1 || max > maxSyncBatch {
		max = maxSyncBatch
	}
	ts := now()
	n := ingest(ts, max)
	for _, r := range catalog.TopLiked() {
		if id := atoi(r.Key); id <= synced {
			if _, _, dur, ok := catalog.TrackBrief(id); ok {
				choose(id, dur, ts)
			}
		}
	}
	stations[MainStation].program(ts, maxFill)
	return n
}

// ingest adds up to max newly published tracks to the stations, New included.
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
		homes.Append(homeAdd(home, stations[NewStation].join(id, dur, ts, newCap))) // index id-1
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
	refresh(cur, trackID)
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
			refresh(cur, id)
		}
	}
	if end := offset + maxRefreshBatch; end < n {
		return end
	}
	return 0
}

func refresh(cur realm, trackID int) {
	if trackID < 1 || trackID > synced {
		panic("radio: track not synced yet")
	}
	_, genre, dur, playable := catalog.TrackBrief(trackID)
	if !playable {
		dur = 0
	}
	ts := now()
	// Only the main station and the stations listed in homes hold the track
	// in their rotation, so only those need a slot lookup. Programmed slots
	// are checked on every station: a genre edit must not leave a slot nobody
	// can silence.
	held := homesOf(trackID)
	inGenre := false
	for _, st := range stations {
		belongs := st.genre == 0 || st.id == genre
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
			release(cur, st.dropSlots(trackID, ts))
		}
	}
	if !inGenre && genre >= 1 && genre <= catalog.NumGenres && dur > 0 {
		rec, _ := homes.Get(trackID - 1)
		homes.Set(trackID-1, homeAdd(rec, itoa(genre)+":"+itoa(stations[genre].add(trackID, dur, ts))))
	}
	chain.Emit("Refreshed", "track", itoa(trackID), "playable", strconv.FormatBool(playable))
}

// ---- Programming ----

// Queue programs a track on a station and adds it to Listeners' choice. It
// starts after the last track a listener programmed, or when the song on air
// ends: nothing is cut. The main station's flow moves back to make room.
// Limits per station: one waiting slot per listener, two per artist, a track
// at most once, 30 upcoming.
func Queue(cur realm, stationID, trackID int) {
	queue(cur, userCaller(cur), stationID, trackID, false, false, "", 0)
}

// QueueAt is Queue for a chosen time: at (unix, UTC) between 15 minutes and
// 24 hours from now; 0 is Queue. The pick starts at the first track boundary
// at or after at (on Main, at at: the flow's track fades out as for any
// pick), unless listener picks fill that moment, then right after them. It
// keeps its time: later picks go before it only if they end by then, else
// after it. Every Queue rule applies, the 3-hour replay gap around at; the
// 2-hour airtime cap does not, but at most 4 picks are booked per station and
// clock hour.
func QueueAt(cur realm, stationID, trackID int, at int64) {
	queue(cur, userCaller(cur), stationID, trackID, false, false, "", at)
}

// QueueWithNote is Queue with a dedication shown on air ("for Marie!"). The
// moderation robot judges it before the transaction (word filter and a
// moderation model, app/netlify/functions/dedication.mts) and signs
// NoteMessage(note, expires): the listener sends that certificate and pays
// their own gas, so a dedication shows at once and costs GnoRadio nothing. It
// must also pass p/gnoradio/safe (plain text, no link, no blocked word).
// Listeners can report it: three reports hide it and give its author a strike;
// a second hidden dedication within a week pauses their dedications for a
// week (ReportNote).
func QueueWithNote(cur realm, stationID, trackID int, note string, expires int64, sigHex string) {
	QueueWithNoteAt(cur, stationID, trackID, 0, note, expires, sigHex)
}

// QueueWithNoteAt is QueueWithNote for a chosen time (see QueueAt; 0: now).
func QueueWithNoteAt(cur realm, stationID, trackID int, at int64, note string, expires int64, sigHex string) {
	caller := userCaller(cur)
	if until, ok := muted.Get(caller.String()); ok && now() < atoi64(until) {
		panic("radio: your dedications are paused after reports, pick without one")
	}
	if why := safe.Note(note, maxNote); why != "" {
		panic("radio: dedication: " + why)
	}
	checkNote(caller, stationID, note, expires, sigHex)
	queue(cur, caller, stationID, trackID, false, false, note, at)
}

// NoteMessage is what the moderation robot signs to approve a dedication by
// author on stationID until expires (unix seconds), on this chain only:
// "gnoradio-note|<chain id>|<author>|<station>|<note>|<expires>". A
// certificate seen in a public transaction serves no other wallet or station.
func NoteMessage(author address, stationID int, note string, expires int64) string {
	return "gnoradio-note|" + runtime.ChainID() + "|" + author.String() + "|" + itoa(stationID) + "|" + note + "|" + itoa64(expires)
}

func checkNote(author address, stationID int, note string, expires int64, sigHex string) {
	if len(noteKey) == 0 {
		panic("radio: dedications are paused, pick without one")
	}
	if ts := now(); expires <= ts || expires > ts+noteCertLife {
		panic("radio: the dedication check expired, send it again")
	}
	sig, err := hex.DecodeString(sigHex)
	if err != nil || len(sig) != 64 || !verifySig(noteKey, []byte(NoteMessage(author, stationID, note, expires)), sig) {
		panic("radio: this dedication was not approved, send it again")
	}
}

// struckMark starts the noteReports value of a hidden dedication: the strike
// time it gave its author, then the one before ("" none).
const struckMark = "struck:"

// ReportNote flags the dedication of the slot starting at start. Only a
// listener who picked a track before may report; the third such listener
// hides it at once, with no moderator involved. A first hidden dedication is
// a strike; a second within muteFor pauses its author's dedications for
// muteFor, so throwaway reports alone cannot silence someone for a week.
func ReportNote(cur realm, stationID int, start int64) {
	caller := userCaller(cur)
	noPayment()
	notFrozen()
	s := noteSlot(stationID, start)
	if s.NoteHidden {
		panic("radio: no dedication at this time on this station")
	}
	if s.By == caller {
		panic("radio: you cannot report your own dedication")
	}
	if CuratorOf(caller).Picks == 0 {
		panic("radio: pick a track first, then you can report dedications")
	}
	key := itoa(stationID) + "/" + itoa64(start)
	by, _ := noteReports.Get(key)
	if strings.Contains(by, caller.String()) {
		panic("radio: you already reported this dedication")
	}
	by += caller.String() + ","
	if strings.Count(by, ",") < hideAfter {
		noteReports.Set(key, by)
		chain.Emit("NoteReported", "station", itoa(stationID), "start", itoa64(start), "by", caller.String())
		return
	}
	s.NoteHidden = true
	ts, author := now(), s.By.String()
	last, struck := strikes.Get(author)
	mute := struck && ts-atoi64(last) < muteFor
	if mute {
		muted.Set(author, itoa64(ts+muteFor))
	}
	strikes.Set(author, itoa64(ts))
	// The hidden note keeps the strike it gave and the one before, so that
	// RestoreNote takes back this strike only.
	noteReports.Set(key, struckMark+itoa64(ts)+":"+last)
	chain.Emit("NoteHidden", "station", itoa(stationID), "start", itoa64(start), "author", author, "muted", strconv.FormatBool(mute))
}

// RestoreNote shows again a dedication hidden by reports by mistake and
// clears its author's strike (Unmute lifts a pause). Radio admin only.
func RestoreNote(cur realm, stationID int, start int64) {
	onlyAdmin(cur)
	s := noteSlot(stationID, start)
	if !s.NoteHidden {
		panic("radio: this dedication is not hidden") // its pending reports stay
	}
	s.NoteHidden = false
	key := itoa(stationID) + "/" + itoa64(start)
	// A wrong hide is no strike: take back the one it gave, if it is still
	// the author's last, and keep any earlier one.
	if rec, _ := noteReports.Get(key); strings.HasPrefix(rec, struckMark) {
		gave, before, _ := strings.Cut(rec[len(struckMark):], ":")
		author := s.By.String()
		if last, _ := strikes.Get(author); last == gave {
			if before == "" {
				strikes.Remove(author)
			} else {
				strikes.Set(author, before)
			}
		}
	}
	noteReports.Remove(key)
	chain.Emit("NoteRestored", "station", itoa(stationID), "start", itoa64(start))
}

// SetModBot names the moderation robot by its Ed25519 public key in hex
// ("" turns dedications off). Radio admin only.
func SetModBot(cur realm, pubKeyHex string) {
	onlyAdmin(cur)
	key, err := hex.DecodeString(pubKeyHex)
	if err != nil || (len(key) != 0 && len(key) != 32) {
		panic("radio: the robot key is a 32-byte Ed25519 public key in hex")
	}
	noteKey = key
	chain.Emit("ModBotSet", "key", pubKeyHex)
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

// shownNote is the dedication listeners see ("" once hidden).
func (s Slot) shownNote() string {
	if s.NoteHidden {
		return ""
	}
	return s.Note
}

// CuratorQueue programs a track like Queue but without the per-listener and
// per-artist quotas (the duplicate, genre and queue-size rules still apply).
// Radio admin only.
func CuratorQueue(cur realm, stationID, trackID int) {
	onlyAdmin(cur)
	queue(cur, cur.Previous().Address(), stationID, trackID, true, false, "", 0)
}

func queue(cur realm, caller address, stationID, trackID int, curator, sponsored bool, note string, at int64) {
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
	if st.id == NewStation && trackID <= synced-newCap {
		panic("radio: only new tracks can be picked on New this week")
	}
	ts := now()
	airs := ts // when the pick is meant to air
	if at != 0 {
		if at < ts+bookMin || at > ts+bookMax {
			panic("radio: book a time between 15 minutes and 24 hours from now")
		}
		airs = at
	}
	st.fold(ts)
	start := st.place(ts, dur, at)
	// The replay gap counts from when the pick really airs: a pick for now
	// may wait up to 2 hours behind others, a booked one keeps its time.
	gapAt := airs
	if at == 0 {
		gapAt = start
	}
	upcoming, perArtist, booked := 0, 0, 0
	for _, s := range st.schedule {
		// A track the flow only suggested can be picked: it leaves the flow.
		// A listener slot of the track blocks it within the replay gap.
		if s.Track == trackID && s.Start+s.Dur > ts && (s.By != "" && abs64(s.Start-gapAt) < replayGap || s.By == "" && s.Start <= ts && at == 0) {
			panic("radio: this track is already programmed")
		}
		// A booked pick enters lastPick when folded, an hour after it ends:
		// until then its slot keeps the replay gap.
		if s.Track == trackID && s.At > 0 && s.By != "" && s.Start+s.Dur <= ts && !curator && gapAt-s.Start < replayGap {
			panic("radio: this track was picked here less than 3 hours ago, pick another one")
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
		if at != 0 && s.At/3600 == at/3600 {
			booked++
		}
	}
	if upcoming >= maxQueue {
		panic("radio: the queue is full, try again later")
	}
	if booked >= maxBookedHour {
		panic("radio: 4 picks are already booked for that hour here, choose another time")
	}
	// No track on a loop: many wallets cannot replay one song for hours.
	if last, ok := lastPicked(st.id, trackID); ok && !curator && gapAt-last < replayGap {
		panic("radio: this track was picked here less than 3 hours ago, pick another one")
	}
	if !curator {
		if last := lastPickAt(caller, st.id); last > 0 && ts-last < queueCooldown {
			panic("radio: you can queue one track per station per hour")
		}
		var ahead int64
		for _, s := range st.schedule {
			if end := s.Start + s.Dur; end > ts && s.By != "" && s.At == 0 {
				ahead += end - max64(s.Start, ts)
			}
		}
		if at == 0 && ahead+dur > maxAheadAir {
			panic("radio: this station is programmed two hours ahead, try again later")
		}
	}
	if !curator && perArtist >= maxPerArtistQ {
		panic("radio: this artist already has 2 tracks in the queue")
	}
	if sponsored {
		sponsorQuota(st, artistID, dur, airs)
	}
	if at == 0 {
		setPicked(st.id, trackID, start) // a booked pick is in the schedule; fold records it once aired
	}
	var pay int64
	if sponsored {
		pay = reserve(cur, caller, st.id, trackID, start, dur, Slot{Start: start, Dur: dur, At: at}.held())
	}
	st.put(Slot{Track: trackID, Start: start, Dur: dur, By: caller, Note: note, Pay: pay, At: at})
	kind := "queue"
	if curator {
		kind = "curator"
	} else if sponsored {
		kind = "sponsored"
	}
	recordActivity(kind, caller, trackID, st.id, start)
	// Picks keep the radio running at no cost to GnoRadio: a few new tracks
	// join the stations and the main flow is topped up (no-ops when current).
	// A sponsored pick is paid for by its artist: it feeds neither Listeners'
	// choice, the curator ranking nor ingestion, and only keeps the cooldown.
	switch {
	case sponsored:
		markPick(caller, st.id)
	case !curator:
		ingest(ts, pickIngest)
		choose(trackID, dur, ts)
		credit(caller, st.id, 1, 0, 0)
	default:
		ingest(ts, pickIngest)
	}
	if main := stations[MainStation]; main.ahead(ts) < pickFillBelow {
		main.program(ts, pickFill)
	}
	chain.Emit("Queued", "curator", strconv.FormatBool(curator), "station", itoa(st.id), "track", itoa(trackID), "by", caller.String(), "start", itoa64(start), "sponsored", itoa64(pay), "at", itoa64(at))
}

// place says when a new pick of d seconds starts. A pick for now starts when
// the song on air ends (at once over a flow track), after the picks for now
// already waiting; one booked for at starts at the first track boundary at or
// after at. Both go around booked picks: before one only if they end by its
// time, else after it.
func (st *station) place(ts, d, at int64) int64 {
	t := at
	if at == 0 {
		t = ts
		if _, _, off, slotDur, ok := st.rotationAt(ts); ok {
			t = ts + slotDur - off
		}
		for _, s := range st.schedule {
			if end := s.Start + s.Dur; end > ts && s.By != "" && s.At == 0 {
				t = end
			} else if s.By == "" && s.Start <= ts && ts < end {
				t = ts // a suggested track on air ends now: the app crossfades into the pick
			}
		}
	} else {
		t = st.boundary(at)
	}
	for _, s := range st.schedule {
		if s.By == "" || s.Start+s.Dur <= t {
			continue
		}
		if s.Start <= t {
			t = s.Start + s.Dur // playing then: wait for its end
			continue
		}
		limit := s.Start
		if s.At > 0 {
			limit = s.At // a booked pick may come back to its own time
		}
		if t+d <= limit {
			break
		}
		t = s.Start + s.Dur
	}
	return t
}

// boundary is the first track boundary at or after t outside listener
// picks: t itself on Main (the flow is a suggestion) or inside a programmed
// slot (place waits for its end), else the end of the rotation track on air.
func (st *station) boundary(t int64) int64 {
	if st.id == MainStation {
		return t
	}
	for _, s := range st.schedule {
		if s.Start <= t && t < s.Start+s.Dur {
			return t
		}
	}
	if _, _, off, d, ok := st.rotationAt(t); ok && off > 0 {
		return t + d - off
	}
	return t
}

// put puts a new listener slot in the schedule. On Main, a flow track on air
// at its start is cut there (it fades out), the flow's next track gives the
// slot its place (and so does this track if the flow had it) and the rest of
// the flow follows, around the picks. Elsewhere the slots after it are
// realigned: they moved with the rotation.
func (st *station) put(n Slot) {
	var kept, flow []Slot
	for i, s := range st.schedule {
		if s.By != "" || s.Start+s.Dur <= n.Start {
			kept = append(kept, s)
			continue
		}
		if s.Start < n.Start {
			s.Dur = n.Start - s.Start
			kept = append(kept, s)
			continue
		}
		// A flow track cut before a booked pick gets its length back.
		if i+1 < len(st.schedule) && st.schedule[i+1].By != "" && st.schedule[i+1].Start == s.Start+s.Dur {
			_, _, s.Dur, _ = catalog.TrackBrief(s.Track)
		}
		flow = append(flow, s)
	}
	st.schedule = kept
	i := st.insert(n)
	if st.id != MainStation {
		st.realign(i)
		return
	}
	t, replaced := n.Start+n.Dur, false
	for _, s := range flow {
		if s.Track == n.Track || !replaced {
			replaced = replaced || s.Track != n.Track
			continue
		}
		if s.Dur > 0 {
			t = st.lay(s, t)
		}
	}
}

// insert puts s in the schedule, sorted by start, and returns its index.
func (st *station) insert(s Slot) int {
	i := len(st.schedule)
	for i > 0 && st.schedule[i-1].Start > s.Start {
		i--
	}
	st.schedule = append(st.schedule, Slot{})
	copy(st.schedule[i+1:], st.schedule[i:])
	st.schedule[i] = s
	return i
}

// lay puts a flow slot at the first free moment from t, cut where the next
// programmed slot starts, and returns its end.
func (st *station) lay(s Slot, t int64) int64 {
	t, room := st.gap(t)
	s.Start = t
	if room >= 0 && room < s.Dur {
		s.Dur = room
	}
	st.insert(s)
	return t + s.Dur
}

// gap returns the first moment from t with nothing programmed, and the room
// there before the next programmed slot (-1: no limit).
func (st *station) gap(t int64) (int64, int64) {
	for _, s := range st.schedule {
		if s.Start+s.Dur <= t {
			continue
		}
		if s.Start <= t {
			t = s.Start + s.Dur
			continue
		}
		return t, s.Start - t
	}
	return t, -1
}

// realign re-times the listener slots after index i once the rotation moved
// under them: a booked one to the first boundary at or after its time (or
// right after the slot before it), a pick that followed the slot before it
// still follows it, a pick for now that waited for a rotation track after a
// gap waits for the new end of that track. Sponsored records, note reports and
// the replay record move along.
// ponytail: only queue realigns; Unqueue, DropSlot and rotation edits leave
// booked slots in place (the rotation track then pauses around them, as
// around any pick after a removed one); realign there too if it matters.
func (st *station) realign(i int) {
	var paused int64 // airtime of the slots before k: they all ended by its time (paused, inline)
	for _, s := range st.schedule[:i+1] {
		paused += s.Dur
	}
	total := st.rot.Total()
	oldEnd := st.schedule[i].Start + st.schedule[i].Dur
	for k := i + 1; k < len(st.schedule); k++ {
		prev, s := st.schedule[k-1], st.schedule[k]
		end := prev.Start + prev.Dur
		start := max64(s.Start, end)
		t := s.At
		if t == 0 && s.Start != oldEnd {
			t = s.Start // a pick for now that started on a rotation boundary after a gap
		}
		if t > end && total > 0 { // the rotation plays until then: wait for the end of that track
			start = t
			p := (t - st.epoch - paused) % total
			if p < 0 {
				p += total
			}
			if slot, _, off, ok := st.rot.Find(p); ok && off > 0 {
				_, d := st.rot.Slot(slot)
				start += d - off
			}
		} else if s.At > 0 || s.Start == oldEnd {
			start = max64(s.At, end)
		}
		oldEnd = s.Start + s.Dur
		paused += s.Dur
		if start != s.Start {
			st.move(k, start)
		}
	}
}

// move re-times slot k, with what is keyed by its start.
func (st *station) move(k int, start int64) {
	s := &st.schedule[k]
	if s.Note != "" {
		old := itoa(st.id) + "/" + itoa64(s.Start)
		if r, ok := noteReports.Get(old); ok {
			noteReports.Remove(old)
			noteReports.Set(itoa(st.id)+"/"+itoa64(start), r)
		}
	}
	if s.Pay > 0 {
		k := sponsorKey(st.id, s.By)
		if rec, ok := sponsor.Get(k); ok && atoi64(store.Field(rec, 0)) == s.Start {
			f := store.Fields(rec)
			sponsor.Set(k, store.Rec(itoa64(start), f[1], itoa64(start+s.Dur), f[3], f[4], f[5]))
		}
	}
	if s.By != "" && s.At == 0 {
		setPicked(st.id, s.Track, start) // a pick for now: the replay gap counts from its airing
	}
	s.Start = start
}

func abs64(n int64) int64 {
	if n < 0 {
		return -n
	}
	return n
}

// ---- Reads ----

// NeedsSync reports whether Sync has work: tracks to ingest or less than an
// hour of main flow left while the schedule has room. The robot reads it
// (free) before paying for a Sync.
func NeedsSync() bool {
	main := stations[MainStation]
	return synced < catalog.TrackCount() || main.ahead(now()) < fillAhead/3 && len(main.schedule) < maxSchedule
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
			return s.shownNote()
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
				s.Note = s.shownNote()
				out = append(out, s)
			}
		}
	}
	return out
}

// StationCount returns the number of stations (ids 0..StationCount()-1).
func StationCount() int { return len(stations) }

// StationName is "Main", the genre name, "New this week" or "Listeners' choice".
func StationName(stationID int) string {
	switch st := mustStation(stationID); st.id {
	case MainStation:
		return "Main"
	case NewStation:
		return "New this week"
	case ChoiceStation:
		return "Listeners' choice"
	default:
		return catalog.GenreName(st.genre)
	}
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

// ---- Migration pages: what a successor realm needs to copy ----

// StatePage lists one table's entries in a stable (hash bucket) order,
// paginated. Values are store records (store.Fields): "curators" address ->
// picks, tips, earned, sponsored refunds, first pick time, pick period, picks
// this period and the one before (sponsor.gno), then this week's week, picks,
// tips and earned, then "station:week:picks:tips:earned:last pick time"
// entries joined by ";"; "muted" and "strikes" address -> unix time;
// "dropped" station/track -> "1"; "lastPick" station -> fixed-width
// entries, a store id then a unix time (lastPicked);
// "noteReports" station/start -> reporters ("struck:time:previous" once
// hidden); "sponsor" station/address ->
// start, track, end, ugnot, held (the end the catalog reserved for) of a
// sponsored pick not collected yet. Rotations
// are in RotationPage, schedules in StationState; homes and the weekly tops
// can be rebuilt from them.
func StatePage(table string, offset, limit int) (keys, vals []string) {
	m := map[string]*store.Map{"curators": curators, "muted": muted, "strikes": strikes,
		"dropped": dropped, "lastPick": lastPick, "noteReports": noteReports, "sponsor": sponsor}[table]
	if m == nil {
		panic("radio: unknown table")
	}
	if offset < 0 {
		offset = 0
	}
	if limit < 1 || limit > 100 {
		limit = 100
	}
	keys = m.Keys(offset, limit)
	for _, k := range keys {
		v, _ := m.Get(k)
		vals = append(vals, v)
	}
	return keys, vals
}

// StationState returns what places a station's listeners: its epoch, its
// ring counter (New and Choice) and its schedule, played slots included.
func StationState(stationID int) (epoch int64, ring int, schedule []Slot) {
	st := mustStation(stationID)
	return st.epoch, st.ring, append([]Slot(nil), st.schedule...)
}

// FlowState returns the ingestion point and the main flow's position: the
// genre of the set being written, the tracks left in it and the next slot of
// each genre rotation (index = genre).
func FlowState() (syncedUpTo, genre, left int, cursors []int) {
	return synced, setGenre, setLeft, append([]int(nil), cursor[:]...)
}

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
	dropped.Set(dropKey(st.id, trackID), "1")
	st.setDuration(i, 0, ts)
	release(cur, st.dropSlots(trackID, ts))
	chain.Emit("SlotDropped", "station", itoa(st.id), "track", itoa(trackID))
}

// RestoreSlot undoes DropSlot: the track plays again on that station if the
// catalog still allows it. Radio admin only.
func RestoreSlot(cur realm, stationID, trackID int) {
	onlyAdmin(cur)
	st := mustStation(stationID)
	if !dropped.Remove(dropKey(st.id, trackID)) {
		panic("radio: this slot was not dropped")
	}
	refresh(cur, trackID)
	chain.Emit("SlotRestored", "station", itoa(st.id), "track", itoa(trackID))
}

func dropKey(stationID, trackID int) string { return text.Key(stationID) + "/" + text.Key(trackID) }

// Unqueue removes a track's programmed slots from a station; one on air ends
// now. Radio admin (curator) only.
func Unqueue(cur realm, stationID, trackID int) {
	onlyAdmin(cur)
	st := mustStation(stationID)
	release(cur, st.dropSlots(trackID, now()))
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

// Freeze stops every write, e.g. during a migration announced with SetSuccessor.
func Freeze(cur realm, on bool) {
	onlyAdmin(cur)
	frozen = on
	chain.Emit("Frozen", "on", strconv.FormatBool(on))
}

// SetSuccessor announces the realm that takes over ("" for none), so clients
// can follow it. Radio admin only.
func SetSuccessor(cur realm, pkgPath string) {
	onlyAdmin(cur)
	if pkgPath != "" && (!strings.HasPrefix(pkgPath, "gno.land/r/") || len(pkgPath) > 120 || !pathChars(pkgPath)) {
		panic("radio: invalid realm path")
	}
	successor = pkgPath
	chain.Emit("Successor", "path", pkgPath)
}

func Successor() string { return successor }

func pathChars(s string) bool {
	for _, c := range s {
		if !(c >= 'a' && c <= 'z' || c >= '0' && c <= '9' || c == '/' || c == '.' || c == '_' || c == '-') {
			return false
		}
	}
	return true
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

// join puts a synced track in New or Choice, a ring of keep slots: once
// full, the oldest slot is reused in place, so the rotation never outgrows
// keep whatever the catalog size or the number of picks. The track it held
// leaves homes, so Refresh leaves it out. It returns the track's homes entry.
// Listeners do not jump: setDuration re-anchors around the change.
func (st *station) join(trackID int, dur int64, ts int64, keep int) string {
	i := st.ring % keep
	st.ring++
	if st.rot.Len() < keep {
		return itoa(st.id) + ":" + itoa(st.add(trackID, dur, ts))
	}
	old, _ := st.rot.Slot(i)
	st.setDuration(i, 0, ts)
	st.rot.Set(i, trackID, 0)
	st.setDuration(i, dur, ts)
	entry := itoa(st.id) + ":" + itoa(i)
	if rec, ok := homes.Get(old - 1); ok {
		var kept []string
		for _, p := range strings.Split(rec, ",") {
			if p != entry {
				kept = append(kept, p)
			}
		}
		homes.Set(old-1, strings.Join(kept, ","))
	}
	return entry
}

// choose adds a synced track to Listeners' choice unless it is already there.
func choose(trackID int, dur int64, ts int64) {
	if trackID < 1 || trackID > synced {
		return // not ingested yet: it has no homes record
	}
	if _, in := homesOf(trackID)[ChoiceStation]; in {
		return
	}
	if dropped.Has(dropKey(ChoiceStation, trackID)) {
		dur = 0
	}
	entry := stations[ChoiceStation].join(trackID, dur, ts, choiceCap)
	rec, _ := homes.Get(trackID - 1)
	homes.Set(trackID-1, homeAdd(rec, entry))
}

func homeAdd(rec, entry string) string {
	if rec == "" {
		return entry
	}
	return rec + "," + entry
}

// slot returns a track's index in this station's rotation. The main station
// keeps no index: Sync appends every track there in id order, so track id
// sits at id-1. Other stations look the slot up in homes.
func (st *station) slot(trackID int) (int, bool) {
	if st.id == MainStation {
		i := trackID - 1
		if i >= 0 && i < st.rot.Len() {
			return i, true
		}
		return 0, false
	}
	i, ok := homesOf(trackID)[st.id]
	return i - 1, ok
}

// homesOf maps the stations other than Main whose rotation holds a track to
// its slot+1.
func homesOf(trackID int) map[int]int {
	rec, _ := homes.Get(trackID - 1)
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

// The replay record of a station is fixed-width entries, the track as a
// store id (store.W bytes) then the pick time (10 digits), read by slicing.
const pickW = store.W + 10

// lastPicked is when a track was last picked on a station, within replayGap.
func lastPicked(stationID, trackID int) (int64, bool) {
	rec, _ := lastPick.Get(itoa(stationID))
	key := store.Enc(trackID)
	for i := 0; i+pickW <= len(rec); i += pickW {
		if rec[i:i+store.W] == key {
			return atoi64(rec[i+store.W : i+pickW]), true
		}
	}
	return 0, false
}

// setPicked records a pick time (the later one wins) and drops the picks
// older than replayGap, which no check reads: the record stays as short as
// the picks of the last three hours.
func setPicked(stationID, trackID int, t int64) {
	k := itoa(stationID)
	rec, _ := lastPick.Get(k)
	key := store.Enc(trackID)
	cut := now() - replayGap
	out := ""
	for i := 0; i+pickW <= len(rec); i += pickW {
		at := atoi64(rec[i+store.W : i+pickW])
		if rec[i:i+store.W] == key {
			if at > t {
				t = at
			}
		} else if at > cut {
			out += rec[i : i+pickW]
		}
	}
	if t > cut {
		out += key + itoa64(t)
	}
	if out == "" {
		lastPick.Remove(k)
		return
	}
	lastPick.Set(k, out)
}

// fold moves programmed slots that ended long ago into the epoch.
func (st *station) fold(ts int64) {
	i := 0
	for i < len(st.schedule) && st.schedule[i].Start+st.schedule[i].Dur <= ts-foldAfter {
		s := st.schedule[i]
		st.epoch += s.Dur
		noteReports.Remove(itoa(st.id) + "/" + itoa64(s.Start))
		if s.At > 0 { // the replay gap counts from when a booked pick aired
			setPicked(st.id, s.Track, s.Start)
		}
		i++
	}
	if i > 0 {
		st.schedule = append([]Slot(nil), st.schedule[i:]...)
	}
}

// dropSlots removes a track's programmed slots; one on air ends now. It
// returns the sponsored ones, which no longer air in full: their payout goes
// back to the artist (release).
func (st *station) dropSlots(trackID int, ts int64) (cut []hold) {
	var out []Slot
	changed := false
	for _, s := range st.schedule {
		if s.Track == trackID && s.Pay > 0 && s.Start+s.Dur > ts {
			if h, ok := unsponsor(st.id, s, ts); ok {
				cut = append(cut, h)
			}
		}
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
	return cut
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

// PickRules returns the limits on listeners' picks, for pages that explain
// them: one pick per cooldown per station, a track not again within replay,
// at most ahead seconds and queue slots waiting, perArtist waiting per artist,
// booked picks bookFrom to bookTo ahead and bookedPerHour per clock hour.
func PickRules() (cooldown, replay, ahead int64, queue, perArtist int, bookFrom, bookTo int64, bookedPerHour int) {
	return queueCooldown, replayGap, maxAheadAir, maxQueue, maxPerArtistQ, bookMin, bookMax, maxBookedHour
}
