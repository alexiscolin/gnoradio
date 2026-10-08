package radio

import (
	"chain"
	"chain/banker"
	"strings"
	"testing"

	"gno.land/p/gnoradio/store/v0"
	"gno.land/p/gnoradio/text/v0"
	"gno.land/p/nt/testutils/v0"
	"gno.land/p/nt/uassert/v0"
	"gno.land/p/nt/urequire/v0"
	"gno.land/r/gnoradio/catalog/v1"
	"gno.land/r/gnoradio/data"
)

const (
	ugnot   = 1_000_000
	pickPay = 200_000 // the catalog's default refund per sponsored pick
)

var (
	radioAddr   = chain.PackageAddress("gno.land/r/gnoradio/radio/v1")
	catalogAddr = chain.PackageAddress("gno.land/r/gnoradio/catalog/v1")
	dataAddr    = chain.PackageAddress(dataPath)
)

func ugnots(n int64) chain.Coins { return chain.Coins{{Denom: "ugnot", Amount: n}} }

func balance(addr address) int64 {
	return banker.NewReadonlyBanker().GetCoins(addr).AmountOf("ugnot")
}

// syncVault gives the data realm back the coins its vault accounts for:
// coins reset between tests, the data realm's state does not.
func syncVault() {
	if d := data.VaultTotal() - balance(dataAddr); d > 0 {
		testing.IssueCoins(dataAddr, ugnots(d))
	}
}

// sponsor is a verified artist whose budget refunds sponsored picks of
// its tracks (the catalog's default: pickPay ugnot a pick).
type sponsor struct {
	owner address
	aid   int
	ids   []int
}

// newSponsor registers, verifies and funds an artist with n tracks of dur
// on genre 5, and syncs them.
func newSponsor(cur realm, name string, n int, dur string) sponsor {
	w := testutils.TestAddress(name)
	testing.SetRealm(testing.NewUserRealm(w))
	aid := catalog.RegisterArtist(cross(cur), name, "")
	var ids []int
	for i := 0; i < n; i++ {
		ids = append(ids, publish(cur, name+" "+text.Itoa(i), 5, dur))
	}
	testing.SetRealm(testing.NewUserRealm(boss))
	catalog.Verify(cross(cur), aid, true)
	syncVault()
	testing.IssueCoins(catalogAddr, ugnots(ugnot))
	testing.SetOriginSend(ugnots(ugnot))
	testing.SetRealm(testing.NewUserRealm(w))
	catalog.FundPromo(cross(cur))
	testing.SetOriginSend(nil)
	testing.SetRealm(testing.NewUserRealm(dave))
	Sync(cross(cur), 50)
	return sponsor{w, aid, ids}
}

// sponsorSetup is a fresh radio and a sponsor of n one-minute tracks on station 5.
func sponsorSetup(cur realm, name string, n int) sponsor {
	reset(cur)
	return newSponsor(cur, name, n, "1:00")
}

// held is the artist's reservation for a pick ending at end (catalog lapseDay).
func (s sponsor) held(end int64) int64 {
	return data.VaultHeld("catalog/"+store.Pad(s.aid), (end+7*24*3600)/(24*3600))
}

// today is the artist's sponsored picks today.
func (s sponsor) today() int { return jsonInt(catalog.PromoJSON(s.aid), "today") }

func jsonInt(js, key string) int {
	i := strings.Index(js, `"`+key+`":`)
	if i < 0 {
		return -1
	}
	v := js[i+len(key)+3:]
	if j := strings.IndexAny(v, ",}"); j >= 0 {
		v = v[:j]
	}
	return text.Atoi(v)
}

// trust gives addr the reputation sponsored picks need.
func trust(cur realm, addr address) {
	edit(cur, func(t *tx) {
		ts := now()
		c, sts := curRec(t, addr.String())
		c[0], c[4], c[5], c[6], c[7] = 3, ts-repAge, ts/repPeriod, repPicks, 0
		putCur(t, addr.String(), c, sts)
	})
}

// claim collects a sponsored pick as who and returns what it paid.
func claim(cur realm, who address, stationID int, start int64) int64 {
	syncVault()
	b := balance(who)
	testing.SetRealm(testing.NewUserRealm(who))
	ClaimPickPayout(cross(cur), stationID, start)
	return balance(who) - b
}

// A wallet earns sponsored picks: a first pick 7 days old and 3 normal picks
// in the last two 15-day periods.
func TestSponsorReputation(cur realm, t *testing.T) {
	sp := sponsorSetup(cur, "Rep Artist", 3)
	ids := sp.ids
	uassert.Equal(t, "sponsored picks open 7 days after your first pick", sponsorBlock(rd(), carol))
	testing.SetRealm(testing.NewUserRealm(carol))
	uassert.AbortsContains(t, cur, "7 days after your first pick", func() { QueueSponsored(cross(cur), 5, ids[0]) })
	Queue(cross(cur), 5, ids[0])
	testing.SkipHeights(repAge / 5)
	uassert.Equal(t, "sponsored picks need 3 normal picks in the last two 15-day periods", sponsorBlock(rd(), carol))
	for _, st := range []int{NewStation, ChoiceStation} {
		testing.SetRealm(testing.NewUserRealm(carol))
		Queue(cross(cur), st, ids[1])
	}
	uassert.Equal(t, "", sponsorBlock(rd(), carol))
	// Two periods later the old picks no longer count.
	testing.SkipHeights(2 * repPeriod / 5)
	uassert.Equal(t, "sponsored picks need 3 normal picks in the last two 15-day periods", sponsorBlock(rd(), carol))
	js := SponsoredJSON(carol)
	urequire.True(t, strings.Contains(js, `"block":"sponsored picks need 3`), js)
}

// The pick is reserved when queued, paid once it aired in full, once.
func TestSponsoredPickLifecycle(cur realm, t *testing.T) {
	sp := sponsorSetup(cur, "Life Artist", 2)
	ids := sp.ids
	trust(cur, carol)
	testing.SetRealm(testing.NewUserRealm(carol))
	QueueSponsored(cross(cur), 5, ids[0])
	s := slotBy(5, carol)
	urequire.Equal(t, int64(pickPay), s.Pay)
	end := s.Start + s.Dur
	uassert.Equal(t, int64(pickPay), sp.held(end))
	js := ScheduleJSON(5, 3600)
	urequire.True(t, strings.Contains(js, `"by":"`+carol.String()+`","note":"","sponsored":200000`), js)
	urequire.True(t, strings.Contains(SponsoredJSON(carol), `"open":[{"station":5,"start":`+text.Itoa64(s.Start)), SponsoredJSON(carol))
	// Paid by the artist: no curator point, no Listeners' choice, but the cooldown holds.
	uassert.Equal(t, 3, CuratorOf(carol).Picks)
	_, inChoice := sta(ChoiceStation).ringSlot(ids[0])
	uassert.False(t, inChoice)
	uassert.Equal(t, "sponsored", Activities(1)[0].Kind)
	uassert.True(t, lastPickAt(rd(), carol, 5) > 0)

	// Not before it has aired in full, not by someone else.
	uassert.AbortsContains(t, cur, "not finished airing", func() { ClaimPickPayout(cross(cur), 5, s.Start) })
	testing.SkipHeights((end - now()) / 5)
	if now() < end {
		testing.SkipHeights(1)
	}
	testing.SetRealm(testing.NewUserRealm(dave))
	uassert.AbortsContains(t, cur, "no sponsored pick of yours", func() { ClaimPickPayout(cross(cur), 5, s.Start) })
	testing.SetRealm(testing.NewUserRealm(carol))
	uassert.AbortsContains(t, cur, "no sponsored pick of yours", func() { ClaimPickPayout(cross(cur), 5, s.Start+1) })
	// One open sponsored pick per station: collect it before the next.
	testing.SkipHeights(queueCooldown / 5)
	uassert.AbortsContains(t, cur, "collect your last sponsored pick", func() { QueueSponsored(cross(cur), 5, ids[1]) })
	uassert.Equal(t, int64(pickPay), claim(cur, carol, 5, s.Start))
	uassert.Equal(t, int64(0), sp.held(end))
	uassert.Equal(t, int64(pickPay), CuratorOf(carol).Promo)
	urequire.True(t, strings.Contains(CuratorJSON(carol), `"promo":200000`), CuratorJSON(carol))
	// Once per slot.
	uassert.AbortsContains(t, cur, "no sponsored pick of yours", func() { ClaimPickPayout(cross(cur), 5, s.Start) })
}

// A sponsored slot removed before its end gives the reservation back.
func TestSponsoredPickDropped(cur realm, t *testing.T) {
	sp := sponsorSetup(cur, "Cut Sponsor", 1)
	other := newSponsor(cur, "Cut Other", 1, "1:00")
	trust(cur, carol)
	trust(cur, bob)
	testing.SetRealm(testing.NewUserRealm(carol))
	QueueSponsored(cross(cur), 5, sp.ids[0])
	testing.SetRealm(testing.NewUserRealm(bob))
	QueueSponsored(cross(cur), 5, other.ids[0])
	c, b := slotBy(5, carol), slotBy(5, bob)
	urequire.True(t, c.Pay > 0 && b.Pay > 0)
	uassert.Equal(t, 1, other.today())

	testing.SetRealm(testing.NewUserRealm(erin)) // radio admin
	Unqueue(cross(cur), 5, other.ids[0])         // not started: removed
	uassert.Equal(t, int64(0), other.held(b.Start+b.Dur))
	uassert.Equal(t, 0, other.today()) // it never aired: the day's count comes back
	testing.SetRealm(testing.NewUserRealm(bob))
	uassert.AbortsContains(t, cur, "no sponsored pick of yours", func() { ClaimPickPayout(cross(cur), 5, b.Start) })

	// carol's pick: cut while on air, it still pays once its end passes (review R2).
	if now() < c.Start {
		testing.SkipHeights((c.Start-now())/5 + 1)
	}
	urequire.True(t, now() < c.Start+c.Dur)
	uassert.Equal(t, int64(pickPay), OnAirPay(5))
	testing.SetRealm(testing.NewUserRealm(erin))
	Unqueue(cross(cur), 5, sp.ids[0])
	uassert.Equal(t, int64(pickPay), sp.held(c.Start+c.Dur)) // it partly aired: the refund stays the picker's
	uassert.Equal(t, 1, sp.today())
	testing.SetRealm(testing.NewUserRealm(carol))
	uassert.Equal(t, "airing", PickPayoutStatus(carol, 5, c.Start))
	testing.SkipHeights((c.Start+c.Dur-now())/5 + 1)
	uassert.Equal(t, int64(pickPay), claim(cur, carol, 5, c.Start))
}

// One sponsored pick per artist per station and hour; sponsored airtime at
// most a quarter of the 2-hour listener window.
func TestSponsoredQuotas(cur realm, t *testing.T) {
	sp := sponsorSetup(cur, "Quota Artist", 2)
	for _, a := range []address{carol, bob} {
		trust(cur, a)
	}
	testing.SetRealm(testing.NewUserRealm(carol))
	QueueSponsored(cross(cur), 5, sp.ids[0])
	testing.SetRealm(testing.NewUserRealm(bob))
	uassert.AbortsContains(t, cur, "sponsored pick this hour here", func() { QueueSponsored(cross(cur), 5, sp.ids[1]) })
	Queue(cross(cur), 5, sp.ids[1]) // a normal pick of the same artist is fine

	// Long tracks of other artists fill the sponsored quarter (1800 s).
	var long []int
	for i := 0; i < 2; i++ {
		long = append(long, newSponsor(cur, "Long Sponsor "+text.Itoa(i), 1, "15:00").ids[0])
	}
	f1, f2 := testutils.TestAddress("fan1"), testutils.TestAddress("fan2")
	trust(cur, f1)
	trust(cur, f2)
	testing.SetRealm(testing.NewUserRealm(f1))
	QueueSponsored(cross(cur), 5, long[0]) // 60 + 900 s
	testing.SetRealm(testing.NewUserRealm(f2))
	uassert.AbortsContains(t, cur, "sponsored picks are full", func() { QueueSponsored(cross(cur), 5, long[1]) })
	Queue(cross(cur), 5, long[1])
}

// A sponsored slot moved since its reservation releases the end the catalog
// filed it under, not its new one.
func TestSponsoredReleaseKeepsHeldEnd(cur realm, t *testing.T) {
	sp := sponsorSetup(cur, "Held Sponsor", 1)
	picker := testutils.TestAddress("heldfan") // a wallet with no sponsored pick today
	trust(cur, picker)
	testing.SetRealm(testing.NewUserRealm(picker))
	QueueSponsored(cross(cur), 5, sp.ids[0])
	s := slotBy(5, picker)
	held := s.Start + s.Dur
	urequire.Equal(t, int64(pickPay), sp.held(held))
	edit(cur, func(t *tx) { // pushed back, as by a booked pick before it
		st := t.station(5)
		for k, x := range st.slots() {
			if x.By == picker {
				st.move(k, x.Start+600)
			}
		}
	})
	uassert.Equal(t, s.Start+600, slotBy(5, picker).Start)
	testing.SetRealm(testing.NewUserRealm(erin))
	Unqueue(cross(cur), 5, sp.ids[0])
	uassert.Equal(t, int64(0), sp.held(held))
	uassert.Equal(t, 0, sp.today())
}

// Nothing left to pay (lapsed, cancelled or removed): the record goes, so the
// next sponsored pick on the station is open at once.
func TestClaimPickPayoutVoid(cur realm, t *testing.T) {
	sp := sponsorSetup(cur, "Void Sponsor", 2)
	picker := testutils.TestAddress("voidfan") // a wallet with no sponsored pick today
	trust(cur, picker)
	testing.SetRealm(testing.NewUserRealm(picker))
	QueueSponsored(cross(cur), 5, sp.ids[0])
	s := slotBy(5, picker)
	testing.SkipHeights((s.Start+s.Dur-now()+8*24*3600)/5 + 1) // past the 7 days
	uassert.Equal(t, "lapsed", PickPayoutStatus(picker, 5, s.Start))
	uassert.Equal(t, int64(0), claim(cur, picker, 5, s.Start)) // nothing paid
	_, open := data.Get(cSponsor, sponsorKey(5, picker))
	uassert.False(t, open)
	uassert.Equal(t, int64(0), CuratorOf(picker).Promo)
	trust(cur, picker)
	testing.SetRealm(testing.NewUserRealm(picker))
	QueueSponsored(cross(cur), 5, sp.ids[1])
}

// The payout status as the app reads it. A paused radio collects nothing:
// a pause longer than 7 days lets the refund lapse back to the artist's
// budget, the money is not lost (docs/ARCHITECTURE-v1.md, section 4).
func TestPickPayoutStatusAndPause(cur realm, t *testing.T) {
	sp := sponsorSetup(cur, "Status Sponsor", 1)
	picker := testutils.TestAddress("statusfan") // a wallet with no sponsored pick today
	trust(cur, picker)
	testing.SetRealm(testing.NewUserRealm(picker))
	QueueSponsored(cross(cur), 5, sp.ids[0])
	s := slotBy(5, picker)
	uassert.Equal(t, "airing", PickPayoutStatus(picker, 5, s.Start))
	uassert.Equal(t, "none", PickPayoutStatus(picker, 5, s.Start+1))
	uassert.Equal(t, "none", PickPayoutStatus(bob, 5, s.Start))
	testing.SkipHeights((s.Start+s.Dur-now())/5 + 1)
	uassert.Equal(t, "ok", PickPayoutStatus(picker, 5, s.Start))
	urequire.True(t, strings.Contains(SponsoredJSON(picker), `"amount":200000,"status":"ok"}`), SponsoredJSON(picker))

	owner := chain.PackageAddress("gno.land/r/gnoradio/data/dev")
	testing.SetRealm(testing.NewUserRealm(owner))
	data.Pause(cross(cur), "radio", true)
	testing.SetRealm(testing.NewUserRealm(picker))
	uassert.AbortsContains(t, cur, "paused", func() { ClaimPickPayout(cross(cur), 5, s.Start) })
	testing.SetRealm(testing.NewUserRealm(owner))
	data.Pause(cross(cur), "radio", false)
	uassert.Equal(t, int64(pickPay), claim(cur, picker, 5, s.Start))
	uassert.Equal(t, "none", PickPayoutStatus(picker, 5, s.Start))
}

// Review R2/R27: once a sponsored pick has aired, nothing its artist does
// voids the refund: hiding the track (even for good) or cutting the slot
// while it airs (hide + Refresh) leaves the record, and the picker collects.
func TestSponsoredRefundSurvivesArtistHide(cur realm, t *testing.T) {
	sp := sponsorSetup(cur, "Hiding Sponsor", 2)
	picker := testutils.TestAddress("hiddenfan")
	trust(cur, picker)
	testing.SetRealm(testing.NewUserRealm(picker))
	QueueSponsored(cross(cur), 5, sp.ids[0])
	s := slotBy(5, picker)
	testing.SkipHeights((s.Start+s.Dur-now())/5 + 1)
	testing.SetRealm(testing.NewUserRealm(sp.owner))
	catalog.HideOwn(cross(cur), "track", sp.ids[0], true)
	uassert.Equal(t, "ok", PickPayoutStatus(picker, 5, s.Start))
	uassert.Equal(t, int64(pickPay), claim(cur, picker, 5, s.Start))

	// Cut while on air: the artist hides the other track and anyone refreshes it.
	testing.SkipHeights(3600/5 + 1) // one pick per station and hour
	testing.SetRealm(testing.NewUserRealm(picker))
	QueueSponsored(cross(cur), 5, sp.ids[1])
	s = slotBy(5, picker)
	testing.SkipHeights((s.Start-now())/5 + 2)
	testing.SetRealm(testing.NewUserRealm(sp.owner))
	catalog.HideOwn(cross(cur), "track", sp.ids[1], true)
	Refresh(cross(cur), sp.ids[1])
	_, open := data.Get(cSponsor, sponsorKey(5, picker))
	uassert.True(t, open)
	testing.SkipHeights((s.Start+s.Dur-now())/5 + 1)
	uassert.Equal(t, int64(pickPay), claim(cur, picker, 5, s.Start))
}

// fundAs funds artist aid's budget from w, as FundPromo does from a wallet.
func fundAs(cur realm, w address) {
	syncVault()
	testing.IssueCoins(catalogAddr, ugnots(ugnot))
	testing.SetOriginSend(ugnots(ugnot))
	testing.SetRealm(testing.NewUserRealm(w))
	catalog.FundPromo(cross(cur))
	testing.SetOriginSend(nil)
}

// Audit Y1: the vault pools an artist's holds per day. A reservation made
// before the profile changed hands was refunded with the old budget: it is
// cancelled, never paid from a later listener's hold, and its release
// does not free that hold either.
func TestSponsoredAfterOwnerChange(cur realm, t *testing.T) {
	reset(cur)
	o1, o2 := testutils.TestAddress("firstowner"), testutils.TestAddress("secondowner")
	p1, p2, p3 := testutils.TestAddress("ownerfan1"), testutils.TestAddress("ownerfan2"), testutils.TestAddress("ownerfan3")
	testing.SetRealm(testing.NewUserRealm(boss))
	aid := catalog.CreateArtist(cross(cur), catalog.OriginCurated, "Handover Band", "", "")
	var ids []int
	for i := 0; i < 3; i++ {
		ids = append(ids, ImportTrack(cross(cur), aid, "Handover "+text.Itoa(i), 5, "1:00", "CC0-1.0", "", "ipfs://"+cid, "", "", "", "https://archive.org/details/handover", "Handover by the band"))
	}
	catalog.AssignArtist(cross(cur), aid, o1)
	fundAs(cur, o1)
	testing.SetRealm(testing.NewUserRealm(dave))
	Sync(cross(cur), 50)
	for _, p := range []address{p1, p2, p3} {
		trust(cur, p)
	}
	testing.SetRealm(testing.NewUserRealm(p1))
	QueueSponsored(cross(cur), 5, ids[0])
	testing.SetRealm(testing.NewUserRealm(p3))
	QueueSponsored(cross(cur), NewStation, ids[2])
	s1, s3 := slotBy(5, p1), slotBy(NewStation, p3)

	// The profile changes hands; the new owner's funding refunds the old one.
	testing.SetRealm(testing.NewUserRealm(boss))
	catalog.ResetOwner(cross(cur), aid)
	catalog.AssignArtist(cross(cur), aid, o2)
	fundAs(cur, o2)
	testing.SetRealm(testing.NewUserRealm(p2))
	QueueSponsored(cross(cur), ChoiceStation, ids[1]) // the same lapse day as p1's
	s2 := slotBy(ChoiceStation, p2)
	acct := "catalog/" + store.Pad(aid)
	day := (s2.Start + s2.Dur + 7*24*3600) / (24 * 3600)
	urequire.Equal(t, int64(pickPay), data.VaultHeld(acct, day))

	// p3's slot is dropped before it airs: nothing of p2's hold goes.
	testing.SetRealm(testing.NewUserRealm(erin))
	Unqueue(cross(cur), NewStation, ids[2])
	uassert.Equal(t, int64(pickPay), data.VaultHeld(acct, day))
	_ = s3

	end := s1.Start + s1.Dur
	if e := s2.Start + s2.Dur; e > end {
		end = e
	}
	testing.SkipHeights((end-now())/5 + 1)
	uassert.Equal(t, "lapsed", PickPayoutStatus(p1, 5, s1.Start))
	uassert.Equal(t, int64(0), claim(cur, p1, 5, s1.Start))
	uassert.Equal(t, int64(pickPay), data.VaultHeld(acct, day))
	uassert.Equal(t, "ok", PickPayoutStatus(p2, ChoiceStation, s2.Start))
	uassert.Equal(t, int64(pickPay), claim(cur, p2, ChoiceStation, s2.Start))
}

// Audit: the budget goes back to the funder of p1's reservation within the
// 7 days. The funder is the same and p2's reservation puts a hold in the
// vault for the same day, but p1's funding generation is gone: p1's pick
// pays nothing and p2's is paid.
func TestSponsoredBackToSameFunder(cur realm, t *testing.T) {
	reset(cur)
	o1, o2 := testutils.TestAddress("tripowner1"), testutils.TestAddress("tripowner2")
	p1, p2 := testutils.TestAddress("tripfan1"), testutils.TestAddress("tripfan2")
	testing.SetRealm(testing.NewUserRealm(boss))
	aid := catalog.CreateArtist(cross(cur), catalog.OriginCurated, "Round Trip Band", "", "")
	var ids []int
	for i := 0; i < 2; i++ {
		ids = append(ids, ImportTrack(cross(cur), aid, "Trip "+text.Itoa(i), 5, "1:00", "CC0-1.0", "", "ipfs://"+cid, "", "", "", "https://archive.org/details/trip", "Trip by the band"))
	}
	catalog.AssignArtist(cross(cur), aid, o1)
	fundAs(cur, o1)
	testing.SetRealm(testing.NewUserRealm(dave))
	Sync(cross(cur), 50)
	trust(cur, p1)
	trust(cur, p2)
	testing.SetRealm(testing.NewUserRealm(p1))
	QueueSponsored(cross(cur), 5, ids[0])
	s1 := slotBy(5, p1)

	for _, o := range []address{o2, o1} { // there and back
		testing.SetRealm(testing.NewUserRealm(boss))
		catalog.ResetOwner(cross(cur), aid)
		catalog.AssignArtist(cross(cur), aid, o)
		fundAs(cur, o)
	}
	testing.SetRealm(testing.NewUserRealm(p2))
	QueueSponsored(cross(cur), ChoiceStation, ids[1])
	s2 := slotBy(ChoiceStation, p2)
	acct := "catalog/" + store.Pad(aid)
	day := (s2.Start + s2.Dur + 7*24*3600) / (24 * 3600)
	urequire.Equal(t, day, (s1.Start+s1.Dur+7*24*3600)/(24*3600))
	urequire.Equal(t, int64(pickPay), data.VaultHeld(acct, day))

	end := s1.Start + s1.Dur
	if e := s2.Start + s2.Dur; e > end {
		end = e
	}
	testing.SkipHeights((end-now())/5 + 1)
	uassert.Equal(t, "lapsed", PickPayoutStatus(p1, 5, s1.Start))
	uassert.Equal(t, int64(0), claim(cur, p1, 5, s1.Start))
	uassert.Equal(t, int64(pickPay), data.VaultHeld(acct, day))
	uassert.Equal(t, int64(pickPay), claim(cur, p2, ChoiceStation, s2.Start))
}

// Audit: a paused catalog does not stop the radio admin from dropping a
// sponsored slot; the reservation lapses back to the budget by itself.
func TestDropSponsoredWhileCatalogPaused(cur realm, t *testing.T) {
	sp := sponsorSetup(cur, "Paused Sponsor", 1)
	picker := testutils.TestAddress("pausedfan")
	trust(cur, picker)
	testing.SetRealm(testing.NewUserRealm(picker))
	QueueSponsored(cross(cur), 5, sp.ids[0])
	s := slotBy(5, picker)
	owner := chain.PackageAddress("gno.land/r/gnoradio/data/dev")
	testing.SetRealm(testing.NewUserRealm(owner))
	data.Pause(cross(cur), "catalog", true)
	testing.SetRealm(testing.NewUserRealm(erin))
	Unqueue(cross(cur), 5, sp.ids[0])
	uassert.Equal(t, "none", PickPayoutStatus(picker, 5, s.Start))
	uassert.Equal(t, int64(pickPay), sp.held(s.Start+s.Dur)) // still held, lapses by itself
	testing.SetRealm(testing.NewUserRealm(owner))
	data.Pause(cross(cur), "catalog", false)
}

// Review R31: the one-sponsored-pick-per-artist-and-hour rule looks around
// when a pick really airs: a pick waiting 70 minutes behind a queue still
// sees the artist's sponsored slot there.
func TestSponsorQuotaAroundAiring(cur realm, t *testing.T) {
	reset(cur)
	ts := now()
	st := rd().station(5)
	st.setSlots([]Slot{{Track: 1, Start: ts + 70*60, Dur: 180, By: carol, Pay: pickPay, artist: 7}})
	sponsorQuota(st, 7, 180, ts, ts) // an hour before: allowed
	uassert.PanicsContains(t, cur, "this hour here", func() { sponsorQuota(st, 7, 180, ts, ts+75*60) })
}
