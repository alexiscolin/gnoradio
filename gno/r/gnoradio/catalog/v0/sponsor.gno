package catalog

import (
	"chain"
	"chain/banker"
	"strings"

	"gno.land/p/gnoradio/store/v0"
	"gno.land/p/gnoradio/text/v0"
)

// Sponsored picks: a verified artist funds a budget that refunds the cost of
// a listener's pick of their track (fee and deposit, ~0.03 GNOT) once it has
// aired in full. It is a refund, not paid listening: the payout stays near the
// pick cost so throwaway wallets gain nothing by farming it, and the radio
// adds airtime and reputation rules (radio/sponsor.gno).
//
// The coins stay in this realm, accounted exactly: promoHeld is the sum of
// every budget's balance and this realm keeps no other coins (tips and
// support leave in the transaction that brings them). The radio reserves the
// payout when the pick is queued; the reservation is paid when the pick has
// aired, released if the slot is dropped, and lapses by itself claimDays after
// the slot ends. The funder withdraws the rest at any time, frozen or not:
// no admin call touches these funds.

const (
	defaultPickPay = 30_000 // ugnot per aired sponsored pick, 0.03 GNOT
	minPickPay     = 10_000
	maxPickPay     = 50_000 // near the pick cost: a refund, never a wage
	maxPickPerDay  = 100    // the artist's own daily limit, 0 = none
	walletPicksDay = 3      // sponsored picks per listener per UTC day, one per artist
	claimDays      = 7      // a reservation lapses this long after the slot ends
	daySecs        = 24 * 3600
)

var (
	budgets   = store.NewMap(8192)  // artist id -> budget record
	walletDay = store.NewMap(65536) // listener -> UTC day, artist ids sponsored that day
	promoHeld int64                 // ugnot held for budgets, reservations included
)

type budget struct {
	Funder address // who put the coins in and alone takes them out
	Balance int64  // held for the artist, reservations included
	Pay     int64  // per aired sponsored pick, 0 = paused
	PerDay  int    // sponsored picks a day, 0 = no limit
	Day     int64  // UTC day of Today
	Today   int
	Funded  int64
	Paid    int64
	Picks   int
	Holds   string // reservations "expiryDay:ugnot,..." by the day they lapse
}

func getBudget(artistID int) (budget, bool) {
	rec, ok := budgets.Get(itoa(artistID))
	if !ok {
		return budget{}, false
	}
	f := store.Fields(rec)
	return budget{Funder: address(f[0]), Balance: atoi64(f[1]), Pay: atoi64(f[2]), PerDay: atoi(f[3]), Day: atoi64(f[4]),
		Today: atoi(f[5]), Funded: atoi64(f[6]), Paid: atoi64(f[7]), Picks: atoi(f[8]), Holds: f[9]}, true
}

func putBudget(artistID int, b budget) {
	budgets.Set(itoa(artistID), store.Rec(b.Funder.String(), itoa64(b.Balance), itoa64(b.Pay), itoa(b.PerDay), itoa64(b.Day),
		itoa(b.Today), itoa64(b.Funded), itoa64(b.Paid), itoa(b.Picks), b.Holds))
}

// holds reads the reservations still live on day today, and the one lapsing on day e.
func holds(list string, today, e int64) (live, atE int64) {
	for _, p := range strings.Split(list, ",") {
		d, v, ok := strings.Cut(p, ":")
		if ok && atoi64(d) >= today {
			live += atoi64(v)
			if atoi64(d) == e {
				atE += atoi64(v)
			}
		}
	}
	return live, atE
}

// addHold adds delta to the reservations lapsing on day e and drops lapsed ones.
func addHold(list string, today, e, delta int64) string {
	var out []string
	for _, p := range strings.Split(list, ",") {
		d, v, ok := strings.Cut(p, ":")
		if !ok || atoi64(d) < today {
			continue
		}
		n := atoi64(v)
		if atoi64(d) == e {
			n, delta = n+delta, 0
		}
		if n > 0 {
			out = append(out, d+":"+itoa64(n))
		}
	}
	if delta > 0 {
		out = append(out, itoa64(e)+":"+itoa64(delta))
	}
	return strings.Join(out, ",")
}

// lapseDay is the last UTC day a pick ending at end can be paid.
func lapseDay(end int64) int64 { return (end + claimDays*daySecs) / daySecs }

// free is what the funder may withdraw and new picks may reserve.
func (b budget) free(today int64) int64 {
	live, _ := holds(b.Holds, today, -1)
	return b.Balance - live
}

// FundPromo adds the attached ugnot to the caller's sponsored-pick budget. A
// new budget pays defaultPickPay per aired pick (SetPromoPay changes it). If
// the profile changed hands since the last funding, the previous funder gets
// their whole balance back first, reservations included.
func FundPromo(cur realm) {
	caller := userCaller(cur)
	notFrozen()
	amt := paid()
	if amt < minTip || amt > maxTip {
		panic("catalog: a promo budget takes 0.1 to 1000000 GNOT")
	}
	a := ownArtist(caller)
	if !a.Verified {
		panic("catalog: verify your profile first")
	}
	b, ok := getBudget(a.ID)
	if !ok {
		b.Pay = defaultPickPay
	}
	if b.Funder != "" && b.Funder != caller && b.Balance > 0 {
		sendHeld(cur, b.Funder, b.Balance)
		emitEvent("PromoWithdrawn", "artist", itoa(a.ID), "to", b.Funder.String(), "amount", itoa64(b.Balance))
		b.Balance, b.Holds = 0, ""
	}
	b.Funder = caller
	b.Balance += amt
	b.Funded += amt
	promoHeld += amt
	putBudget(a.ID, b)
	emitEvent("PromoFunded", "artist", itoa(a.ID), "by", caller.String(), "amount", itoa64(amt), "balance", itoa64(b.Balance))
}

// SetPromoPay sets what each aired sponsored pick of the caller's tracks
// refunds (10 000..50 000 ugnot, 0 pauses) and an optional daily limit
// (0 = none, at most 100).
func SetPromoPay(cur realm, ugnotPerPick int64, perDay int) {
	caller := userCaller(cur)
	noPayment()
	notFrozen()
	if ugnotPerPick != 0 && (ugnotPerPick < minPickPay || ugnotPerPick > maxPickPay) {
		panic("catalog: a sponsored pick refunds 0.01 to 0.05 GNOT (0 pauses)")
	}
	if perDay < 0 || perDay > maxPickPerDay {
		panic("catalog: the daily limit is 0 (none) to 100 picks")
	}
	a := ownArtist(caller)
	b, _ := getBudget(a.ID)
	b.Pay, b.PerDay = ugnotPerPick, perDay
	putBudget(a.ID, b)
	emitEvent("PromoPay", "artist", itoa(a.ID), "pay", itoa64(ugnotPerPick), "perDay", itoa(perDay))
}

// WithdrawPromo sends the caller the unreserved part of a budget they funded.
// It works whatever happened to the profile (hidden, unverified, new owner)
// and while GnoRadio is frozen: funds are never stuck.
func WithdrawPromo(cur realm, artistID int) {
	caller := userCaller(cur)
	noPayment()
	b, _ := getBudget(artistID)
	free := b.free(now() / daySecs)
	if b.Funder != caller || free <= 0 {
		panic("catalog: nothing of yours to withdraw from this budget")
	}
	sendHeld(cur, caller, free)
	b.Balance -= free
	putBudget(artistID, b)
	emitEvent("PromoWithdrawn", "artist", itoa(artistID), "to", caller.String(), "amount", itoa64(free))
}

// PromoReserve reserves the refund of a sponsored pick of trackID by picker
// whose slot ends at end. Only the radio realm may call it (radio.QueueSponsored);
// it panics with the reason when the pick cannot be sponsored.
func PromoReserve(cur realm, trackID int, picker address, end int64) int64 {
	onlyRadio(cur.Previous().PkgPath())
	notFrozen()
	t := mustTrack(trackID)
	a := getArtist(t.Artist)
	b, _ := getBudget(a.ID)
	if a.Hidden || !a.Verified || a.Owner == "" || b.Funder != a.Owner || b.Pay == 0 {
		panic("catalog: this artist does not sponsor picks right now")
	}
	own := picker == a.Owner || !picker.IsValid() || isSibling(picker)
	for _, s := range t.Splits {
		own = own || s.To == picker
	}
	if own {
		panic("catalog: the artist and collaborators cannot take a sponsored pick")
	}
	today := now() / daySecs
	if b.Day != today {
		b.Day, b.Today = today, 0
	}
	if b.PerDay > 0 && b.Today >= b.PerDay {
		panic("catalog: this artist's sponsored picks for today are taken, pick it normally")
	}
	if b.free(today) < b.Pay {
		panic("catalog: this artist's promo budget is empty, pick it normally")
	}
	wd, _ := walletDay.Get(picker.String())
	day, list, _ := strings.Cut(wd, "|")
	if atoi64(day) != today {
		list = ""
	}
	if strings.Contains(","+list, ","+itoa(a.ID)+",") {
		panic("catalog: one sponsored pick per artist a day, pick it normally")
	}
	if strings.Count(list, ",") >= walletPicksDay {
		panic("catalog: three sponsored picks a day, pick normally")
	}
	walletDay.Set(picker.String(), itoa64(today)+"|"+list+itoa(a.ID)+",")
	b.Holds = addHold(b.Holds, today, lapseDay(end), b.Pay)
	b.Today++
	putBudget(a.ID, b)
	emitEvent("PromoReserved", "artist", itoa(a.ID), "track", itoa(trackID), "picker", picker.String(), "amount", itoa64(b.Pay))
	return b.Pay
}

// PromoClaim pays picker a reservation once their sponsored pick ending at end
// has aired; the radio realm checks the slot. A lapsed or cancelled
// reservation (the profile changed hands) pays nothing.
func PromoClaim(cur realm, trackID int, picker address, end, amount int64) {
	onlyRadio(cur.Previous().PkgPath())
	artistID, _, _, _, _ := brief(trackID)
	b, _ := getBudget(artistID)
	today, e := now()/daySecs, lapseDay(end)
	if today > e {
		panic("catalog: this sponsored pick was not collected within 7 days")
	}
	if _, atE := holds(b.Holds, today, e); atE < amount || amount <= 0 {
		panic("catalog: this sponsorship was cancelled")
	}
	b.Holds = addHold(b.Holds, today, e, -amount)
	b.Balance -= amount
	b.Paid += amount
	b.Picks++
	putBudget(artistID, b)
	sendHeld(cur, picker, amount)
	emitEvent("PromoPaid", "artist", itoa(artistID), "track", itoa(trackID), "to", picker.String(), "amount", itoa64(amount))
}

// PromoClaimable reports whether PromoClaim would pay a sponsored pick's
// refund: reserved for end and neither lapsed nor cancelled.
func PromoClaimable(trackID int, end, amount int64) bool {
	artistID, _, _, _, _ := brief(trackID)
	b, _ := getBudget(artistID)
	today, e := now()/daySecs, lapseDay(end)
	if today > e || amount <= 0 {
		return false
	}
	_, atE := holds(b.Holds, today, e)
	return atE >= amount
}

// PromoRelease returns a reservation to its budget: the slot was dropped or
// cut before it aired in full. A pick that never aired, reserved at reserved
// (unix; 0 when it partly aired), also gives back the daily counts it took,
// the artist's and picker's, if that was today. Radio realm only.
func PromoRelease(cur realm, trackID int, picker address, end, amount, reserved int64) {
	onlyRadio(cur.Previous().PkgPath())
	artistID, _, _, _, _ := brief(trackID)
	b, _ := getBudget(artistID)
	today, e := now()/daySecs, lapseDay(end)
	_, atE := holds(b.Holds, today, e)
	if atE < amount {
		amount = atE // lapsed or cancelled already
	}
	if amount > 0 {
		b.Holds = addHold(b.Holds, today, e, -amount)
		emitEvent("PromoReleased", "artist", itoa(artistID), "track", itoa(trackID), "amount", itoa64(amount))
	}
	unpick := reserved > 0 && reserved/daySecs == today
	if unpick {
		if b.Day == today && b.Today > 0 {
			b.Today--
		}
		wd, _ := walletDay.Get(picker.String())
		day, list, _ := strings.Cut(wd, "|")
		if atoi64(day) == today {
			walletDay.Set(picker.String(), day+"|"+strings.Replace(","+list, ","+itoa(artistID)+",", ",", 1)[1:])
		}
	}
	if amount > 0 || unpick {
		putBudget(artistID, b)
	}
}

// PromoOffer is what a sponsored pick of the artist's tracks refunds right
// now (0: none). Picker-specific limits are checked when picking.
func PromoOffer(artistID int) int64 { return offer(getArtist(artistID)) }

func offer(a *Artist) int64 {
	if a == nil {
		return 0
	}
	b, ok := getBudget(a.ID)
	today := now() / daySecs
	if !ok || a.Hidden || !a.Verified || a.Owner == "" || b.Funder != a.Owner || b.Pay == 0 ||
		b.free(today) < b.Pay || b.PerDay > 0 && b.Day == today && b.Today >= b.PerDay {
		return 0
	}
	return b.Pay
}

// PromoHeld is the ugnot this realm holds for budgets (the sum of balances).
func PromoHeld() int64 { return promoHeld }

// PromoJSON is an artist's sponsored-pick budget:
// {"artist","funder","balance","reserved","free","pay","perDay","today","funded","paid","picks","offer"}.
func PromoJSON(artistID int) string {
	b, _ := getBudget(artistID)
	today := now() / daySecs
	free := b.free(today)
	if b.Day != today {
		b.Today = 0
	}
	return `{"artist":` + itoa(artistID) + `,"funder":` + text.Str(b.Funder.String()) + `,"balance":` + itoa64(b.Balance) +
		`,"reserved":` + itoa64(b.Balance-free) + `,"free":` + itoa64(free) + `,"pay":` + itoa64(b.Pay) + `,"perDay":` + itoa(b.PerDay) +
		`,"today":` + itoa(b.Today) + `,"funded":` + itoa64(b.Funded) + `,"paid":` + itoa64(b.Paid) + `,"picks":` + itoa(b.Picks) +
		`,"offer":` + itoa64(PromoOffer(artistID)) + `}`
}

// PromoPage lists budgets (artist id -> record: funder, balance, pay,
// perDay, day, today, funded, paid, picks, holds) for a successor realm or an
// audit; the sum of balances equals PromoHeld.
func PromoPage(offset, limit int) (keys, vals []string) {
	if offset < 0 {
		offset = 0
	}
	if limit < 1 || limit > 100 {
		limit = 100
	}
	keys = budgets.Keys(offset, limit)
	for _, k := range keys {
		v, _ := budgets.Get(k)
		vals = append(vals, v)
	}
	return keys, vals
}

func onlyRadio(caller string) {
	if caller != radioRealm {
		panic("catalog: only the GnoRadio radio realm can call this")
	}
}

// sendHeld pays amt out of the budgets' coins.
func sendHeld(cur realm, to address, amt int64) {
	promoHeld -= amt
	bk := banker.NewBanker(banker.BankerTypeRealmSend, cur)
	bk.SendCoins(cur.Address(), to, chain.Coins{{Denom: denom, Amount: amt}})
}
