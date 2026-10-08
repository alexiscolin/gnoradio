package catalog

import (
	"strings"
	"testing"

	"gno.land/p/gnoradio/text/v0"
	"gno.land/p/nt/uassert/v0"
	"gno.land/p/nt/urequire/v0"
)

// treasuryTo points the treasury at a fresh wallet and returns it.
func treasuryTo(cur realm) address {
	to := who("treasury")
	testing.SetRealm(testing.NewUserRealm(boss))
	SetTreasury(cross(cur), to)
	return to
}

func TestSupportGnoRadio(cur realm, t *testing.T) {
	dave := treasuryTo(cur)
	carol := who("carol")
	_, total0, n0, month0, _ := SupportInfo()
	testing.IssueCoins(realmAddr, ugnots(8*ugnot))
	testing.SetOriginSend(ugnots(5 * ugnot))
	testing.SetRealm(testing.NewUserRealm(carol))
	SupportGnoRadio(cross(cur))
	uassert.Equal(t, int64(5*ugnot), balance(dave))
	testing.SetOriginSend(ugnots(3 * ugnot))
	SupportGnoRadio(cross(cur))
	uassert.Equal(t, int64(0), balance(realmAddr))
	_, total, n, _, _ := SupportInfo()
	uassert.Equal(t, total0+8*ugnot, total)
	uassert.Equal(t, n0+1, n)

	js := SupportJSON()
	urequire.True(t, strings.Contains(js, `"total":`+text.Itoa64(total)), js)
	urequire.True(t, strings.Contains(js, `"supporters":`+text.Itoa(n)), js)
	urequire.True(t, strings.Contains(js, `"monthTotal":`+text.Itoa64(month0+8*ugnot)), js)
	urequire.True(t, strings.Contains(js, `"treasury":"`+dave.String()+`"`), js)
	urequire.True(t, strings.Contains(js, `{"address":"`+carol.String()+`","amount":8000000}`), js)

	testing.SetOriginSend(ugnots(10))
	uassert.AbortsContains(t, cur, "support is between", func() { SupportGnoRadio(cross(cur)) })
	testing.SetOriginSend(nil)

	// Admin settings.
	uassert.AbortsWithMessage(t, cur, "catalog: admin only", func() { SetTreasury(cross(cur), carol) })
	testing.SetRealm(testing.NewUserRealm(boss))
	SetMonthlyGoal(cross(cur), 50*ugnot)
	urequire.True(t, strings.Contains(SupportJSON(), `"goal":50000000`))
}

func TestTipWithSupport(cur realm, t *testing.T) {
	dave := treasuryTo(cur)
	alice, aid := artist(cur, "alice")
	bob, carol := who("bob"), who("carol")
	testing.SetRealm(testing.NewUserRealm(alice))
	id := PublishTrack(cross(cur), "Song", 2, "1:40", "CC-BY", "none", "", ipfs, "", "", "", bob.String()+":30", "yes")
	verified(cur, aid)
	_, total0, _, _, _ := SupportInfo()

	// 11 GNOT with 10% support: 10 to the artist side (3 bob, 7 alice), 1 to GnoRadio.
	testing.IssueCoins(realmAddr, ugnots(11*ugnot))
	testing.SetOriginSend(ugnots(11 * ugnot))
	testing.SetRealm(testing.NewUserRealm(carol))
	TipWithSupport(cross(cur), id, 10)
	uassert.Equal(t, int64(7*ugnot), balance(alice))
	uassert.Equal(t, int64(3*ugnot), balance(bob))
	uassert.Equal(t, int64(1*ugnot), balance(dave))
	uassert.Equal(t, int64(10*ugnot), getTrack(rd(), id).Tips)
	uassert.Equal(t, int64(10*ugnot), getArtist(rd(), aid).Tips)
	_, total, _, _, _ := SupportInfo()
	uassert.Equal(t, total0+1*ugnot, total)

	// Rounding: everything attached is paid out, the artist side gets the floor.
	const odd = 1_000_003
	testing.IssueCoins(realmAddr, ugnots(odd))
	testing.SetOriginSend(ugnots(odd))
	a0, b0, d0 := balance(alice), balance(bob), balance(dave)
	TipWithSupport(cross(cur), id, 7)
	artistPart := int64(odd * 100 / 107)
	uassert.Equal(t, int64(odd)-artistPart, balance(dave)-d0)
	uassert.Equal(t, artistPart, (balance(alice)-a0)+(balance(bob)-b0))
	uassert.Equal(t, int64(0), balance(realmAddr))

	testing.SetOriginSend(ugnots(ugnot))
	uassert.AbortsContains(t, cur, "supportPct", func() { TipWithSupport(cross(cur), id, 51) })
	uassert.AbortsContains(t, cur, "supportPct", func() { TipWithSupport(cross(cur), id, -1) })
	testing.SetOriginSend(ugnots(105_000))
	uassert.AbortsContains(t, cur, "between 0.1", func() { TipWithSupport(cross(cur), id, 10) })
	testing.SetOriginSend(nil)

	feed := ActivityJSON(2)
	urequire.True(t, strings.HasPrefix(feed, `[{"kind":"support"`) || strings.HasPrefix(feed, `[{"kind":"tip"`), feed)
	urequire.True(t, strings.Contains(ActivityJSON(10), `"kind":"publish"`))
}

func TestActivityRing(cur realm, t *testing.T) {
	alice := who("alice")
	for i := 1; i <= 70; i += 35 { // two transactions: a Batch takes 64 ops
		tx := rd()
		for j := i; j < i+35; j++ {
			tx.activity("like", alice, text.Itoa(j), "1", "0")
		}
		testing.SetRealm(testing.NewCodeRealm(self))
		save(cur, tx)
	}
	got := Activities(100)
	uassert.Equal(t, activitySize, len(got))
	uassert.Equal(t, 70, got[0].Track)
	uassert.Equal(t, 7, got[len(got)-1].Track)
	uassert.Equal(t, 3, len(Activities(3)))
	urequire.True(t, strings.HasPrefix(ActivityJSON(1), `[{"kind":"like","by":"`+alice.String()+`","track":70,`))
	uassert.Equal(t, "2026-10", month(1791294000))
	uassert.Equal(t, "2026-11", month(1793900000))
}
