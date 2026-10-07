package catalog

import (
	"chain"
	"chain/banker"
	"strconv"
	"strings"
	"time"

	"gno.land/p/gnoradio/store/v0"
	"gno.land/p/gnoradio/text/v0"

	"gno.land/p/nt/avl/v0"
)

// GnoRadio's own funding, always on top of what artists receive and always
// visible on-chain: direct support and the optional share added to a tip.
// Every coin is forwarded to the treasury in the same transaction.

const activitySize = 64

// siblingRealms are GnoRadio's other realms (SetSibling adds their next
// versions): they hold no treasury, so coins sent there would be stuck.
var siblingRealms = []string{
	"gno.land/r/gnoradio/radio/v0",
	"gno.land/r/gnoradio/tickets/v0",
	"gno.land/r/gnoradio/home/v0",
}

// Activity is one entry of the public activity feed.
type Activity struct {
	Kind   string // publish | like | follow | tip | support | playlist | album | claim
	By     address
	Track  int // track, playlist or album id depending on Kind
	Artist int
	Amount int64
	At     int64
}

var (
	treasury       address
	totalSupport   int64
	nSupporters    int
	supporterTotal = store.NewMap(65536) // address -> lifetime total (an avl node would cost each supporter about 2KB of deposit)
	monthly        avl.Tree // "YYYY-MM" -> int64
	monthlyGoal    int64
	topSupport     []Rank

	activity     [activitySize]Activity // ring buffer, fixed size
	activityHead int                    // next write position
	activityN    int                    // filled entries, <= activitySize
)

// SupportGnoRadio sends the attached ugnot to the GnoRadio treasury.
func SupportGnoRadio(cur realm) {
	caller := userCaller(cur)
	notFrozen()
	amt := paid()
	if amt < minTip || amt > maxTip {
		panic("catalog: support is between 0.1 and 1000000 GNOT")
	}
	bk := banker.NewBanker(banker.BankerTypeRealmSend, cur)
	bk.SendCoins(cur.Address(), treasury, chain.Coins{{Denom: denom, Amount: amt}})
	recordSupport(caller, amt)
	emitEvent("Supported", "by", caller.String(), "amount", itoa64(amt))
}

// SetTreasury changes where GnoRadio's support goes. Admin only.
func SetTreasury(cur realm, to address) {
	onlyAdmin(cur)
	if !to.IsValid() {
		panic("catalog: invalid address")
	}
	if to == cur.Address() || isSibling(to) {
		panic("catalog: the treasury cannot be a GnoRadio realm")
	}
	emitEvent("TreasuryChanged", "from", treasury.String(), "to", to.String())
	treasury = to
}

// SetMonthlyGoal sets the monthly support goal shown in the app (ugnot). Admin only.
func SetMonthlyGoal(cur realm, ugnot int64) {
	onlyAdmin(cur)
	if ugnot < 0 || ugnot > maxTip {
		panic("catalog: goal out of range")
	}
	monthlyGoal = ugnot
	emitEvent("MonthlyGoal", "ugnot", itoa64(ugnot))
}

func Treasury() address { return treasury }

// SetSibling adds (or removes) a GnoRadio realm, e.g. a v1 being deployed:
// it can then never be named a treasury, a referrer or a collaborator. Admin only.
func SetSibling(cur realm, pkgPath string, on bool) {
	onlyAdmin(cur)
	mustRealmPath(pkgPath)
	if on {
		addSibling(pkgPath)
	} else {
		var kept []string
		for _, p := range siblingRealms {
			if p != pkgPath {
				kept = append(kept, p)
			}
		}
		siblingRealms = kept
	}
	emitEvent("Sibling", "path", pkgPath, "on", strconv.FormatBool(on))
}

// SiblingRealms lists the GnoRadio realms that receive no coins.
func SiblingRealms() []string { return append([]string(nil), siblingRealms...) }

func addSibling(pkgPath string) {
	for _, p := range siblingRealms {
		if p == pkgPath {
			return
		}
	}
	siblingRealms = append(siblingRealms, pkgPath)
}

// isSibling reports whether addr is another GnoRadio realm.
func isSibling(addr address) bool {
	for _, p := range siblingRealms {
		if addr == chain.PackageAddress(p) {
			return true
		}
	}
	return false
}

// SupportInfo returns GnoRadio's public funding state for this month.
func SupportInfo() (to address, total int64, supporters int, monthTotal, goal int64) {
	mt, _ := monthly.Get(month(now())).(int64)
	return treasury, totalSupport, nSupporters, mt, monthlyGoal
}

func recordSupport(by address, amt int64) {
	totalSupport += amt
	s, had := supporterTotal.Get(by.String())
	if !had {
		nSupporters++
	}
	prev := atoi64(s)
	supporterTotal.Set(by.String(), itoa64(prev+amt))
	topSupport = updateTop(topSupport, by.String(), prev+amt)
	m := month(now())
	cur, _ := monthly.Get(m).(int64)
	monthly.Set(m, cur+amt)
	recordActivity("support", by, 0, 0, amt)
}

func month(unix int64) string { return time.Unix(unix, 0).UTC().Format("2006-01") }

// recordActivity writes into the fixed-size ring: storage never grows.
func recordActivity(kind string, by address, track, artist int, amount int64) {
	activity[activityHead] = Activity{Kind: kind, By: by, Track: track, Artist: artist, Amount: amount, At: now()}
	activityHead = (activityHead + 1) % activitySize
	if activityN < activitySize {
		activityN++
	}
}

// Activities returns up to limit entries, newest first.
func Activities(limit int) []Activity {
	if limit < 1 || limit > activitySize {
		limit = activitySize
	}
	if limit > activityN {
		limit = activityN
	}
	out := make([]Activity, 0, limit)
	for i := 1; i <= limit; i++ {
		out = append(out, activity[(activityHead-i+activitySize)%activitySize])
	}
	return out
}

// ActivityJSON returns the activity feed, newest first (limit <= 64).
func ActivityJSON(limit int) string {
	var b strings.Builder
	b.WriteString("[")
	for i, a := range Activities(limit) {
		if i > 0 {
			b.WriteString(",")
		}
		b.WriteString(`{"kind":` + text.Str(a.Kind) + `,"by":` + text.Str(a.By.String()) + `,"track":` + itoa(a.Track) +
			`,"artist":` + itoa(a.Artist) + `,"amount":` + itoa64(a.Amount) + `,"at":` + itoa64(a.At) + `}`)
	}
	b.WriteString("]")
	return b.String()
}

// SupportJSON returns GnoRadio's public funding state.
func SupportJSON() string {
	m := month(now())
	mt, _ := monthly.Get(m).(int64)
	var b strings.Builder
	b.WriteString(`{"treasury":` + text.Str(treasury.String()) + `,"total":` + itoa64(totalSupport) + `,"supporters":` + itoa(nSupporters) +
		`,"month":` + text.Str(m) + `,"monthTotal":` + itoa64(mt) + `,"goal":` + itoa64(monthlyGoal) + `,"top":[`)
	for i, r := range topSupport {
		if i > 0 {
			b.WriteString(",")
		}
		b.WriteString(`{"address":` + text.Str(r.Key) + `,"amount":` + itoa64(r.Value) + `}`)
	}
	b.WriteString(`]}`)
	return b.String()
}
