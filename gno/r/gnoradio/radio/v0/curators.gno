package radio

import (
	"chain"
	"chain/banker"
	"chain/runtime/unsafe"
	"strings"

	"gno.land/p/gnoradio/store/v0"
	"gno.land/p/gnoradio/text/v0"

	"gno.land/r/gnoradio/catalog/v0"
)

// Curators are the listeners who pick tracks. While a pick is on air, a tip to
// its artist made with TipOnAir sends the artist's promo share to the picker
// (catalog/promo.gno). Every pick and every shared tip updates the picker's
// counters and the weekly top of the station and of all stations: one record
// and a 10-entry list, whatever the number of curators.

const (
	allStations = -1
	topCurators = 10
	week        = 7 * 24 * 3600
	tipGrace    = 120 // seconds after a pick ends during which a tip still credits its picker
)

// Curator is a picker's record, all time or for one week.
type Curator struct {
	Address address
	Picks   int
	Tips    int   // tips received while their picks were on air
	Earned  int64 // ugnot from those tips
	Promo   int64 // ugnot refunded by artists for sponsored picks (sponsor.gno)
}

type rank struct {
	Key   string // address
	Score int64  // picks + tips this week
}

type weekTop struct {
	Week int64
	List []rank
}

// A curator is one record (one map entry costs a listener about 1.5KB of
// deposit): all time, picks, tips, earned, promo, first pick, period, picks
// this period, picks the period before; this week across stations, week,
// picks, tips, earned; then one entry per station picked on lately (see
// stationOf).
const (
	cWeek    = 8
	cFields  = 12
	cStation = 12 // field index of the per-station entries
)

var (
	curators = store.NewMap(65536)      // address -> curator record
	tops     [ChoiceStation + 2]weekTop // index station+1, 0 = all stations

	// radioTip is a test seam: radio tests cannot verify an artist (the
	// catalog admin is unreachable there); catalog/promo_test.gno covers it.
	radioTip = catalog.RadioTip
)

// TipOnAir tips the artist of trackID: the attached ugnot go through the
// catalog, which pays the artist and collaborators exactly as
// catalog.TipWithSupport does. When trackID is a listener's pick on air on
// stationID (or ended less than two minutes ago), the artist's promo share
// goes to that listener; the radio reads the picker from its own schedule.
// ref is who shared the link the tipper came from ("" for none): picker and
// ref split the promo share, never more.
func TipOnAir(cur realm, stationID, trackID, supportPct int, ref address) {
	tipper := userCaller(cur)
	notFrozen()
	sent := unsafe.OriginSend()
	if len(sent) != 1 || sent[0].Denom != "ugnot" || sent[0].Amount <= 0 {
		panic("radio: attach an amount in ugnot")
	}
	st := mustStation(stationID)
	ts := now()
	var picker address
	for _, s := range st.schedule {
		// The radio admin's curator picks earn nothing: GnoRadio takes no share.
		// Nor do sponsored picks: the artist already refunds them (sponsor.gno).
		if s.Track == trackID && s.By != "" && s.By != admin && s.Pay == 0 && s.Start <= ts && ts < s.Start+s.Dur+tipGrace {
			picker = s.By
		}
	}
	bk := banker.NewBanker(banker.BankerTypeRealmSend, cur)
	bk.SendCoins(cur.Address(), chain.PackageAddress("gno.land/r/gnoradio/catalog/v0"), sent)
	toPicker, _ := radioTip(cross(cur), trackID, supportPct, tipper, picker, ref, sent[0].Amount)
	if toPicker > 0 {
		credit(picker, st.id, 0, 1, toPicker)
		chain.Emit("CuratorTipped", "station", itoa(st.id), "track", itoa(trackID), "picker", picker.String(), "amount", itoa64(toPicker))
	}
}

// credit adds picks or a shared tip to a curator, all time and this week.
// The station's entry also keeps the time of the last pick there, which the
// queue cooldown reads (lastPickAt): no extra write per pick.
func credit(by address, stationID, picks, tips int, earned int64) {
	k := by.String()
	ts := now()
	c, sts := curRec(k)
	c[0], c[1], c[2] = c[0]+int64(picks), c[1]+int64(tips), c[2]+earned
	if picks > 0 {
		// The reputation sponsored picks need (sponsor.gno): the first pick,
		// and picks counted per period, this one and the one before.
		if c[4] == 0 {
			c[4] = ts
		}
		switch p := ts / repPeriod; c[5] {
		case p:
			c[6]++
		case p - 1:
			c[5], c[6], c[7] = p, 1, c[6]
		default:
			c[5], c[6], c[7] = p, 1, 0
		}
	}
	wk := weekOf(ts)
	if c[cWeek] != wk {
		c[cWeek], c[cWeek+1], c[cWeek+2], c[cWeek+3] = wk, 0, 0, 0
	}
	c[cWeek+1], c[cWeek+2], c[cWeek+3] = c[cWeek+1]+int64(picks), c[cWeek+2]+int64(tips), c[cWeek+3]+earned
	w := stationOf(sts, stationID)
	if w[0] != wk {
		w = []int64{wk, 0, 0, 0, w[4]}
	}
	w[1], w[2], w[3] = w[1]+int64(picks), w[2]+int64(tips), w[3]+earned
	if picks > 0 {
		w[4] = ts
	}
	putCur(k, c, withStation(sts, stationID, w, ts))
	tops[0].set(wk, k, c[cWeek+1]+c[cWeek+2])
	tops[stationID+1].set(wk, k, w[1]+w[2])
}

// curRec reads a curator record (zeros when absent).
func curRec(k string) ([]int64, string) {
	c := make([]int64, cFields)
	rec, ok := curators.Get(k)
	if !ok {
		return c, ""
	}
	f := store.Fields(rec)
	for i := 0; i < cFields && i < len(f); i++ {
		c[i] = atoi64(f[i])
	}
	if len(f) > cStation {
		return c, f[cStation]
	}
	return c, ""
}

func putCur(k string, c []int64, sts string) {
	f := make([]string, cFields+1)
	for i, v := range c {
		f[i] = itoa64(v)
	}
	f[cStation] = sts
	curators.Set(k, store.Rec(f...))
}

// putCurator replaces the first len(c) numbers of a curator record.
func putCurator(k string, c []int64) {
	old, sts := curRec(k)
	copy(old, c)
	putCur(k, old, sts)
}

// stationOf returns a curator's entry for a station: week, picks, tips,
// earned, last pick time (zeros when none). Entries are "id:week:picks:tips:
// earned:last" joined by ";".
func stationOf(sts string, stationID int) []int64 {
	w := make([]int64, 5)
	p := itoa(stationID) + ":"
	for _, e := range strings.Split(sts, ";") {
		if strings.HasPrefix(e, p) {
			for i, f := range strings.Split(e[len(p):], ":") {
				if i < 5 {
					w[i] = atoi64(f)
				}
			}
		}
	}
	return w
}

// withStation sets a station's entry and drops the entries that no longer
// count: an older week whose last pick is past the cooldown.
func withStation(sts string, stationID int, w []int64, ts int64) string {
	p := itoa(stationID) + ":"
	out := p + itoa64(w[0]) + ":" + itoa64(w[1]) + ":" + itoa64(w[2]) + ":" + itoa64(w[3]) + ":" + itoa64(w[4])
	wk := weekOf(ts)
	for _, e := range strings.Split(sts, ";") {
		if e == "" || strings.HasPrefix(e, p) {
			continue
		}
		f := strings.Split(e, ":")
		if len(f) == 6 && (atoi64(f[1]) == wk || ts-atoi64(f[5]) < queueCooldown) {
			out += ";" + e
		}
	}
	return out
}

// markPick keeps the time of a pick that earns no point (a sponsored one) for
// the queue cooldown.
func markPick(by address, stationID int) {
	k := by.String()
	ts := now()
	c, sts := curRec(k)
	w := stationOf(sts, stationID)
	if wk := weekOf(ts); w[0] != wk {
		w = []int64{wk, 0, 0, 0, 0}
	}
	w[4] = ts
	putCur(k, c, withStation(sts, stationID, w, ts))
}

// lastPickAt is when addr last picked on a station (0: never).
func lastPickAt(addr address, stationID int) int64 {
	rec, _ := curators.Get(addr.String())
	if rec == "" {
		return 0
	}
	return stationOf(store.Field(rec, cStation), stationID)[4]
}

// weekOf numbers weeks from Monday 00:00 UTC.
func weekOf(ts int64) int64 { return (ts + 3*24*3600) / week }

// nums reads the first n integers of a record (zeros when absent).
func nums(m *store.Map, k string, n int) []int64 {
	out := make([]int64, n)
	if rec, ok := m.Get(k); ok {
		for i, f := range store.Fields(rec) {
			if i < n {
				out[i] = atoi64(f)
			}
		}
	}
	return out
}

// set raises k's score in the ranking, emptied when a new week starts. Scores
// only grow, so a curator outside the top that does not pass the last one
// leaves the list untouched (and unsaved).
func (w *weekTop) set(wk int64, k string, v int64) {
	if w.Week != wk {
		w.Week, w.List = wk, nil
	}
	out := make([]rank, 0, topCurators+1)
	for _, r := range w.List {
		if r.Key != k {
			out = append(out, r)
		}
	}
	i := len(out)
	for i > 0 && out[i-1].Score < v {
		i--
	}
	if i >= topCurators {
		return
	}
	out = append(out, rank{})
	copy(out[i+1:], out[i:])
	out[i] = rank{k, v}
	if len(out) > topCurators {
		out = out[:topCurators]
	}
	// A stored slice keeps its whole backing array, each spare element an
	// empty struct (about 400 bytes of deposit): store one of its length.
	w.List = make([]rank, len(out))
	copy(w.List, out)
}

// CuratorOf returns a listener's curator record, all time.
func CuratorOf(addr address) Curator {
	c := nums(curators, addr.String(), 4)
	return Curator{Address: addr, Picks: int(c[0]), Tips: int(c[1]), Earned: c[2], Promo: c[3]}
}

// TopCurators returns this week's top curators of a station (allStations:
// every station), best first, with their counts for the week. Picks and tips
// received on air score one point each.
func TopCurators(stationID int) []Curator {
	if stationID != allStations {
		mustStation(stationID)
	}
	wk := weekOf(now())
	w := tops[stationID+1]
	if w.Week != wk {
		return nil
	}
	out := make([]Curator, 0, len(w.List))
	for _, r := range w.List {
		c, sts := curRec(r.Key)
		n := c[cWeek:]
		if stationID != allStations {
			n = stationOf(sts, stationID)
		}
		out = append(out, Curator{Address: address(r.Key), Picks: int(n[1]), Tips: int(n[2]), Earned: n[3]})
	}
	return out
}

// CuratorJSON returns a listener's curator record: all time, this week, and
// their place in this week's top across stations (0 when outside the top 10).
func CuratorJSON(addr address) string {
	c := CuratorOf(addr)
	r, _ := curRec(addr.String())
	w := r[cWeek:]
	if w[0] != weekOf(now()) {
		w = []int64{0, 0, 0, 0}
	}
	place := 0
	for i, r := range TopCurators(allStations) {
		if r.Address == addr {
			place = i + 1
		}
	}
	return `{"address":` + text.Str(addr.String()) + `,"picks":` + itoa(c.Picks) + `,"tips":` + itoa(c.Tips) + `,"earned":` + itoa64(c.Earned) + `,"promo":` + itoa64(c.Promo) +
		`,"week":{"picks":` + itoa64(w[1]) + `,"tips":` + itoa64(w[2]) + `,"earned":` + itoa64(w[3]) + `,"rank":` + itoa(place) + `}}`
}

// TopCuratorsJSON returns TopCurators as JSON with the week's start (unix).
func TopCuratorsJSON(stationID int) string {
	var b strings.Builder
	b.WriteString(`{"station":` + itoa(stationID) + `,"since":` + itoa64(weekOf(now())*week-3*24*3600) + `,"top":[`)
	for i, c := range TopCurators(stationID) {
		if i > 0 {
			b.WriteString(",")
		}
		b.WriteString(`{"address":` + text.Str(c.Address.String()) + `,"picks":` + itoa(c.Picks) + `,"tips":` + itoa(c.Tips) + `,"earned":` + itoa64(c.Earned) + `}`)
	}
	b.WriteString(`]}`)
	return b.String()
}
