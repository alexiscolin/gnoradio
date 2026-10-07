package radio

import (
	"chain"

	"gno.land/p/gnoradio/store/v0"
	"gno.land/p/gnoradio/text/v0"

	"gno.land/r/gnoradio/catalog/v0"
)

// Sponsored picks: an artist's promo budget (catalog/sponsor.gno) refunds a
// listener's pick of their track, about what the pick costs. The listener
// chooses it (QueueSponsored) instead of a normal pick; the artist's refund is
// reserved at once, and the listener collects it (ClaimPickPayout, one
// signature, their gas) once the slot has aired in full. A slot dropped or cut
// before its end gives the reservation back; one not collected within 7 days
// lapses back to the budget by itself.
//
// Farming with throwaway wallets earns at most the pick cost back, and these
// rules keep it rare: a wallet needs a first pick 7 days old and 3 normal
// picks in the last 30 days (two 15-day counters in the curator record: the
// current period and the one before, so the window is 15 to 30 days, never
// more);
// one sponsored pick per artist per station and hour; sponsored airtime at
// most a quarter of the 2 hours listeners may program; and per wallet one per
// artist and three a day (the catalog). They earn no curator point, do not
// join Listeners' choice and carry no dedication.

const (
	repPeriod     = 15 * 24 * 3600 // reputation counters roll over every 15 days
	repAge        = 7 * 24 * 3600  // a wallet's first pick must be this old
	repPicks      = 3              // normal picks this period and the one before
	sponsorShare  = maxAheadAir / 4
	sponsorWindow = 3600
	sponsorClaim  = 7 * 24 * 3600 // the catalog lets a reservation lapse after this
)

var (
	sponsor = store.NewMap(65536) // station + "/" + address -> start, track, end, ugnot, held, reserved (one open sponsored pick per wallet and station; held: the end the catalog reserved for; reserved: when, unix)

	// Test seams: radio tests cannot verify an artist; catalog/sponsor_test.gno covers the money.
	promoReserve   = catalog.PromoReserve
	promoClaim     = catalog.PromoClaim
	promoRelease   = catalog.PromoRelease
	promoClaimable = catalog.PromoClaimable
)

// QueueSponsored is Queue paid by the artist: once the pick has aired in
// full, ClaimPickPayout sends the picker the artist's refund (catalog
// PromoOffer). No dedication. A wallet has one sponsored pick open per
// station: it must be collected (or have lapsed) before the next.
func QueueSponsored(cur realm, stationID, trackID int) {
	QueueSponsoredAt(cur, stationID, trackID, 0)
}

// QueueSponsoredAt is QueueSponsored for a chosen time (see QueueAt; 0: now).
// The refund lapses 7 days after the booked time plus the track's length.
func QueueSponsoredAt(cur realm, stationID, trackID int, at int64) {
	caller := userCaller(cur)
	if why := sponsorBlock(caller); why != "" {
		panic("radio: " + why)
	}
	mustStation(stationID)
	if rec, ok := sponsor.Get(sponsorKey(stationID, caller)); ok {
		f := store.Fields(rec)
		if now() < atoi64(f[2])+sponsorClaim {
			panic("radio: collect your last sponsored pick on this station first")
		}
	}
	queue(cur, caller, stationID, trackID, false, true, "", at)
}

// ClaimPickPayout sends the caller the refund of their sponsored pick that
// started at start on stationID, once it has aired in full. It works while
// GnoRadio is frozen: a freeze must not let a refund lapse.
func ClaimPickPayout(cur realm, stationID int, start int64) {
	caller := userCaller(cur)
	noPayment()
	mustStation(stationID)
	k := sponsorKey(stationID, caller)
	rec, ok := sponsor.Get(k)
	if !ok || atoi64(store.Field(rec, 0)) != start {
		panic("radio: no sponsored pick of yours to collect at this time")
	}
	f := store.Fields(rec)
	track, amt, held := atoi(f[1]), atoi64(f[3]), atoi64(f[4])
	status := payoutStatus(f)
	if status == "airing" {
		panic("radio: your pick has not finished airing yet")
	}
	sponsor.Remove(k)
	// A removed track, a cancelled sponsorship or a lapsed refund leaves
	// nothing to pay: the record goes, so the next sponsored pick is open.
	if status == "lapsed" {
		chain.Emit("PickPayoutVoid", "station", itoa(stationID), "start", itoa64(start), "track", itoa(track), "to", caller.String())
		return
	}
	promoClaim(cross(cur), track, caller, held, amt)
	c := nums(curators, caller.String(), 8)
	c[3] += amt
	putCurator(caller.String(), c)
	chain.Emit("PickPaid", "station", itoa(stationID), "start", itoa64(start), "track", itoa(track), "to", caller.String(), "amount", itoa64(amt))
}

// sponsorBlock says why a wallet may not take sponsored picks yet ("" when it may).
func sponsorBlock(addr address) string {
	c := nums(curators, addr.String(), 8)
	ts := now()
	if c[4] == 0 || ts-c[4] < repAge {
		return "sponsored picks open 7 days after your first pick"
	}
	recent := int64(0)
	switch ts / repPeriod {
	case c[5]:
		recent = c[6] + c[7]
	case c[5] + 1:
		recent = c[6]
	}
	if recent < repPicks {
		return "sponsored picks need 3 normal picks in the last 30 days"
	}
	return ""
}

// sponsorQuota: one sponsored pick per artist per station and hour, and
// sponsored airtime at most a quarter of the listener window, both around
// airs (now, or the time booked).
func sponsorQuota(st *station, artistID int, dur, airs int64) {
	air := dur
	for _, s := range st.schedule {
		if s.Pay == 0 {
			continue
		}
		if end := s.Start + s.Dur; end > airs && s.Start < airs+maxAheadAir {
			air += end - max64(s.Start, airs)
		}
		if s.Start+s.Dur > airs-sponsorWindow && s.Start < airs+sponsorWindow {
			if a, _, _, _ := catalog.TrackBrief(s.Track); a == artistID {
				panic("radio: this artist already has a sponsored pick this hour here, pick it normally")
			}
		}
	}
	if air > sponsorShare {
		panic("radio: sponsored picks are full on this station for now, pick normally")
	}
}

// reserve books the artist's refund for a sponsored slot, lapsing after held.
func reserve(cur realm, picker address, stationID, trackID int, start, dur, held int64) int64 {
	amt := promoReserve(cross(cur), trackID, picker, held)
	sponsor.Set(sponsorKey(stationID, picker), store.Rec(itoa64(start), itoa(trackID), itoa64(start+dur), itoa64(amt), itoa64(held), itoa64(now())))
	return amt
}

// held is the end the catalog reserves a sponsored slot's refund for: a
// booked slot keeps the one of its time even if it moves to a boundary.
func (s Slot) held() int64 {
	if s.At > 0 {
		return s.At + s.Dur
	}
	return s.Start + s.Dur
}

// hold is a sponsored slot's reservation in the catalog: filed under the end
// it was reserved for (the slot may have moved since). reserved is when it
// was taken, 0 once the slot started airing: only a pick that never aired
// gives its daily counts back.
type hold struct {
	track                int
	picker               address
	held, paid, reserved int64
}

// unsponsor forgets the open record of a sponsored slot that will not air in
// full (cut at ts); it returns the reservation, ok false when there was none.
func unsponsor(stationID int, s Slot, ts int64) (hold, bool) {
	k := sponsorKey(stationID, s.By)
	rec, ok := sponsor.Get(k)
	if !ok || atoi64(store.Field(rec, 0)) != s.Start {
		return hold{}, false
	}
	sponsor.Remove(k)
	f := store.Fields(rec)
	h := hold{s.Track, s.By, atoi64(f[4]), s.Pay, atoi64(f[5])}
	if s.Start < ts {
		h.reserved = 0 // it partly aired
	}
	return h, true
}

// release gives the reservations of cut sponsored slots back to their artists.
func release(cur realm, cut []hold) {
	for _, h := range cut {
		promoRelease(cross(cur), h.track, h.picker, h.held, h.paid, h.reserved)
	}
}

func sponsorKey(stationID int, addr address) string { return itoa(stationID) + "/" + addr.String() }

func max64(a, b int64) int64 {
	if a > b {
		return a
	}
	return b
}

// PickPayoutStatus says what ClaimPickPayout would do for addr's sponsored
// pick that started at start on stationID: "ok" (it pays), "airing" (not
// finished yet), "lapsed" (nothing to pay: lapsed, cancelled or the track was
// removed; collecting only clears it) or "none" (no such open pick).
func PickPayoutStatus(addr address, stationID int, start int64) string {
	rec, ok := sponsor.Get(sponsorKey(stationID, addr))
	if !ok || atoi64(store.Field(rec, 0)) != start {
		return "none"
	}
	return payoutStatus(store.Fields(rec))
}

func payoutStatus(f []string) string {
	track, end, amt, held := atoi(f[1]), atoi64(f[2]), atoi64(f[3]), atoi64(f[4])
	if now() < end {
		return "airing"
	}
	if _, _, _, ok := catalog.TrackBrief(track); !ok || !promoClaimable(track, held, amt) {
		return "lapsed"
	}
	return "ok"
}

// SponsoredJSON lists a wallet's sponsored picks not collected yet, with
// whether it may take new ones and each one's PickPayoutStatus:
// {"block":"why not, or empty","open":[{"station","start","track","end","amount","status"}]}.
func SponsoredJSON(addr address) string {
	out := `{"block":` + text.Str(sponsorBlock(addr)) + `,"open":[`
	n := 0
	for id := range stations {
		rec, ok := sponsor.Get(sponsorKey(id, addr))
		if !ok {
			continue
		}
		f := store.Fields(rec)
		if n > 0 {
			out += ","
		}
		out += `{"station":` + itoa(id) + `,"start":` + f[0] + `,"track":` + f[1] + `,"end":` + f[2] + `,"amount":` + f[3] + `,"status":"` + payoutStatus(f) + `"}`
		n++
	}
	return out + `]}`
}

// OnAirPay is the refund of the sponsored pick on air (0: none), for labels.
func OnAirPay(stationID int) int64 {
	ts := now()
	for _, s := range mustStation(stationID).schedule {
		if ts >= s.Start && ts < s.Start+s.Dur {
			return s.Pay
		}
	}
	return 0
}
