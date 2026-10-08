package catalog

import (
	"chain"
	"strings"
	"testing"

	"gno.land/p/gnoradio/store/v0"
	"gno.land/p/gnoradio/text/v0"
	"gno.land/p/nt/uassert/v0"
	"gno.land/r/gnoradio/data"
)

// Threat model rows of docs/ARCHITECTURE-v1.md section 8 that catalog owns.

// Payment bypass through a realm: every payable entrypoint takes coins only
// from a wallet's direct call. A MsgRun ephemeral realm has a pkgpath like
// any realm, so it fails IsUserCall the same way (v1.5.0's test harness
// cannot make an ephemeral caller: NewCodeRealm refuses /e/ paths).
func TestPayRefusesRealms(cur realm, t *testing.T) {
	_, _, _, id := promoTrack(cur)
	testing.SetOriginSend(ugnots(ugnot))
	testing.SetRealm(testing.NewCodeRealm("gno.land/r/evil/proxy"))
	uassert.AbortsContains(t, cur, "directly from your wallet", func() { Tip(cross(cur), id) })
	uassert.AbortsContains(t, cur, "directly from your wallet", func() { TipWithSupport(cross(cur), id, 10) })
	uassert.AbortsContains(t, cur, "directly from your wallet", func() { SupportGnoRadio(cross(cur)) })
	uassert.AbortsContains(t, cur, "directly from your wallet", func() { FundPromo(cross(cur)) })
	testing.SetOriginSend(nil)
}

// Rules realms end every transaction holding nothing.
func TestRulesHoldNothing(cur realm, t *testing.T) {
	owner, _, _, id := promoTrack(cur)
	carol := who("carol")
	pay := func(n int64) {
		testing.IssueCoins(realmAddr, ugnots(n)) // what the wallet's call brings
		testing.SetOriginSend(ugnots(n))
	}
	testing.SetRealm(testing.NewUserRealm(carol))
	pay(ugnot)
	Tip(cross(cur), id)
	uassert.Equal(t, int64(0), balance(realmAddr))
	pay(ugnot)
	TipWithSupport(cross(cur), id, 25)
	uassert.Equal(t, int64(0), balance(realmAddr))
	pay(ugnot)
	SupportGnoRadio(cross(cur))
	uassert.Equal(t, int64(0), balance(realmAddr))
	syncVault()
	testing.SetRealm(testing.NewUserRealm(owner))
	pay(ugnot)
	FundPromo(cross(cur))
	uassert.Equal(t, int64(0), balance(realmAddr))
	testing.SetOriginSend(nil)
	radioTip(cur, id, 10, carol, who("picker"), who("ref"), ugnot)
	uassert.Equal(t, int64(0), balance(realmAddr))
	uassert.True(t, balance(dataAddr) >= data.VaultTotal())
}

// The admin passes in two steps, every change mirrored to the data realm
// for the next release.
func TestAdminTwoStep(cur realm, t *testing.T) {
	bob, carol := who("bob"), who("carol")
	testing.SetRealm(testing.NewUserRealm(carol))
	uassert.AbortsWithMessage(t, cur, "catalog: admin only", func() { OfferAdmin(cross(cur), carol) })
	testing.SetRealm(testing.NewUserRealm(boss))
	OfferAdmin(cross(cur), bob)
	uassert.Equal(t, boss, Admin()) // nothing changes before the accept
	testing.SetRealm(testing.NewUserRealm(carol))
	uassert.AbortsContains(t, cur, "nothing offered to you", func() { AcceptAdmin(cross(cur)) })
	testing.SetRealm(testing.NewUserRealm(bob))
	testing.SetOriginSend(ugnots(1))
	uassert.AbortsContains(t, cur, "does not take coins", func() { AcceptAdmin(cross(cur)) })
	testing.SetOriginSend(nil)
	AcceptAdmin(cross(cur))
	uassert.Equal(t, bob, Admin())
	v, _ := data.Get(cConfig, "admin")
	uassert.Equal(t, bob.String(), v)
	uassert.True(t, strings.Contains(Info(), `"admin":"`+bob.String()+`"`))
	testing.SetRealm(testing.NewUserRealm(boss))
	uassert.AbortsWithMessage(t, cur, "catalog: admin only", func() { SetMonthlyGoal(cross(cur), 1) })
	// and back
	testing.SetRealm(testing.NewUserRealm(bob))
	OfferAdmin(cross(cur), boss)
	testing.SetRealm(testing.NewUserRealm(boss))
	AcceptAdmin(cross(cur))
	v, _ = data.Get(cConfig, "admin")
	uassert.Equal(t, boss.String(), v)
}

// Per-user lists and records are capped: nobody grows a value past the data
// realm's limits, nor makes a chunk others share too big.
func TestCaps(cur realm, t *testing.T) {
	alice, aid := artist(cur, "alice")
	id := publish(cur, alice, "Capped")
	heavy := who("heavy")
	ids := make([]int, maxFollows)
	for i := range ids {
		ids[i] = 1_000_000 + i // artists not followed yet
	}
	seed(cur, cUsers, heavy.String(), store.Rec(store.Pack(ids), "0", store.Pack(ids[:maxUserLists]), "0"))
	testing.SetRealm(testing.NewUserRealm(heavy))
	uassert.AbortsContains(t, cur, "follows limit reached", func() { Follow(cross(cur), aid) })
	uassert.AbortsContains(t, cur, "playlists per listener limit reached", func() { PublishPlaylist(cross(cur), "One more", text.Itoa(id)) })

	// The longest record an author may write leaves room for its counters
	// and early badges in an 8-record chunk under 16 KiB.
	long := "https://archive.org/download/" + strings.Repeat("x", 270)
	words := strings.Repeat("音", 64)
	testing.SetRealm(testing.NewUserRealm(alice))
	uassert.AbortsContains(t, cur, "too long", func() {
		PublishTrack(cross(cur), words, 2, "3:30", "cc by", "none", strings.Repeat("音", 160), long, sha, long, sha, "", "yes")
	})
	PublishTrack(cross(cur), "Short", 2, "3:30", "cc by", "none", "", long, sha, long, sha, "", "yes")
	uassert.True(t, chunkSize*(maxRec+earlyBadges*41+64)+1+3*chunkSize < 16<<10)
}

// Audit Y1: the data realm's admin mirror is the authority, so an admin
// change the previous release made after this one's init counts.
func TestAdminFollowsMirror(cur realm, t *testing.T) {
	other := who("newadmin")
	seed(cur, cConfig, "admin", other.String()) // as the previous release would
	uassert.Equal(t, other, Admin())
	testing.SetRealm(testing.NewUserRealm(boss))
	uassert.AbortsWithMessage(t, cur, "catalog: admin only", func() { SetMonthlyGoal(cross(cur), 1) })
	testing.SetRealm(testing.NewUserRealm(other))
	OfferAdmin(cross(cur), boss)
	uassert.Equal(t, boss, admin.Pending()) // an unchanged mirror keeps the offer
	seed(cur, cConfig, "admin", "")         // the previous release renounced
	testing.SetRealm(testing.NewUserRealm(other))
	uassert.AbortsWithMessage(t, cur, "catalog: admin only", func() { SetMonthlyGoal(cross(cur), 1) })
	uassert.Equal(t, address(""), Admin())
	seed(cur, cConfig, "admin", other.String())
	testing.SetRealm(testing.NewUserRealm(other))
	OfferAdmin(cross(cur), boss)
	testing.SetRealm(testing.NewUserRealm(boss))
	AcceptAdmin(cross(cur))
	uassert.Equal(t, boss, Admin())
}

// Audit Y2: a paused radio moves no promo coins and pays no tips.
func TestPausedRadio(cur realm, t *testing.T) {
	_, _, _, id := promoTrack(cur)
	testing.SetRealm(testing.NewUserRealm(dataOwner))
	data.Pause(cross(cur), "radio", true)
	testing.SetRealm(testing.NewCodeRealm(radioPath()))
	uassert.AbortsContains(t, cur, "radio is paused", func() { PromoReserve(cross(cur), id, who("fan"), now()+300) })
	uassert.AbortsContains(t, cur, "radio is paused", func() { RadioTip(cross(cur), id, 0, who("fan"), "", "", ugnot) })
	uassert.AbortsContains(t, cur, "radio is paused", func() { PromoClaim(cross(cur), id, who("fan"), now(), 30_000, 0) })
	testing.SetRealm(testing.NewUserRealm(dataOwner))
	data.Pause(cross(cur), "radio", false)
}

// Audit Y3: no payout to a GnoRadio realm, whatever the radio names.
func TestNoPayoutToRealms(cur realm, t *testing.T) {
	_, _, _, id := promoTrack(cur)
	toP, _ := radioTip(cur, id, 0, who("carol"), dataAddr, "", ugnot)
	uassert.Equal(t, int64(0), toP)
	uassert.Equal(t, int64(0), balance(realmAddr))
	// A collaborator that became a GnoRadio realm (proposed for a release
	// after publishing) gets nothing: the owner keeps its share.
	owner, aid0 := artist(cur, "splitter")
	later := "gno.land/r/gnoradio/radio/v" + text.Itoa(seq+100)
	testing.SetRealm(testing.NewUserRealm(owner))
	tid := PublishTrack(cross(cur), "Split", 2, "1:40", "CC-BY", "none", "", ipfs, "", "", "", chain.PackageAddress(later).String()+":30", "yes")
	verified(cur, aid0)
	testing.SetRealm(testing.NewUserRealm(dataOwner))
	data.Propose(cross(cur), "radio", later)
	testing.IssueCoins(realmAddr, ugnots(ugnot))
	testing.SetOriginSend(ugnots(ugnot))
	testing.SetRealm(testing.NewUserRealm(who("carol")))
	Tip(cross(cur), tid)
	testing.SetOriginSend(nil)
	uassert.Equal(t, int64(0), balance(chain.PackageAddress(later)))
	uassert.Equal(t, int64(ugnot), balance(owner))
	testing.SetRealm(testing.NewUserRealm(dataOwner))
	data.Cancel(cross(cur))

	testing.SetRealm(testing.NewUserRealm(boss))
	aid := CreateArtist(cross(cur), OriginCurated, name("Realm Owned"), "", "")
	uassert.AbortsContains(t, cur, "invalid or already has", func() { AssignArtist(cross(cur), aid, realmAddr) })
}
