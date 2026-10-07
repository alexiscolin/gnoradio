// Package tickets sells GnoRadio concert tickets as GRC721 NFTs drawn
// on-chain. Concerts belong to artist profiles of the catalog realm; ticket
// money goes straight to the artist's owner address in the same transaction.
package tickets

import (
	"chain"
	"chain/banker"
	"chain/runtime/unsafe"
	"strconv"
	"strings"
	"time"

	"gno.land/p/gnoradio/safe/v0"
	"gno.land/p/gnoradio/store/v0"
	"gno.land/p/gnoradio/text/v0"

	"gno.land/p/nt/avl/v0"
	"gno.land/p/nt/grc721/v0"
	"gno.land/p/nt/seqid/v0"

	"gno.land/r/gnoradio/catalog/v0"
)

const (
	denom          = "ugnot"
	ugnot          = 1_000_000
	minPrice       = 100_000 // 0.1 GNOT
	maxTicketPrice = 10_000 * ugnot
	maxCapacity    = 10000
	maxPerBuyer    = 4
	maxPerArtist   = 500       // concerts ever created
	maxOpenAhead   = 10        // future, not cancelled concerts per artist
	checkInWindow  = 12 * 3600 // check-in opens 12h before the concert
)

// Event is a concert. Values returned to other realms are copies.
type Event struct {
	ID        int
	ArtistID  int
	Title     string
	Venue     string
	Link      string // optional https link, public
	Start     int64
	Price     int64 // ugnot, 0 = free
	Capacity  int
	Sold      int
	Cancelled bool
	Hidden    bool
	Removed   string // the moderator's reason while hidden
}

type event struct {
	Event
}

// Ticket is one NFT ticket.
type Ticket struct {
	ID       int
	Event    int
	Serial   int
	Attended bool
}

var (
	admin  address
	frozen bool

	events       avl.Tree // padded id -> *event
	byArtist     avl.Tree // artistID padded + "/" + padded event id -> true
	artistEvents avl.Tree // padded artistID -> int (count)
	upcoming     avl.Tree // padded start + "/" + padded id -> *event (not cancelled, not hidden)
	artistAhead  avl.Tree // padded artistID + "/" + padded start + "/" + padded id -> true (not cancelled)
	// A ticket is a few short records: with the grc721 ledger's own
	// entries, about 6KB of deposit per ticket instead of about 11KB with
	// avl nodes and a struct (more than many ticket prices).
	tickets  = store.NewSeq(16)    // id-1 -> event, serial, attended
	owned    = store.NewMap(65536) // owner -> sorted packed ticket ids (the grc721 ledger cannot list by owner)
	buyers   = store.NewMap(65536) // event id + "/" + address -> tickets bought
	attended avl.Tree              // holder -> int
	nEvents  int
	nTickets int

	ticketTok *grc721.Token
	ticketLed *grc721.PrivateLedger
	tokSeq    seqid.ID
)

func init() {
	admin = unsafe.OriginCaller()
}

// CreateEvent announces a concert by the caller's artist profile.
// start is "YYYY-MM-DD HH:MM" in UTC; price is in GNOT ("0" for free, "2.5");
// link is an optional https URL (stream or venue page, public).
func CreateEvent(cur realm, title, venue, link, start, price string, capacity int) int {
	caller := userCaller(cur)
	noPayment()
	notFrozen()
	artistID := mustArtistOf(caller)
	if n, _ := artistEvents.Get(text.Key(artistID)).(int); n >= maxPerArtist {
		panic("tickets: concert limit reached for this artist")
	}
	if openAhead(artistID) >= maxOpenAhead {
		panic("tickets: an artist can announce " + itoa(maxOpenAhead) + " upcoming concerts at a time")
	}
	title, venue, link = strings.TrimSpace(title), strings.TrimSpace(venue), strings.TrimSpace(link)
	mustText("title", title, 2, 48)
	mustText("venue", venue, 2, 48)
	if link != "" && !validURL(link) {
		panic("tickets: link must start with https:// (max 200 chars, no spaces)")
	}
	when, err := time.Parse("2006-01-02 15:04", strings.TrimSpace(start))
	if err != nil {
		panic("tickets: start must look like 2026-11-20 21:00 (UTC)")
	}
	if when.Unix() <= now() {
		panic("tickets: the concert must be in the future")
	}
	p, ok := parseGNOT(price)
	if !ok || p > maxTicketPrice || (p > 0 && p < minPrice) {
		panic("tickets: price must be 0 (free) or between 0.1 and 10000 GNOT")
	}
	if capacity < 1 || capacity > maxCapacity {
		panic("tickets: capacity must be between 1 and 10000")
	}
	nEvents++
	e := &event{Event: Event{ID: nEvents, ArtistID: artistID, Title: title, Venue: venue, Link: link,
		Start: when.Unix(), Price: p, Capacity: capacity}}
	events.Set(text.Key(e.ID), e)
	byArtist.Set(text.Key(artistID)+"/"+text.Key(e.ID), true)
	upcoming.Set(upKey(e), e)
	artistAhead.Set(text.Key(artistID)+"/"+upKey(e), true)
	n, _ := artistEvents.Get(text.Key(artistID)).(int)
	artistEvents.Set(text.Key(artistID), n+1)
	chain.Emit("EventCreated", "id", itoa(e.ID), "artist", itoa(artistID), "start", itoa64(e.Start), "price", itoa64(p))
	return e.ID
}

// CancelEvent stops ticket sales. Payments already went to the artist, who
// handles refunds directly. Artist owner only.
func CancelEvent(cur realm, eventID int) {
	caller := userCaller(cur)
	noPayment()
	e := mustEvent(eventID)
	if catalog.ArtistOwner(e.ArtistID) != caller {
		panic("tickets: only the artist can cancel this concert")
	}
	e.Cancelled = true
	upcoming.Remove(upKey(e))
	artistAhead.Remove(text.Key(e.ArtistID) + "/" + upKey(e))
	chain.Emit("EventCancelled", "id", itoa(e.ID))
}

// artistVerified gates paid tickets like tips (tests swap it: the catalog
// admin is unreachable from this package under gno test).
var artistVerified = catalog.ArtistVerified

// BuyTicket mints a GRC721 ticket to the caller; the exact price must be
// attached and goes straight to the artist.
func BuyTicket(cur realm, eventID int) int {
	caller := userCaller(cur)
	notFrozen()
	e := mustEvent(eventID)
	if e.Cancelled {
		panic("tickets: this concert is cancelled")
	}
	if now() >= e.Start {
		panic("tickets: ticket sales are closed")
	}
	if e.Sold >= e.Capacity {
		panic("tickets: sold out")
	}
	owner := catalog.ArtistOwner(e.ArtistID)
	if e.Price > 0 && (owner == "" || !artistVerified(e.ArtistID)) {
		panic("tickets: this artist has not verified their profile yet")
	}
	buyKey := itoa(e.ID) + "/" + caller.String()
	b, _ := buyers.Get(buyKey)
	bought := atoi(b)
	if bought >= maxPerBuyer || (e.Price == 0 && bought >= 1) {
		panic("tickets: ticket limit reached for this concert (1 free or 4 paid per wallet)")
	}
	fee := int64(0)
	if e.Price == 0 {
		noPayment()
	} else {
		fee = serviceFee
		if fee > 0 && !catalog.Treasury().IsValid() {
			panic("tickets: the GnoRadio treasury is not set")
		}
		if paid() != e.Price+fee {
			panic("tickets: attach exactly " + text.GNOT(e.Price+fee))
		}
	}

	if ticketTok == nil {
		ticketTok, ticketLed = grc721.NewToken("GnoRadio Ticket", "GRTIX", tokSeq.Next(), cur)
	}
	e.Sold++
	buyers.Set(buyKey, itoa(bought+1))
	nTickets++
	tk := &Ticket{ID: nTickets, Event: e.ID, Serial: e.Sold}
	tickets.Append(ticketRecord(tk))
	if err := ticketLed.Mint(caller, tokenID(tk.ID)); err != nil {
		panic("tickets: " + err.Error())
	}
	addOwned(caller, tk.ID)
	if e.Price > 0 {
		bk := banker.NewBanker(banker.BankerTypeRealmSend, cur)
		bk.SendCoins(cur.Address(), owner, chain.Coins{{Denom: denom, Amount: e.Price}})
		if fee > 0 {
			bk.SendCoins(cur.Address(), catalog.Treasury(), chain.Coins{{Denom: denom, Amount: fee}})
		}
	}
	chain.Emit("TicketBought", "event", itoa(e.ID), "ticket", itoa(tk.ID), "by", caller.String(), "price", itoa64(e.Price), "fee", itoa64(fee))
	return tk.ID
}

// TransferTicket gives one of the caller's tickets to someone else. There is
// no built-in resale market.
func TransferTicket(cur realm, to address, ticketID int) {
	caller := userCaller(cur)
	noPayment()
	tk := mustTicket(ticketID)
	if tk.Attended {
		panic("tickets: a checked-in ticket can no longer be gifted")
	}
	if !to.IsValid() || to == caller || to == cur.Address() {
		panic("tickets: invalid recipient")
	}
	if err := ticketLed.TransferFrom(caller, caller, to, tokenID(ticketID)); err != nil {
		panic("tickets: you do not hold this ticket")
	}
	removeOwned(caller, ticketID)
	addOwned(to, ticketID)
	chain.Emit("TicketGifted", "ticket", itoa(ticketID), "from", caller.String(), "to", to.String())
}

// CheckIn marks a ticket as used at the door; its holder earns the
// "I was there" stamp. The concert's artist owner only, from 12h before.
func CheckIn(cur realm, ticketID int) {
	caller := userCaller(cur)
	noPayment()
	tk := mustTicket(ticketID)
	e := mustEvent(tk.Event)
	if catalog.ArtistOwner(e.ArtistID) != caller {
		panic("tickets: only the concert's artist can check tickets in")
	}
	if e.Cancelled {
		panic("tickets: this concert is cancelled")
	}
	if now() < e.Start-checkInWindow {
		panic("tickets: check-in opens 12h before the concert")
	}
	if tk.Attended {
		panic("tickets: ticket already checked in")
	}
	tk.Attended = true
	tickets.Set(tk.ID-1, ticketRecord(tk))
	holder := TicketOwner(ticketID)
	n, _ := attended.Get(holder.String()).(int)
	attended.Set(holder.String(), n+1)
	chain.Emit("CheckedIn", "ticket", itoa(ticketID), "holder", holder.String())
}

// ---- moderation ----

// HideEvent hides or restores a concert. Admin only; hiding takes a public
// reason (4-200 characters). Tickets stay with their holders.
func HideEvent(cur realm, eventID int, hidden bool, reason string) {
	onlyAdmin(cur)
	e := getEvent(eventID)
	if e == nil {
		panic("tickets: unknown concert")
	}
	reason = strings.TrimSpace(reason)
	if hidden {
		mustText("reason", reason, 4, 200)
	} else {
		reason = ""
	}
	e.Hidden, e.Removed = hidden, reason
	if hidden || e.Cancelled {
		upcoming.Remove(upKey(e))
	} else {
		upcoming.Set(upKey(e), e)
	}
	chain.Emit("Moderated", "kind", "event", "target", itoa(eventID), "hidden", strconv.FormatBool(hidden), "reason", reason, "by", "moderator")
}

// RefreshArtist re-reads an artist's visibility in the catalog and updates
// the Upcoming index for its future concerts (at most maxOpenAhead): once
// moderators hide a profile, its concerts stop taking places in the
// Upcoming scan; a restored artist's come back. Anyone may call it.
func RefreshArtist(cur realm, artistID int) {
	noPayment()
	prefix := text.Key(artistID) + "/"
	var evs []*event
	artistAhead.Iterate(prefix+key64(now()+1), prefix+"~", func(k string, _ any) bool {
		id, _ := strconv.Atoi(k[strings.LastIndex(k, "/")+1:])
		evs = append(evs, getEvent(id))
		return false
	})
	for _, e := range evs {
		if visible(e) && !e.Cancelled {
			upcoming.Set(upKey(e), e)
		} else {
			upcoming.Remove(upKey(e))
		}
	}
	chain.Emit("ArtistRefreshed", "artist", itoa(artistID), "concerts", itoa(len(evs)))
}

func TransferAdmin(cur realm, to address) {
	onlyAdmin(cur)
	if !to.IsValid() {
		panic("tickets: invalid address")
	}
	chain.Emit("AdminTransferred", "from", admin.String(), "to", to.String())
	admin = to
}

// Freeze stops new concerts and sales; gifting and check-in keep working.
func Freeze(cur realm, on bool) {
	onlyAdmin(cur)
	frozen = on
	chain.Emit("Frozen", "on", strconv.FormatBool(on))
}

// ---- read API (values only) ----

// TicketOwner returns the current holder of a ticket.
func TicketOwner(ticketID int) address {
	mustTicket(ticketID)
	owner, err := ticketTok.OwnerOf(tokenID(ticketID))
	if err != nil {
		panic(err.Error())
	}
	return owner
}

// EventInfo returns a copy of a visible concert; ok is false otherwise.
func EventInfo(id int) (Event, bool) {
	e := getEvent(id)
	if !visible(e) {
		return Event{}, false
	}
	return e.Event, true
}

// HiddenNote says why a concert is hidden: "Removed by moderation: <reason>", or "".
func HiddenNote(eventID int) string {
	if e := getEvent(eventID); e != nil && e.Hidden {
		return "Removed by moderation: " + e.Removed
	}
	return ""
}

// TicketInfo returns a copy of a ticket.
func TicketInfo(id int) (Ticket, bool) {
	tk := getTicket(id)
	if tk == nil {
		return Ticket{}, false
	}
	return *tk, true
}

func EventCount() int  { return nEvents }
func TicketCount() int { return nTickets }

// Attended returns how many concerts a holder checked in at.
func Attended(holder address) int {
	n, _ := attended.Get(holder.String()).(int)
	return n
}

// TicketsOf returns up to limit ticket ids held by owner, newest first.
func TicketsOf(owner address, offset, limit int) []int {
	if limit < 1 || limit > 50 {
		limit = 50
	}
	if offset < 0 {
		offset = 0
	}
	list, _ := owned.Get(owner.String())
	return store.Page(list, offset, limit, true)
}

// ArtistEvents returns up to limit concert ids of an artist, newest first.
func ArtistEvents(artistID, limit int) []int {
	if limit < 1 || limit > 50 {
		limit = 50
	}
	var ids []int
	prefix := text.Key(artistID) + "/"
	byArtist.ReverseIterate(prefix, prefix+"~", func(k string, _ any) bool {
		if e := getEvent(atoi(k[len(prefix):])); visible(e) {
			ids = append(ids, e.ID)
		}
		return len(ids) >= limit
	})
	return ids
}

// Upcoming returns up to n visible, not cancelled future concerts, soonest
// first.
func Upcoming(n int) []Event {
	if n < 1 || n > 50 {
		n = 50
	}
	var out []Event
	eachUpcoming(func(e *event) bool {
		out = append(out, e.Event)
		return len(out) >= n
	})
	return out
}

// eachUpcoming walks the visible future concerts, soonest first, until fn
// returns true. Past entries are skipped by starting the walk at now.
func eachUpcoming(fn func(e *event) bool) {
	scanned := 0
	upcoming.Iterate(key64(now()+1), "", func(_ string, v any) bool {
		e := v.(*event)
		scanned++
		if visible(e) && !e.Cancelled && fn(e) {
			return true
		}
		return scanned >= 1000
	})
}

// openAhead counts the artist's future, not cancelled concerts.
func openAhead(artistID int) int {
	n := 0
	prefix := text.Key(artistID) + "/"
	artistAhead.Iterate(prefix+key64(now()+1), prefix+"~", func(_ string, _ any) bool {
		n++
		return false
	})
	return n
}

// ---- helpers ----

func now() int64 { return time.Now().Unix() }

func userCaller(cur realm) address {
	if !cur.Previous().IsUserCall() {
		panic("tickets: call this directly from your wallet")
	}
	return cur.Previous().Address()
}

func onlyAdmin(cur realm) {
	if cur.Previous().Address() != admin {
		panic("tickets: moderators only")
	}
	noPayment()
}

func notFrozen() {
	if frozen {
		panic("tickets: GnoRadio tickets are paused (migration in progress)")
	}
}

func noPayment() {
	if len(unsafe.OriginSend()) != 0 {
		panic("tickets: this action takes no coins")
	}
}

// paid returns the ugnot attached to the call; anything else is refused.
func paid() int64 {
	sent := unsafe.OriginSend()
	if len(sent) != 1 || sent[0].Denom != denom || sent[0].Amount <= 0 {
		panic("tickets: attach a single ugnot amount")
	}
	return sent[0].Amount
}

func mustArtistOf(addr address) int {
	id := catalog.ArtistOf(addr)
	if id == 0 || !catalog.ArtistVisible(id) {
		panic("tickets: create your artist profile first")
	}
	return id
}

func key64(n int64) string {
	s := strconv.FormatInt(n, 10)
	return strings.Repeat("0", 12-len(s)) + s
}

func upKey(e *event) string { return key64(e.Start) + "/" + text.Key(e.ID) }

func getEvent(id int) *event {
	if e, ok := events.Get(text.Key(id)).(*event); ok {
		return e
	}
	return nil
}

// artistVisible is a test seam: the catalog admin, who hides artists, is
// unreachable from this package under gno test.
var artistVisible = catalog.ArtistVisible

func visible(e *event) bool {
	return e != nil && !e.Hidden && artistVisible(e.ArtistID)
}

func mustEvent(id int) *event {
	e := getEvent(id)
	if !visible(e) {
		panic("tickets: unknown concert")
	}
	return e
}

// getTicket decodes a ticket (a copy: save changes with ticketRecord).
func getTicket(id int) *Ticket {
	rec, ok := tickets.Get(id - 1)
	if !ok {
		return nil
	}
	f := store.Fields(rec)
	return &Ticket{ID: id, Event: atoi(f[0]), Serial: atoi(f[1]), Attended: f[2] != ""}
}

func ticketRecord(tk *Ticket) string {
	att := ""
	if tk.Attended {
		att = "1"
	}
	return store.Rec(itoa(tk.Event), itoa(tk.Serial), att)
}

func mustTicket(id int) *Ticket {
	tk := getTicket(id)
	if tk == nil {
		panic("tickets: unknown ticket")
	}
	return tk
}

func addOwned(addr address, id int) {
	list, _ := owned.Get(addr.String())
	list, _ = store.Add(list, id)
	owned.Set(addr.String(), list)
}

func removeOwned(addr address, id int) {
	list, _ := owned.Get(addr.String())
	if list, _ = store.Remove(list, id); list == "" {
		owned.Remove(addr.String())
	} else {
		owned.Set(addr.String(), list)
	}
}

func tokenID(id int) grc721.TokenID { return grc721.TokenID(strconv.Itoa(id)) }

func mustText(field, s string, min, max int) {
	if !text.Valid(s, min, max) {
		panic("tickets: " + field + " must be " + itoa(min) + "-" + itoa(max) +
			" characters (letters, digits, spaces and . , ' - ! ? : / &)")
	}
	if safe.Slur(s) {
		panic("tickets: " + field + " holds a slur")
	}
}

func validURL(s string) bool {
	if !strings.HasPrefix(s, "https://") || len(s) <= 10 || len(s) > 200 {
		return false
	}
	for _, c := range s {
		switch {
		case c >= 'a' && c <= 'z', c >= 'A' && c <= 'Z', c >= '0' && c <= '9':
		case strings.ContainsRune("-._~:/?#=&%+@", c):
		default:
			return false
		}
	}
	return true
}

// parseGNOT parses a decimal GNOT amount ("10", "2.5") into ugnot.
func parseGNOT(s string) (int64, bool) {
	s = strings.TrimSpace(s)
	whole, frac, _ := strings.Cut(s, ".")
	if whole == "" || len(whole) > 9 || len(frac) > 6 || !text.Digits(whole) || (frac != "" && !text.Digits(frac)) {
		return 0, false
	}
	w, _ := strconv.ParseInt(whole, 10, 64)
	f, _ := strconv.ParseInt(frac+strings.Repeat("0", 6-len(frac)), 10, 64)
	return w*ugnot + f, true
}

func itoa(n int) string     { return strconv.Itoa(n) }
func itoa64(n int64) string { return strconv.FormatInt(n, 10) }

func atoi(s string) int {
	n, err := strconv.Atoi(s)
	if err != nil {
		return 0
	}
	return n
}

func date(unix int64) string { return time.Unix(unix, 0).UTC().Format("2006-01-02 15:04") + " UTC" }

// serviceFee is paid by buyers of paid tickets, on top of the price (which
// still goes 100% to the artist), and forwarded to the GnoRadio treasury.
var serviceFee int64

const maxServiceFee = 10 * 1_000_000

// SetServiceFee sets the per-ticket service fee in ugnot (0..10 GNOT). Admin only.
func SetServiceFee(cur realm, ugnot int64) {
	onlyAdmin(cur)
	if ugnot < 0 || ugnot > maxServiceFee {
		panic("tickets: service fee must be between 0 and 10 GNOT")
	}
	serviceFee = ugnot
	chain.Emit("ServiceFee", "ugnot", itoa64(ugnot))
}

// ServiceFee returns the current per-ticket service fee in ugnot.
func ServiceFee() int64 { return serviceFee }
