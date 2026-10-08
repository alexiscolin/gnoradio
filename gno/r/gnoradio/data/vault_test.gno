package data

import (
	"chain"
	"chain/banker"
	"strings"
	"testing"

	"gno.land/p/nt/uassert/v0"
)

var dataAddr = chain.PackageAddress("gno.land/r/gnoradio/data")

func balance(a address) int64 { return banker.NewReadonlyBanker().GetCoin(a, denom) }

// fund plays catalog/v1 funding an account for funder: it sends the coins
// to data, then credits them.
func fund(cur realm, acct string, funder address, amt int64) {
	testing.IssueCoins(dataAddr, chain.Coins{{denom, amt}})
	testing.SetRealm(testing.NewCodeRealm(cat1))
	VaultCredit(cross(cur), acct, funder, amt)
}

// invariant: data holds at least what the vault owes.
func invariant(t *testing.T) {
	uassert.True(t, balance(dataAddr) >= VaultTotal(), "banker(data) >= VaultTotal")
}

func TestVaultInvariant(cur realm, t *testing.T) {
	reset()
	start := balance(dataAddr)
	testing.SetRealm(testing.NewCodeRealm(cat1))
	// coins not received yet, or already owed to another account
	uassert.AbortsContains(t, cur, "send the coins before crediting them", func() { VaultCredit(cross(cur), "catalog/1", alice, start+1) })
	fund(cur, "catalog/1", alice, 1000)
	uassert.AbortsContains(t, cur, "send the coins before crediting them", func() { VaultCredit(cross(cur), "catalog/2", bob, start+1) })
	// an amount that would wrap vaultTotal+amt
	uassert.AbortsContains(t, cur, "send the coins before crediting them", func() { VaultCredit(cross(cur), "catalog/3", bob, 1<<63-1) })
	invariant(t)

	d := today()
	VaultHold(cross(cur), "catalog/1", 300, d+2)
	VaultHold(cross(cur), "catalog/1", 200, d+2)
	uassert.AbortsContains(t, cur, "not enough free", func() { VaultHold(cross(cur), "catalog/1", 501, d) })
	uassert.Equal(t, int64(500), VaultHeld("catalog/1", d+2))
	uassert.Equal(t, int64(100), VaultRelease(cross(cur), "catalog/1", 100, d+2))
	uassert.Equal(t, int64(400), VaultRelease(cross(cur), "catalog/1", 999, d+2)) // only what is held
	VaultHold(cross(cur), "catalog/1", 300, d+2)
	VaultPay(cross(cur), "catalog/1", bob, 120, d+2)
	uassert.AbortsContains(t, cur, "no such hold", func() { VaultPay(cross(cur), "catalog/1", bob, 181, d+2) })
	uassert.AbortsContains(t, cur, "no such hold", func() { VaultPay(cross(cur), "catalog/1", bob, 1, d+1) })
	invariant(t)
	f, bal, free := VaultInfo("catalog/1")
	uassert.Equal(t, alice, f)
	uassert.Equal(t, int64(880), bal)
	uassert.Equal(t, int64(700), free)
	uassert.Equal(t, int64(880), VaultTotal())
	uassert.Equal(t, start+880, balance(dataAddr))
	uassert.Equal(t, int64(120), balance(bob))

	// a refund pays everything back, holds included
	uassert.Equal(t, int64(880), VaultRefund(cross(cur), "catalog/1"))
	uassert.Equal(t, int64(0), VaultRefund(cross(cur), "catalog/1"))
	uassert.Equal(t, int64(880), balance(alice))
	uassert.Equal(t, int64(0), VaultTotal())
	invariant(t)
}

func TestVaultHoldsLapse(cur realm, t *testing.T) {
	reset()
	fund(cur, "catalog/1", alice, 1000)
	d := today()
	uassert.AbortsContains(t, cur, "within 31 days", func() { VaultHold(cross(cur), "catalog/1", 1, d-1) })
	uassert.AbortsContains(t, cur, "within 31 days", func() { VaultHold(cross(cur), "catalog/1", 1, d+32) })
	VaultHold(cross(cur), "catalog/1", 600, d)
	VaultHold(cross(cur), "catalog/1", 400, d+1)
	_, _, free := VaultInfo("catalog/1")
	uassert.Equal(t, int64(0), free)
	testing.SkipHeights(blocksIn(day))
	_, _, free = VaultInfo("catalog/1")
	uassert.Equal(t, int64(600), free) // the hold of day d lapsed by itself
	uassert.AbortsContains(t, cur, "no such hold", func() { VaultPay(cross(cur), "catalog/1", bob, 1, d) })
	uassert.Equal(t, int64(0), VaultRelease(cross(cur), "catalog/1", 600, d))
	testing.SkipHeights(blocksIn(day))
	_, _, free = VaultInfo("catalog/1")
	uassert.Equal(t, int64(1000), free)
}

func TestWithdrawFunderOnly(cur realm, t *testing.T) {
	reset()
	fund(cur, "catalog/1", alice, 1000)
	VaultHold(cross(cur), "catalog/1", 400, today())
	testing.SetRealm(testing.NewUserRealm(bob))
	uassert.AbortsContains(t, cur, "nothing of yours", func() { VaultWithdraw(cross(cur), "catalog/1") })
	testing.SetRealm(testing.NewCodeRealm(cat1))
	uassert.AbortsContains(t, cur, "nothing of yours", func() { VaultWithdraw(cross(cur), "catalog/1") })
	testing.SetRealm(testing.NewUserRealm(dev))
	uassert.AbortsContains(t, cur, "nothing of yours", func() { VaultWithdraw(cross(cur), "catalog/1") })
	testing.SetRealm(testing.NewUserRealm(alice))
	VaultWithdraw(cross(cur), "catalog/1")
	uassert.Equal(t, int64(600), balance(alice))
	uassert.AbortsContains(t, cur, "nothing of yours", func() { VaultWithdraw(cross(cur), "catalog/1") }) // the hold stays
	uassert.Equal(t, int64(400), VaultTotal())
	invariant(t)
}

// A malicious release proposed with a stolen owner key: during the delay,
// and while every role is paused, funders still take their coins out.
func TestWithdrawWhilePaused(cur realm, t *testing.T) {
	reset()
	fund(cur, "catalog/1", alice, 1000)
	testing.SetRealm(testing.NewUserRealm(dev))
	Propose(cross(cur), "catalog", evil)
	testing.SetRealm(testing.NewCodeRealm(evil))
	Ready(cross(cur))
	testing.SetRealm(testing.NewUserRealm(dev))
	Pause(cross(cur), "", true)
	testing.SetRealm(testing.NewCodeRealm(cat1))
	uassert.AbortsContains(t, cur, "catalog is paused", func() { VaultHold(cross(cur), "catalog/1", 1, today()) })
	testing.SetRealm(testing.NewUserRealm(alice))
	VaultWithdraw(cross(cur), "catalog/1")
	uassert.Equal(t, int64(1000), balance(alice))
	invariant(t)
}

func TestWithdrawAfterRenounce(cur realm, t *testing.T) {
	reset()
	fund(cur, "catalog/1", alice, 500)
	testing.SetRealm(testing.NewUserRealm(dev))
	Renounce(cross(cur))
	testing.SetRealm(testing.NewUserRealm(alice))
	VaultWithdraw(cross(cur), "catalog/1")
	uassert.Equal(t, int64(500), balance(alice))
}

func TestVaultGuards(cur realm, t *testing.T) {
	reset()
	fund(cur, "catalog/1", alice, 1000)
	VaultHold(cross(cur), "catalog/1", 500, today())
	// payouts never go to a GnoRadio realm, which must end every call empty
	uassert.AbortsContains(t, cur, "outside GnoRadio", func() { VaultPay(cross(cur), "catalog/1", chain.PackageAddress(cat1), 1, today()) })
	uassert.AbortsContains(t, cur, "outside GnoRadio", func() { VaultPay(cross(cur), "catalog/1", dataAddr, 1, today()) })
	uassert.AbortsContains(t, cur, "outside GnoRadio", func() { VaultCredit(cross(cur), "catalog/2", chain.PackageAddress(radio1), 1) })
	// a new funder needs the account emptied first, so a writer cannot hand
	// alice's coins to bob
	testing.IssueCoins(dataAddr, chain.Coins{{denom, 10}})
	uassert.AbortsContains(t, cur, "refund the previous funder first", func() { VaultCredit(cross(cur), "catalog/1", bob, 10) })
	uassert.AbortsContains(t, cur, "must be positive", func() { VaultHold(cross(cur), "catalog/1", 0, today()) })
	uassert.AbortsContains(t, cur, "must be positive", func() { VaultPay(cross(cur), "catalog/1", bob, -1, today()) })
	uassert.AbortsContains(t, cur, "at most 64 bytes", func() { VaultHold(cross(cur), "catalog/"+string(make([]byte, 60)), 1, today()) })
	// only the writer of the account's role
	testing.SetRealm(testing.NewCodeRealm(radio1))
	uassert.AbortsContains(t, cur, "only "+cat1, func() { VaultRefund(cross(cur), "catalog/1") })
	uassert.AbortsContains(t, cur, "only "+cat1, func() { VaultPay(cross(cur), "catalog/1", bob, 1, today()) })
	testing.SetRealm(testing.NewUserRealm(alice))
	uassert.AbortsContains(t, cur, "only "+cat1, func() { VaultPay(cross(cur), "catalog/1", alice, 1, today()) })
	invariant(t)
}

// A pause stops the vault's clock: a hold does not lapse while its writer
// cannot pay it, and lapses as much later.
func TestPauseKeepsHolds(cur realm, t *testing.T) {
	reset()
	fund(cur, "catalog/1", alice, 1000)
	d := today()
	VaultHold(cross(cur), "catalog/1", 400, d)
	testing.SetRealm(testing.NewUserRealm(dev))
	Pause(cross(cur), "catalog", true)
	testing.SkipHeights(blocksIn(8 * day))
	uassert.Equal(t, int64(400), VaultHeld("catalog/1", d))
	Pause(cross(cur), "catalog", false)
	uassert.Equal(t, d, VaultDay())
	testing.SetRealm(testing.NewCodeRealm(cat1))
	VaultPay(cross(cur), "catalog/1", bob, 400, d)
	uassert.Equal(t, int64(400), balance(bob))
	// a hold reaches 31 days of real time, not of the lagging clock
	uassert.AbortsContains(t, cur, "within 31 days", func() { VaultHold(cross(cur), "catalog/1", 1, d+8+32) })
	VaultHold(cross(cur), "catalog/1", 1, d+8+31)
}

// Every address the vault stores or pays to is in its canonical spelling.
func TestVaultCanonicalAddresses(cur realm, t *testing.T) {
	reset()
	up := address(strings.ToUpper(alice.String()))
	testing.IssueCoins(dataAddr, chain.Coins{{denom, 100}})
	testing.SetRealm(testing.NewCodeRealm(cat1))
	uassert.AbortsContains(t, cur, "outside GnoRadio", func() { VaultCredit(cross(cur), "catalog/1", up, 100) })
	VaultCredit(cross(cur), "catalog/1", alice, 100)
	VaultHold(cross(cur), "catalog/1", 100, today())
	uassert.AbortsContains(t, cur, "outside GnoRadio", func() { VaultPay(cross(cur), "catalog/1", up, 100, today()) })
}
