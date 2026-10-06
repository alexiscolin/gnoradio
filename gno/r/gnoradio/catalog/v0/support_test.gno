package catalog

import (
	"strings"
	"testing"

	"gno.land/p/nt/avl/v0"
	"gno.land/p/nt/uassert/v0"
	"gno.land/p/nt/urequire/v0"
)

func resetSupport() {
	treasury = dave
	totalSupport, nSupporters, monthlyGoal = 0, 0, 0
	supporterTotal, monthly = avl.Tree{}, avl.Tree{}
	topSupport = nil
	activity, activityHead, activityN = [activitySize]Activity{}, 0, 0
}

func TestSupportGnoRadio(cur realm, t *testing.T) {
	reset()
	resetSupport()
	testing.IssueCoins(realmAddr, ugnots(8*ugnot))
	testing.SetOriginSend(ugnots(5 * ugnot))
	testing.SetRealm(testing.NewUserRealm(carol))
	before := balance(dave)
	SupportGnoRadio(cross(cur))
	uassert.Equal(t, before+5*ugnot, balance(dave))
	testing.SetOriginSend(ugnots(3 * ugnot))
	SupportGnoRadio(cross(cur))
	uassert.Equal(t, int64(0), balance(realmAddr))
	uassert.Equal(t, int64(8*ugnot), totalSupport)
	uassert.Equal(t, 1, nSupporters)
	uassert.Equal(t, carol.String(), topSupport[0].Key)

	js := SupportJSON()
	urequire.True(t, strings.Contains(js, `"total":8000000`), js)
	urequire.True(t, strings.Contains(js, `"supporters":1`), js)
	urequire.True(t, strings.Contains(js, `"monthTotal":8000000`), js)
	urequire.True(t, strings.Contains(js, `"treasury":"`+dave.String()+`"`), js)

	testing.SetOriginSend(ugnots(10))
	uassert.AbortsContains(t, cur, "support is between", func() { SupportGnoRadio(cross(cur)) })
	testing.SetOriginSend(nil)

	// Admin settings.
	uassert.AbortsWithMessage(t, cur, "catalog: admin only", func() { SetTreasury(cross(cur), bob) })
	testing.SetRealm(testing.NewUserRealm(boss))
	SetTreasury(cross(cur), bob)
	uassert.Equal(t, bob, Treasury())
	SetMonthlyGoal(cross(cur), 50*ugnot)
	urequire.True(t, strings.Contains(SupportJSON(), `"goal":50000000`))
}

func TestTipWithSupport(cur realm, t *testing.T) {
	reset()
	resetSupport()
	testing.SetRealm(testing.NewUserRealm(alice))
	RegisterArtist(cross(cur), "Alice", "")
	id := PublishTrack(cross(cur), "Song", 2, "1:40", "CC-BY", "none", "", ipfs, "", "", "", bob.String()+":30", "yes")

	// 11 GNOT with 10% support: 10 to the artist side (3 bob, 7 alice), 1 to GnoRadio.
	testing.IssueCoins(realmAddr, ugnots(11*ugnot))
	testing.SetOriginSend(ugnots(11 * ugnot))
	testing.SetRealm(testing.NewUserRealm(carol))
	a0, b0, d0 := balance(alice), balance(bob), balance(dave)
	TipWithSupport(cross(cur), id, 10)
	uassert.Equal(t, a0+7*ugnot, balance(alice))
	uassert.Equal(t, b0+3*ugnot, balance(bob))
	uassert.Equal(t, d0+1*ugnot, balance(dave))
	uassert.Equal(t, int64(10*ugnot), getTrack(id).Tips)
	uassert.Equal(t, int64(10*ugnot), getArtist(1).Tips)
	uassert.Equal(t, int64(1*ugnot), totalSupport)

	// Rounding: everything attached is paid out, the artist side gets the floor.
	const odd = 1_000_003
	testing.IssueCoins(realmAddr, ugnots(odd))
	testing.SetOriginSend(ugnots(odd))
	a0, b0, d0 = balance(alice), balance(bob), balance(dave)
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

func TestActivityRing(t *testing.T) {
	resetSupport()
	for i := 1; i <= 70; i++ {
		recordActivity("like", alice, i, 1, 0)
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
