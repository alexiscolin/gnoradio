// Package gnoradio is a community radio and open music catalog living fully
// on gno.land: artists register, publish tracks (audio on IPFS, everything else
// on-chain), receive tips split transparently between collaborators, sell NFT
// tickets for their concerts, and the community programs the radio.
//
// Money never stays in this realm: every tip and ticket sale is forwarded to
// the artist (and collaborators) in the same transaction. 0% platform fee.
package gnoradio

import (
	"chain"
	"chain/banker"
	"chain/runtime/unsafe"
	"strconv"
	"strings"
	"time"

	"gno.land/p/nt/avl/v0"
	"gno.land/p/nt/grc721/v0"
	"gno.land/p/nt/seqid/v0"
)

const (
	version        = "0.2.0"
	denom          = "ugnot"
	ugnot          = 1_000_000
	minTip         = 100_000           // 0.1 GNOT
	maxTip         = 1_000_000 * ugnot // keeps share math far from overflow
	maxSplits      = 4
	maxSplitPct    = 90 // the artist always keeps at least 10%
	maxQueue       = 30
	maxPerArtistQ  = 2 // queued slots per artist at once
	earlyBadges    = 10
	minDuration    = 10
	maxDuration    = 1200
	maxCapacity    = 10000
	maxPerBuyer    = 4
	maxTicketPrice = 10_000 * ugnot
	maxPerArtist   = 500 // tracks or events per artist
	maxReports     = 1000
	checkInWindow  = 12 * 3600 // check-in opens 12h before the concert
)

// licenses are SPDX identifiers. ALL-RIGHTS-RESERVED still grants GnoRadio the
// broadcast right declared at publish time.
var licenses = []string{
	"CC0-1.0", "CC-BY-4.0", "CC-BY-SA-4.0", "CC-BY-ND-4.0",
	"CC-BY-NC-4.0", "CC-BY-NC-SA-4.0", "CC-BY-NC-ND-4.0", "ALL-RIGHTS-RESERVED",
}

// Collective management (SACEM & co): members may only publish works they
// declared under a non-commercial CC license.
const (
	cmoNone     = "none"
	cmoSacemNC  = "sacem-nc"
	rightsTerms = "I own the rights to this recording and composition and grant GnoRadio a non-exclusive right to broadcast and display it."
)

type Split struct {
	To  address
	Pct int64 // percent of each tip
}

type Artist struct {
	Addr     address
	Name     string
	Bio      string
	Joined   int64
	Tips     int64
	Tracks   []int
	Events   []int
	Verified bool
	Hidden   bool
}

type Track struct {
	ID         int
	Artist     address
	Title      string
	Genre      string
	Credits    string
	CID        string // IPFS CID of the audio file
	License    string // SPDX id
	CMO        string // none | sacem-nc
	Duration   int64  // seconds
	Splits     []Split
	Created    int64
	Likes      int
	Tips       int64
	Supporters int // distinct tippers
	Hidden     bool
	early      []address // first listeners to like it
	likedBy    avl.Tree  // address -> true
	tippers    avl.Tree  // address -> true
}

// Slot is a track programmed on the radio by a listener. Dur is copied from
// the track so later edits cannot move the timeline.
type Slot struct {
	Track int
	Start int64
	Dur   int64
	By    address
}

type Event struct {
	ID        int
	Artist    address
	Title     string
	Venue     string
	Link      string // optional https link (stream, venue page)
	Start     int64
	Price     int64
	Capacity  int
	Sold      int
	Cancelled bool
	Hidden    bool
	buyers    avl.Tree // address -> int (tickets bought)
}

type Ticket struct {
	ID       int
	Event    int
	Serial   int
	Attended bool
}

type Listener struct {
	Likes    int
	Tipped   int64
	Queued   int
	Attended int
}

type report struct {
	ID     int
	Kind   string // track | event | artist
	Target string
	Reason string
	By     address
	At     int64
}

type rank struct {
	key   string
	value int64
}

var (
	admin     address
	frozen    bool
	successor string

	artists   avl.Tree // address -> *Artist
	names     avl.Tree // lowercased artist name -> address
	tracks    avl.Tree // padded id -> *Track
	events    avl.Tree // padded id -> *Event
	tickets   avl.Tree // padded id -> *Ticket
	owned     avl.Tree // owner address -> []int ticket ids
	listeners avl.Tree // address -> *Listener
	reports   avl.Tree // padded id -> *report
	nTracks   int
	nEvents   int
	nTickets  int
	nReports  int

	// Radio: the rotation plays every playable track in id order, looping.
	// Its position at time ts is (ts - epoch - paused(ts)) mod rotTotal, so it
	// pauses while listener-programmed slots play.
	schedule []Slot // sorted by Start, at most ~maxQueue+few entries
	epoch    int64
	rotTotal int64

	topArtists []rank // by tips
	topFans    []rank // by tipped
	topLiked   []rank // track ids by likes

	ticketTok *grc721.Token
	ticketLed *grc721.PrivateLedger
	tokSeq    seqid.ID
)

func init() {
	admin = unsafe.OriginCaller()
}

// ---- Artists ----

// Register creates or updates the caller's artist profile. Names use Latin
// letters, digits and a little punctuation, to prevent look-alike names.
func Register(cur realm, name, bio string) {
	caller := userCaller(cur)
	noPayment()
	notFrozen()
	name = strings.TrimSpace(name)
	bio = strings.TrimSpace(bio)
	if !validName(name) {
		panic("gnoradio: le nom d'artiste doit faire 2 à 32 caractères (lettres latines, chiffres, espaces, . ' -)")
	}
	mustText("la bio", bio, 0, 280)
	key := strings.ToLower(name)

	if a := getArtist(caller); a != nil {
		old := strings.ToLower(a.Name)
		if old != key {
			if names.Has(key) {
				panic("gnoradio: ce nom d'artiste est déjà pris")
			}
			// The old name stays reserved to this address.
			names.Set(key, caller)
			a.Verified = false
		}
		a.Name, a.Bio = name, bio
		chain.Emit("ArtistUpdated", "artist", caller.String(), "name", name)
		return
	}
	if names.Has(key) {
		panic("gnoradio: ce nom d'artiste est déjà pris")
	}
	artists.Set(caller.String(), &Artist{Addr: caller, Name: name, Bio: bio, Joined: now()})
	names.Set(key, caller)
	chain.Emit("ArtistRegistered", "artist", caller.String(), "name", name)
}

// ---- Tracks ----

// Publish adds a track by the caller, who must be a registered artist and
// declare owning the rights (rights must be "yes"). duration is "m:ss".
// cmo is "none" or "sacem-nc" (SACEM members: declared NC works only).
// splits is optional: "g1...:30,g1...:15" gives each collaborator that percent
// of every tip; the artist keeps the rest (at least 10%).
func Publish(cur realm, title, genre, credits, cid, license, cmo, duration, splits, rights string) int {
	caller := userCaller(cur)
	noPayment()
	notFrozen()
	a := mustArtist(caller)
	if len(a.Tracks) >= maxPerArtist {
		panic("gnoradio: limite de morceaux atteinte pour cet artiste")
	}
	if strings.ToLower(strings.TrimSpace(rights)) != "yes" && strings.ToLower(strings.TrimSpace(rights)) != "oui" {
		panic("gnoradio: tu dois déclarer détenir les droits (réponds oui)")
	}
	t := &Track{ID: nTracks + 1, Artist: caller, Created: now()}
	setTrackInfo(t, title, genre, credits, cid, license, cmo, duration)
	t.Splits = parseSplits(splits, caller, cur.Address())

	ts := now()
	p := rotPos(ts)
	nTracks++
	tracks.Set(key(t.ID), t)
	a.Tracks = append(a.Tracks, t.ID)
	// New tracks join the end of the rotation; keep everyone on their song.
	rotTotal += t.Duration
	epoch = ts - paused(ts) - p
	chain.Emit("TrackPublished", "id", itoa(t.ID), "artist", caller.String(), "title", t.Title,
		"cid", t.CID, "duration", itoa64(t.Duration), "license", t.License)
	return t.ID
}

// EditTrack fixes a track's details. Artist only.
func EditTrack(cur realm, trackID int, title, genre, credits, cid, license, cmo, duration string) {
	caller := userCaller(cur)
	noPayment()
	notFrozen()
	t := mustTrack(trackID)
	if t.Artist != caller {
		panic("gnoradio: seul l'artiste peut modifier ce morceau")
	}
	reanchor(func() { setTrackInfo(t, title, genre, credits, cid, license, cmo, duration) })
	chain.Emit("TrackEdited", "id", itoa(t.ID), "cid", t.CID, "duration", itoa64(t.Duration))
}

func setTrackInfo(t *Track, title, genre, credits, cid, license, cmo, duration string) {
	title, genre, credits = strings.TrimSpace(title), strings.TrimSpace(genre), strings.TrimSpace(credits)
	mustText("le titre", title, 1, 64)
	mustText("le genre", genre, 0, 24)
	mustText("les crédits", credits, 0, 120)
	cid = strings.TrimSpace(cid)
	if !validCID(cid) {
		panic("gnoradio: le CID doit être un CID IPFS (46 à 100 caractères alphanumériques)")
	}
	lic := normLicense(license)
	if lic == "" {
		panic("gnoradio: licence inconnue, choisis parmi " + strings.Join(licenses, ", "))
	}
	cmo = strings.ToLower(strings.TrimSpace(cmo))
	if cmo == "" {
		cmo = cmoNone
	}
	switch cmo {
	case cmoNone:
	case cmoSacemNC:
		if !strings.Contains(lic, "-NC") {
			panic("gnoradio: les membres SACEM ne peuvent publier que des œuvres déclarées en licence CC NC")
		}
	default:
		panic("gnoradio: société de gestion : réponds none ou sacem-nc (les autres ne sont pas encore prises en charge)")
	}
	d, ok := parseClock(duration)
	if !ok || d < minDuration || d > maxDuration {
		panic("gnoradio: durée au format m:ss, entre 0:10 et 20:00")
	}
	t.Title, t.Genre, t.Credits, t.CID, t.License, t.CMO, t.Duration = title, genre, credits, cid, lic, cmo, d
}

// Like records the caller's like. The first listeners to like a track earn
// its "premier auditeur" badge.
func Like(cur realm, trackID int) {
	caller := userCaller(cur)
	noPayment()
	notFrozen()
	t := mustTrack(trackID)
	if caller == t.Artist {
		panic("gnoradio: tu ne peux pas aimer ton propre morceau")
	}
	if t.likedBy.Has(caller.String()) {
		panic("gnoradio: tu aimes déjà ce morceau")
	}
	t.likedBy.Set(caller.String(), true)
	t.Likes++
	if len(t.early) < earlyBadges {
		t.early = append(t.early, caller)
	}
	listener(caller).Likes++
	topLiked = updateTop(topLiked, itoa(t.ID), int64(t.Likes), 10)
	chain.Emit("Liked", "track", itoa(trackID), "by", caller.String())
}

// Tip sends the attached ugnot to the track's artist and collaborators,
// split as declared at publish time, in this same transaction.
func Tip(cur realm, trackID int) {
	caller := userCaller(cur)
	notFrozen()
	t := mustTrack(trackID)
	if caller == t.Artist {
		panic("gnoradio: tu ne peux pas soutenir ton propre morceau")
	}
	amt := paid()
	if amt < minTip || amt > maxTip {
		panic("gnoradio: un tip va de 0.1 à 1000000 GNOT")
	}

	bk := banker.NewBanker(banker.BankerTypeRealmSend, cur)
	self := cur.Address()
	rest := amt
	var paidTo strings.Builder
	for _, s := range t.Splits {
		share := amt * s.Pct / 100
		if share > 0 {
			bk.SendCoins(self, s.To, chain.Coins{{Denom: denom, Amount: share}})
			rest -= share
			paidTo.WriteString(s.To.String() + ":" + itoa64(share) + ",")
		}
	}
	bk.SendCoins(self, t.Artist, chain.Coins{{Denom: denom, Amount: rest}})
	paidTo.WriteString(t.Artist.String() + ":" + itoa64(rest))

	t.Tips += amt
	if !t.tippers.Has(caller.String()) {
		t.tippers.Set(caller.String(), true)
		t.Supporters++
	}
	a := mustArtist(t.Artist)
	a.Tips += amt
	l := listener(caller)
	l.Tipped += amt
	topArtists = updateTop(topArtists, a.Addr.String(), a.Tips, 10)
	topFans = updateTop(topFans, caller.String(), l.Tipped, 10)
	chain.Emit("Tipped", "track", itoa(trackID), "by", caller.String(), "amount", itoa64(amt), "paid", paidTo.String())
}

// ---- Radio ----

// Queue programs a track on the radio. It starts after the last programmed
// track, or when the song currently on air ends: nothing is cut.
// Limits: one waiting slot per listener, two per artist, a track at most once.
func Queue(cur realm, trackID int) {
	caller := userCaller(cur)
	noPayment()
	notFrozen()
	t := mustTrack(trackID)
	ts := now()
	pruneSchedule(ts)
	upcoming, perArtist := 0, 0
	for _, s := range schedule {
		if s.Start+s.Dur <= ts {
			continue
		}
		upcoming++
		if s.Start > ts && s.By == caller {
			panic("gnoradio: tu as déjà un morceau en attente dans la file")
		}
		if s.Track == t.ID {
			panic("gnoradio: ce morceau est déjà programmé")
		}
		if st := getTrack(s.Track); st != nil && st.Artist == t.Artist {
			perArtist++
		}
	}
	if upcoming >= maxQueue {
		panic("gnoradio: la file est pleine, reviens plus tard")
	}
	if perArtist >= maxPerArtistQ {
		panic("gnoradio: cet artiste a déjà 2 morceaux dans la file")
	}
	start := ts
	if n := len(schedule); n > 0 && schedule[n-1].Start+schedule[n-1].Dur > ts {
		start = schedule[n-1].Start + schedule[n-1].Dur
	} else if id, off := rotationAt(ts); id != 0 {
		start = ts + getTrack(id).Duration - off
	}
	schedule = append(schedule, Slot{Track: t.ID, Start: start, Dur: t.Duration, By: caller})
	listener(caller).Queued++
	chain.Emit("Queued", "track", itoa(t.ID), "by", caller.String(), "start", itoa64(start))
}

// NowPlaying returns what is on air at the last block: the track, the offset
// into it in seconds, and whether a listener programmed it. trackID is 0 when
// nothing plays. Clients should prefer ScheduleJSON and their own clock.
func NowPlaying() (trackID int, offset int64, queued bool) {
	return onAir(now())
}

// UpNext returns the programmed slots that have not started yet.
func UpNext() []Slot {
	ts := now()
	var out []Slot
	for _, s := range schedule {
		if s.Start > ts && playable(getTrack(s.Track)) {
			out = append(out, s)
		}
	}
	return out
}

func onAir(ts int64) (int, int64, bool) {
	for _, s := range schedule {
		if ts >= s.Start && ts < s.Start+s.Dur {
			if playable(getTrack(s.Track)) {
				return s.Track, ts - s.Start, true
			}
			return 0, 0, false // a removed slot plays silence until its end
		}
	}
	id, off := rotationAt(ts)
	return id, off, false
}

// paused is the total airtime taken by programmed slots before ts.
func paused(ts int64) int64 {
	var p int64
	for _, s := range schedule {
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

func rotPos(ts int64) int64 {
	if rotTotal == 0 {
		return 0
	}
	p := (ts - epoch - paused(ts)) % rotTotal
	if p < 0 {
		p += rotTotal
	}
	return p
}

// rotationAt returns the rotation track and offset at ts.
func rotationAt(ts int64) (int, int64) {
	if rotTotal == 0 {
		return 0, 0
	}
	pos := rotPos(ts)
	id, off := 0, int64(0)
	tracks.Iterate("", "", func(_ string, v any) bool {
		t := v.(*Track)
		if !playable(t) {
			return false
		}
		if pos < t.Duration {
			id, off = t.ID, pos
			return true
		}
		pos -= t.Duration
		return false
	})
	return id, off
}

// reanchor applies a change that alters the rotation (hide, edit) while
// keeping listeners on the song they are hearing.
func reanchor(change func()) {
	ts := now()
	curID, off := rotationAt(ts)
	change()
	var total, start int64
	found := false
	tracks.Iterate("", "", func(_ string, v any) bool {
		t := v.(*Track)
		if !playable(t) {
			return false
		}
		if !found && t.ID >= curID {
			found = true
			start = total
			if t.ID == curID && off < t.Duration {
				start += off
			}
		}
		total += t.Duration
		return false
	})
	rotTotal = total
	if !found {
		start = 0
	}
	epoch = ts - paused(ts) - start
}

// pruneSchedule folds slots that ended more than an hour ago into epoch.
func pruneSchedule(ts int64) {
	i := 0
	for i < len(schedule) && schedule[i].Start+schedule[i].Dur <= ts-3600 {
		epoch += schedule[i].Dur
		i++
	}
	if i > 0 {
		schedule = append([]Slot(nil), schedule[i:]...)
	}
}

// dropSlots removes a track's programmed slots; one on air ends now.
func dropSlots(trackID int, ts int64) {
	var out []Slot
	for _, s := range schedule {
		if s.Track == trackID {
			if s.Start >= ts {
				continue
			}
			if s.Start+s.Dur > ts {
				s.Dur = ts - s.Start
			}
		}
		out = append(out, s)
	}
	schedule = out
}

// ---- Concerts & NFT tickets ----

// CreateEvent announces a concert by the caller (a registered artist).
// start is "YYYY-MM-DD HH:MM" in UTC; price is in GNOT ("0" for free, "2.5");
// link is an optional https URL (stream or venue page, public).
func CreateEvent(cur realm, title, venue, link, start, price string, capacity int) int {
	caller := userCaller(cur)
	noPayment()
	notFrozen()
	a := mustArtist(caller)
	if len(a.Events) >= maxPerArtist {
		panic("gnoradio: limite de concerts atteinte pour cet artiste")
	}
	title, venue, link = strings.TrimSpace(title), strings.TrimSpace(venue), strings.TrimSpace(link)
	mustText("le titre", title, 2, 48)
	mustText("le lieu", venue, 2, 48)
	if link != "" && !validURL(link) {
		panic("gnoradio: le lien doit commencer par https:// (200 caractères max, sans espace)")
	}
	when, err := time.Parse("2006-01-02 15:04", strings.TrimSpace(start))
	if err != nil {
		panic("gnoradio: date au format 2026-11-20 21:00 (heure UTC)")
	}
	if when.Unix() <= now() {
		panic("gnoradio: le concert doit être dans le futur")
	}
	p, ok := parseGNOT(price)
	if !ok || p > maxTicketPrice || (p > 0 && p < minTip) {
		panic("gnoradio: prix en GNOT : 0 (gratuit) ou entre 0.1 et 10000")
	}
	if capacity < 1 || capacity > maxCapacity {
		panic("gnoradio: entre 1 et 10000 places")
	}
	nEvents++
	e := &Event{ID: nEvents, Artist: caller, Title: title, Venue: venue, Link: link, Start: when.Unix(), Price: p, Capacity: capacity}
	events.Set(key(e.ID), e)
	a.Events = append(a.Events, e.ID)
	chain.Emit("EventCreated", "id", itoa(e.ID), "artist", caller.String(), "start", itoa64(e.Start), "price", itoa64(p))
	return e.ID
}

// CancelEvent stops ticket sales. Payments already went to the artist, who
// handles refunds directly. Artist only.
func CancelEvent(cur realm, eventID int) {
	caller := userCaller(cur)
	noPayment()
	e := mustEvent(eventID)
	if e.Artist != caller {
		panic("gnoradio: seul l'artiste peut annuler ce concert")
	}
	e.Cancelled = true
	chain.Emit("EventCancelled", "id", itoa(e.ID))
}

// BuyTicket mints a GRC721 ticket to the caller; the exact price must be
// attached and goes straight to the artist.
func BuyTicket(cur realm, eventID int) int {
	caller := userCaller(cur)
	notFrozen()
	e := mustEvent(eventID)
	if e.Cancelled {
		panic("gnoradio: ce concert est annulé")
	}
	if now() >= e.Start {
		panic("gnoradio: la billetterie est fermée")
	}
	if e.Sold >= e.Capacity {
		panic("gnoradio: complet")
	}
	bought := 0
	if v, ok := e.buyers.Get(caller.String()).(int); ok {
		bought = v
	}
	if bought >= maxPerBuyer || (e.Price == 0 && bought >= 1) {
		panic("gnoradio: limite de billets atteinte pour ce concert (1 gratuit ou 4 payants par wallet)")
	}
	if e.Price == 0 {
		noPayment()
	} else if paid() != e.Price {
		panic("gnoradio: joins exactement " + gnot(e.Price))
	}

	if ticketTok == nil {
		ticketTok, ticketLed = grc721.NewToken("GnoRadio Ticket", "GRTIX", tokSeq.Next(), cur)
	}
	e.Sold++
	e.buyers.Set(caller.String(), bought+1)
	nTickets++
	tk := &Ticket{ID: nTickets, Event: e.ID, Serial: e.Sold}
	tickets.Set(key(tk.ID), tk)
	if err := ticketLed.Mint(caller, tokenID(tk.ID)); err != nil {
		panic("gnoradio: " + err.Error())
	}
	addOwned(caller, tk.ID)
	if e.Price > 0 {
		bk := banker.NewBanker(banker.BankerTypeRealmSend, cur)
		bk.SendCoins(cur.Address(), e.Artist, chain.Coins{{Denom: denom, Amount: e.Price}})
	}
	chain.Emit("TicketBought", "event", itoa(e.ID), "ticket", itoa(tk.ID), "by", caller.String(), "price", itoa64(e.Price))
	return tk.ID
}

// TransferTicket gives one of the caller's tickets to someone else. There is
// no built-in resale market.
func TransferTicket(cur realm, to address, ticketID int) {
	caller := userCaller(cur)
	noPayment()
	tk := mustTicket(ticketID)
	if tk.Attended {
		panic("gnoradio: un billet déjà utilisé ne peut plus être offert")
	}
	if !to.IsValid() || to == caller || to == cur.Address() {
		panic("gnoradio: destinataire invalide")
	}
	if err := ticketLed.TransferFrom(caller, caller, to, tokenID(ticketID)); err != nil {
		panic("gnoradio: tu n'es pas le détenteur de ce billet")
	}
	removeOwned(caller, ticketID)
	addOwned(to, ticketID)
}

// CheckIn marks a ticket as used at the door; its holder earns the
// "j'y étais" stamp. The concert's artist only, from 12h before the start.
func CheckIn(cur realm, ticketID int) {
	caller := userCaller(cur)
	noPayment()
	tk := mustTicket(ticketID)
	e := mustEvent(tk.Event)
	if e.Artist != caller {
		panic("gnoradio: seul l'artiste du concert peut valider les billets")
	}
	if now() < e.Start-checkInWindow {
		panic("gnoradio: la validation ouvre 12h avant le concert")
	}
	if tk.Attended {
		panic("gnoradio: billet déjà validé")
	}
	tk.Attended = true
	holder := TicketOwner(ticketID)
	listener(holder).Attended++
	chain.Emit("CheckedIn", "ticket", itoa(ticketID), "holder", holder.String())
}

// TicketOwner returns the current holder of a ticket.
func TicketOwner(ticketID int) address {
	mustTicket(ticketID)
	owner, err := ticketTok.OwnerOf(tokenID(ticketID))
	if err != nil {
		panic(err.Error())
	}
	return owner
}

// ---- Community moderation ----

// Report flags a track, event or artist for the moderators.
// kind is track, event or artist; target is the id or the g1 address.
func Report(cur realm, kind, target, reason string) {
	caller := userCaller(cur)
	noPayment()
	reason = strings.TrimSpace(reason)
	mustText("le motif", reason, 4, 200)
	switch kind {
	case "track":
		mustTrack(atoi(target))
	case "event":
		mustEvent(atoi(target))
	case "artist":
		mustArtist(address(target))
	default:
		panic("gnoradio: type à signaler : track, event ou artist")
	}
	if nReports >= maxReports {
		panic("gnoradio: file de modération pleine, contacte les modérateurs")
	}
	nReports++
	reports.Set(key(nReports), &report{ID: nReports, Kind: kind, Target: target, Reason: reason, By: caller, At: now()})
	chain.Emit("Reported", "kind", kind, "target", target, "by", caller.String())
}

func HideTrack(cur realm, trackID int, hidden bool) {
	onlyAdmin(cur)
	t := getTrack(trackID)
	if t == nil {
		panic("gnoradio: morceau inconnu")
	}
	reanchor(func() { t.Hidden = hidden })
	if hidden {
		dropSlots(trackID, now())
	}
	chain.Emit("Moderated", "kind", "track", "target", itoa(trackID), "hidden", strconv.FormatBool(hidden))
}

func HideEvent(cur realm, eventID int, hidden bool) {
	onlyAdmin(cur)
	mustEvent(eventID).Hidden = hidden
	chain.Emit("Moderated", "kind", "event", "target", itoa(eventID), "hidden", strconv.FormatBool(hidden))
}

// HideArtist hides an artist's profile, tracks and concerts.
func HideArtist(cur realm, addr address, hidden bool) {
	onlyAdmin(cur)
	a := getArtist(addr)
	if a == nil {
		panic("gnoradio: artiste inconnu")
	}
	reanchor(func() { a.Hidden = hidden })
	if hidden {
		ts := now()
		for _, id := range a.Tracks {
			dropSlots(id, ts)
		}
	}
	chain.Emit("Moderated", "kind", "artist", "target", addr.String(), "hidden", strconv.FormatBool(hidden))
}

// Verify marks an artist as verified (identity checked off-chain).
func Verify(cur realm, addr address, verified bool) {
	onlyAdmin(cur)
	mustArtist(addr).Verified = verified
	chain.Emit("Verified", "artist", addr.String(), "verified", strconv.FormatBool(verified))
}

// TransferAdmin hands moderation to a new address (a multisig or a DAO realm).
func TransferAdmin(cur realm, to address) {
	onlyAdmin(cur)
	if !to.IsValid() {
		panic("gnoradio: adresse invalide")
	}
	chain.Emit("AdminTransferred", "from", admin.String(), "to", to.String())
	admin = to
}

// Freeze stops new activity, e.g. when migrating to a new version announced
// with SetSuccessor. Tickets can still be gifted and checked in.
func Freeze(cur realm, on bool) {
	onlyAdmin(cur)
	frozen = on
	chain.Emit("Frozen", "on", strconv.FormatBool(on))
}

func SetSuccessor(cur realm, pkgPath string) {
	onlyAdmin(cur)
	if pkgPath != "" && (!strings.HasPrefix(pkgPath, "gno.land/r/") || !validURLChars(pkgPath) || len(pkgPath) > 120) {
		panic("gnoradio: chemin de realm invalide")
	}
	successor = pkgPath
	chain.Emit("Successor", "path", pkgPath)
}

// ---- helpers ----

func now() int64 { return time.Now().Unix() }

func userCaller(cur realm) address {
	if !cur.Previous().IsUserCall() {
		panic("gnoradio: appelle cette fonction directement depuis ton wallet")
	}
	return cur.Previous().Address()
}

func onlyAdmin(cur realm) {
	if cur.Previous().Address() != admin {
		panic("gnoradio: réservé aux modérateurs")
	}
	noPayment()
}

func notFrozen() {
	if frozen {
		panic("gnoradio: GnoRadio est en pause (migration en cours)")
	}
}

func noPayment() {
	if len(unsafe.OriginSend()) != 0 {
		panic("gnoradio: cette action ne prend pas de GNOT")
	}
}

// paid returns the ugnot attached to the call; anything else is refused.
func paid() int64 {
	sent := unsafe.OriginSend()
	if len(sent) != 1 || sent[0].Denom != denom || sent[0].Amount <= 0 {
		panic("gnoradio: joins un montant en ugnot")
	}
	return sent[0].Amount
}

func key(id int) string {
	s := strconv.Itoa(id)
	return strings.Repeat("0", 10-len(s)) + s
}

func listener(addr address) *Listener {
	if l, ok := listeners.Get(addr.String()).(*Listener); ok {
		return l
	}
	l := &Listener{}
	listeners.Set(addr.String(), l)
	return l
}

func getArtist(addr address) *Artist {
	if a, ok := artists.Get(addr.String()).(*Artist); ok {
		return a
	}
	return nil
}

func mustArtist(addr address) *Artist {
	a := getArtist(addr)
	if a == nil || a.Hidden {
		panic("gnoradio: crée d'abord ton profil d'artiste")
	}
	return a
}

func artistByName(name string) *Artist {
	if addr, ok := names.Get(strings.ToLower(name)).(address); ok {
		return getArtist(addr)
	}
	return nil
}

func getTrack(id int) *Track {
	if t, ok := tracks.Get(key(id)).(*Track); ok {
		return t
	}
	return nil
}

// playable reports whether a track can be heard and shown.
func playable(t *Track) bool {
	if t == nil || t.Hidden {
		return false
	}
	a := getArtist(t.Artist)
	return a != nil && !a.Hidden
}

func mustTrack(id int) *Track {
	t := getTrack(id)
	if !playable(t) {
		panic("gnoradio: morceau inconnu")
	}
	return t
}

func getEvent(id int) *Event {
	if e, ok := events.Get(key(id)).(*Event); ok {
		return e
	}
	return nil
}

func visibleEvent(e *Event) bool {
	if e == nil || e.Hidden {
		return false
	}
	a := getArtist(e.Artist)
	return a != nil && !a.Hidden
}

func mustEvent(id int) *Event {
	e := getEvent(id)
	if !visibleEvent(e) {
		panic("gnoradio: concert inconnu")
	}
	return e
}

func getTicket(id int) *Ticket {
	if tk, ok := tickets.Get(key(id)).(*Ticket); ok {
		return tk
	}
	return nil
}

func mustTicket(id int) *Ticket {
	tk := getTicket(id)
	if tk == nil {
		panic("gnoradio: billet inconnu")
	}
	return tk
}

func ownedBy(addr address) []int {
	if ids, ok := owned.Get(addr.String()).([]int); ok {
		return ids
	}
	return nil
}

func addOwned(addr address, id int) {
	owned.Set(addr.String(), append(append([]int(nil), ownedBy(addr)...), id))
}

func removeOwned(addr address, id int) {
	var out []int
	for _, x := range ownedBy(addr) {
		if x != id {
			out = append(out, x)
		}
	}
	owned.Set(addr.String(), out)
}

func tokenID(id int) grc721.TokenID { return grc721.TokenID(strconv.Itoa(id)) }

// updateTop keeps a short leaderboard sorted by value, highest first.
func updateTop(list []rank, k string, v int64, n int) []rank {
	out := make([]rank, 0, n+1)
	for _, r := range list {
		if r.key != k {
			out = append(out, r)
		}
	}
	i := len(out)
	for i > 0 && out[i-1].value < v {
		i--
	}
	if i >= n {
		return out
	}
	out = append(out, rank{})
	copy(out[i+1:], out[i:])
	out[i] = rank{k, v}
	if len(out) > n {
		out = out[:n]
	}
	return out
}

func parseSplits(s string, artist, self address) []Split {
	s = strings.TrimSpace(s)
	if s == "" {
		return nil
	}
	parts := strings.Split(s, ",")
	if len(parts) > maxSplits {
		panic("gnoradio: 4 collaborateurs maximum")
	}
	var out []Split
	var sum int64
	seen := map[string]bool{}
	for _, p := range parts {
		addrStr, pctStr, ok := strings.Cut(strings.TrimSpace(p), ":")
		to := address(strings.TrimSpace(addrStr))
		pct, err := strconv.ParseInt(strings.TrimSpace(strings.TrimSuffix(strings.TrimSpace(pctStr), "%")), 10, 64)
		if !ok || err != nil || !to.IsValid() || to == artist || to == self || seen[to.String()] || pct < 1 || pct > maxSplitPct {
			panic("gnoradio: collaborateurs au format g1...:30,g1...:15 (en %)")
		}
		seen[to.String()] = true
		sum += pct
		out = append(out, Split{To: to, Pct: pct})
	}
	if sum > maxSplitPct {
		panic("gnoradio: les collaborateurs peuvent recevoir 90 % maximum")
	}
	return out
}

// parseClock parses "m:ss" (or plain seconds) into seconds.
func parseClock(s string) (int64, bool) {
	s = strings.TrimSpace(s)
	m, sec, hasColon := strings.Cut(s, ":")
	if !hasColon {
		if s == "" || !digits(s) || len(s) > 5 {
			return 0, false
		}
		v, _ := strconv.ParseInt(s, 10, 64)
		return v, true
	}
	if m == "" || len(m) > 3 || len(sec) != 2 || !digits(m) || !digits(sec) {
		return 0, false
	}
	mv, _ := strconv.ParseInt(m, 10, 64)
	sv, _ := strconv.ParseInt(sec, 10, 64)
	if sv > 59 {
		return 0, false
	}
	return mv*60 + sv, true
}

// parseGNOT parses a decimal GNOT amount ("10", "2.5") into ugnot.
func parseGNOT(s string) (int64, bool) {
	s = strings.TrimSpace(s)
	whole, frac, _ := strings.Cut(s, ".")
	if whole == "" || len(whole) > 9 || len(frac) > 6 || !digits(whole) || !digits(frac) {
		return 0, false
	}
	w, _ := strconv.ParseInt(whole, 10, 64)
	f, _ := strconv.ParseInt(frac+strings.Repeat("0", 6-len(frac)), 10, 64)
	return w*ugnot + f, true
}

func digits(s string) bool {
	for _, c := range s {
		if c < '0' || c > '9' {
			return false
		}
	}
	return true
}
