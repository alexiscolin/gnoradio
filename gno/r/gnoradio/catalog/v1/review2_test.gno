package catalog

import (
	"strings"
	"testing"

	"gno.land/p/gnoradio/store/v0"
	"gno.land/p/gnoradio/text/v0"
	"gno.land/p/nt/uassert/v0"
	"gno.land/r/gnoradio/data"
)

func upper(a address) address { return address(strings.ToUpper(a.String())) }

// M4: an upper-case address is the same account but compares as another
// string. Every address argument refuses it, or treats it as absent.
func TestUpperCaseAddresses(cur realm, t *testing.T) {
	alice, _, aid, id := promoTrack(cur)
	testing.SetRealm(testing.NewUserRealm(alice))
	SetPromoShare(cross(cur), 20)
	carol := who("carol")
	uassert.True(t, upper(carol).IsValid())

	// A tipper naming themselves as ref or picker in upper case gets nothing back.
	toP, toR := radioTip(cur, id, 0, carol, upper(carol), upper(carol), 10*ugnot)
	uassert.Equal(t, int64(0), toP)
	uassert.Equal(t, int64(0), toR)
	uassert.Equal(t, int64(0), balance(upper(carol)))

	testing.SetRealm(testing.NewUserRealm(alice))
	uassert.AbortsContains(t, cur, "collaborators as", func() {
		PublishTrack(cross(cur), "Self Split", 2, "1:40", "CC-BY", "none", "", ipfs, "", "", "", upper(alice).String()+":30", "yes")
	})
	uassert.AbortsContains(t, cur, "collaborators as", func() {
		PublishTrack(cross(cur), "Realm Split", 2, "1:40", "CC-BY", "none", "", ipfs, "", "", "", upper(dataAddr).String()+":30", "yes")
	})

	testing.SetRealm(testing.NewUserRealm(boss))
	uassert.AbortsContains(t, cur, "invalid address", func() { SetTreasury(cross(cur), upper(carol)) })
	uassert.AbortsContains(t, cur, "not an address", func() { OfferAdmin(cross(cur), upper(carol)) })
	c := CreateArtist(cross(cur), "curated", name("Upper"), "", "")
	uassert.AbortsContains(t, cur, "invalid or already has", func() { AssignArtist(cross(cur), c, upper(carol)) })
	uassert.AbortsContains(t, cur, "invalid or already has", func() { AssignArtist(cross(cur), c, upper(alice)) })
	_ = aid
}

// L4: names that pass for GnoRadio's own roles are refused.
func TestReservedNames(cur realm, t *testing.T) {
	testing.SetRealm(testing.NewUserRealm(who("alice")))
	for _, n := range []string{"GnoRadio", "Gno Radio", "GNORADIO Moderator", "Gn0 Radi0", "The Gno-Radio Team",
		"Treasury", "Admin", "Official", "Staff", "Moderator", "Moderation", "GnoRadio Support", "Administrator", "Adm1n",
		"Gnoland", "gno.land", "GNO LAND Official", "Gn0.1and", "Adena", "Adena Wallet", "4DENA", "Audius", "AUDIUS Music", "Aud1us",
		"AdenaWallet", "Adena2", "Ade-na", "A.D.E.N.A", "AudiusOfficial", "The AudiusHQ", "Avdivs"} {
		uassert.AbortsContains(t, cur, "is reserved", func() { RegisterArtist(cross(cur), n, "") }, n)
	}
	// Adena and Audius are prefixes: names that only end with them pass.
	for _, n := range []string{"Pasadena", "La Cadena", "Claudius", "Macadena"} {
		testing.SetRealm(testing.NewUserRealm(who("alice")))
		RegisterArtist(cross(cur), name(n), "")
	}
	testing.SetRealm(testing.NewUserRealm(who("alice")))
	n := name("Badminton Club")
	RegisterArtist(cross(cur), n, "")
	// A name reserved after it was taken stays its owner's: a bio update keeps
	// it, a rename to another reserved name is refused.
	saved := reservedStems
	reservedStems = append(reservedStems, skeleton("Badminton"))
	RegisterArtist(cross(cur), n, "new bio")
	uassert.AbortsContains(t, cur, "is reserved", func() { RegisterArtist(cross(cur), n+" Two", "") })
	reservedStems = saved
	testing.SetRealm(testing.NewUserRealm(boss))
	uassert.AbortsContains(t, cur, "is reserved", func() { CreateArtist(cross(cur), "curated", "GnoRadio Official", "", "") })
}

// L5: more look-alikes fold to one skeleton.
func TestSkeletonMoreLookalikes(t *testing.T) {
	for _, p := range [][2]string{{"Kanye West", "Kanye Vvest"}, {"Drake", "Clrake"}, {"Muse", "Mu5e"},
		{"Eminem", "3minem"}, {"Abba", "4bba"}, {"Tool", "7ool"}, {"Drake", "C1rake"},
		{"Gorillaz", "9orillaz"}, {"Muse", "Mvse"}, {"Kanye West", "Kanye Uuest"}, {"Audius", "Avdivs"}} {
		uassert.Equal(t, skeleton(p[0]), skeleton(p[1]), p[1])
	}
}

// L6 + security review: no proof page verifies a curated import, neither on
// its source site (whose operator is not the artist) nor on any other domain
// (anyone can buy one): the moderator assigns it (AssignArtist).
func TestCuratedNotRobotVerifiable(cur realm, t *testing.T) {
	a := &Artist{Kind: OriginCurated, Source: "https://ccmixter.org/people/someone"}
	uassert.PanicsContains(t, cur, "moderator", func() { mustRobotVerifiable(a) })
	a.Source = ""
	uassert.PanicsContains(t, cur, "moderator", func() { mustRobotVerifiable(a) })
	a.Kind = OriginAudius
	mustRobotVerifiable(a)
	a.Kind = OriginArtist
	mustRobotVerifiable(a)
}

// L11: Unlike gives the early-listener badge back.
func TestUnlikeDropsEarlyBadge(cur realm, t *testing.T) {
	alice, _ := artist(cur, "alice")
	id := publish(cur, alice, "Song")
	var fans []address
	for i := 0; i < 3; i++ {
		fans = append(fans, who("fan"))
		testing.SetRealm(testing.NewUserRealm(fans[i]))
		Like(cross(cur), id)
	}
	testing.SetRealm(testing.NewUserRealm(fans[1]))
	Unlike(cross(cur), id)
	early := getTrack(rd(), id).Early
	uassert.Equal(t, 2, len(early))
	uassert.Equal(t, fans[0], early[0])
	uassert.Equal(t, fans[2], early[1])
	testing.SetRealm(testing.NewUserRealm(fans[0]))
	Unlike(cross(cur), id)
	testing.SetRealm(testing.NewUserRealm(fans[2]))
	Unlike(cross(cur), id)
	uassert.Equal(t, 0, len(getTrack(rd(), id).Early))
}

// L8: like/unlike cycling (or many likes in a row) writes one feed entry.
func TestLikeCyclingFeed(cur realm, t *testing.T) {
	alice, aid := artist(cur, "alice")
	a, b := publish(cur, alice, "A"), publish(cur, alice, "B")
	carol := who("carol")
	testing.SetRealm(testing.NewUserRealm(carol))
	for i := 0; i < 3; i++ {
		Like(cross(cur), a)
		Unlike(cross(cur), a)
		Like(cross(cur), b)
		Unlike(cross(cur), b)
	}
	Follow(cross(cur), aid)
	Unfollow(cross(cur), aid)
	Follow(cross(cur), aid)
	n := map[string]int{}
	for _, e := range Activities(activitySize) {
		if e.By == carol {
			n[e.Kind]++
		}
	}
	uassert.Equal(t, 1, n["like"])
	uassert.Equal(t, 1, n["follow"])
}

// L10: a tipper's rank counts what reached the artist side, not the promo
// shares a second wallet of theirs may take back.
func TestTipRankCountsNet(cur realm, t *testing.T) {
	alice, _, _, id := promoTrack(cur)
	testing.SetRealm(testing.NewUserRealm(alice))
	SetPromoShare(cross(cur), 20)
	carol, alt := who("carol"), who("alt")
	_, toR := radioTip(cur, id, 0, carol, "", alt, 10*ugnot)
	uassert.Equal(t, int64(2*ugnot), toR)
	uassert.Equal(t, int64(8*ugnot), user(rd(), carol).Tipped)
	uassert.Equal(t, int64(8*ugnot), Activities(1)[0].Amount)
}

// L3 and M6: pending claims are listed; the proof host of a verified
// artist is public.
func TestPendingClaimsAndProofHost(cur realm, t *testing.T) {
	_, a1 := artist(cur, "claimant")
	_, a2 := artist(cur, "claimant")
	_, gen := botKey(rd())
	before, n0 := PendingClaims(0, 100)
	seed(cur, cClaims, store.Pad(a1), store.Rec(who("w").String(), "https://a.example/x", text.Itoa64(now()), text.Itoa(gen)))
	seed(cur, cClaims, store.Pad(a2), store.Rec(who("w").String(), "https://b.example/x", text.Itoa64(now()), text.Itoa(gen+1))) // stale key
	ids, n := PendingClaims(0, 100)
	uassert.Equal(t, n0+2, n)
	uassert.Equal(t, len(before)+1, len(ids))
	last := ids[len(ids)-1]
	uassert.Equal(t, a1, last.Artist)
	uassert.Equal(t, "https://a.example/x", last.Proof)
	uassert.Equal(t, now()+claimDelay, last.ReadyAt)

	uassert.Equal(t, "", ProofHost(a1))
	seed(cur, cProofs, store.Pad(a1), "https://Proof.Example.org/.well-known/gnoradio.txt")
	uassert.Equal(t, "", ProofHost(a1)) // not verified
	verified(cur, a1)
	uassert.Equal(t, "proof.example.org", ProofHost(a1))
	uassert.True(t, strings.Contains(ArtistJSON(a1), `"proofHost":"proof.example.org"`))
	uassert.True(t, strings.Contains(ArtistJSON(a2), `"proofHost":""`))
}

// L18: a ranged set past 100 ranges is read whole.
func TestRangesPastOnePage(cur realm, t *testing.T) {
	carol := who("carol")
	for r := 0; r < 105; r++ {
		seed(cur, cLikes, rangeKey(carol.String(), r<<idRange+1), store.Pack([]int{r<<idRange + 1}))
	}
	likes, _, _, _ := UserStats(carol)
	uassert.Equal(t, 105, likes)
	got := LikedPage(carol, 100, 10)
	uassert.Equal(t, 5, len(got))
	uassert.Equal(t, 1, got[4])
	_ = data.Size
}

// Auditor Y1: a proof's host is the one it is read from. "?@" or "#@" tricks,
// user info and ports are refused, and a stored one is never shown wrong.
func TestProofHostNotForged(cur realm, t *testing.T) {
	for _, p := range []string{"https://realartist.com@evil.com/x", "https://evil.com:443/x"} {
		uassert.False(t, validHost(hostOf(p)), p) // Claim refuses these
	}
	uassert.Equal(t, "evil.com", hostOf("https://evil.com?@realartist.com/x"))
	uassert.Equal(t, "evil.com", hostOf("https://evil.com#@realartist.com/x"))
	_, aid := artist(cur, "forged")
	seed(cur, cProofs, store.Pad(aid), "https://evil.com?@realartist.com/x")
	verified(cur, aid)
	uassert.Equal(t, "evil.com", ProofHost(aid))
	seed(cur, cProofs, store.Pad(aid), "https://realartist.com@evil.com/x")
	uassert.Equal(t, "", ProofHost(aid))
}
