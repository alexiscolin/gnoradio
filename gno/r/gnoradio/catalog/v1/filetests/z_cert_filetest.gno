// PKGPATH: gno.land/r/test/cert
package cert

// Verification with real robot certificates. The vectors were signed by the
// robot's own code (app/netlify/bot.ts signCertificate, seed 0x07 * 32) over
// catalog.ClaimMessage: chain "dev", data realm gno.land/r/gnoradio/data,
// artist, wallet, proof and expiry. A filetest starts from an empty
// deployment, so the artist ids below are fixed.

import (
	"chain"
	"strings"
	"testing"

	"gno.land/p/nt/testutils/v0"
	catalog "gno.land/r/gnoradio/catalog/v1"
)

const (
	robotPub = "ea4a6c63e29c520abef5507b132ec5f9954776aebebe7b92421eea691446d22c"
	proof    = "https://audius.co/nighttapes"
	t0       = int64(1234567890)
	e0       = t0 + 600                   // expiry of the certificates signed at t0
	e1       = t0 + (72*3600/5+1)*5 + 600 // expiry of those signed after the 72 hours
	ipfs     = "ipfs://bafybeigdyrzt5sfp7udm7hu76uh7y26nf3efuylqabf3oclgtqy55fbzdi"

	dave1      = "369b313c0e3c95956a4f2e33bab71e20646edf2eee87b0f823b251ed1a6d9c55b0a6e884454c08762ef684d69b388659d0992b1089c90fb9a2fd4ddfc3e6c50e"
	staging    = "beaed3e911611f3912c0b05cd5fb92781c2630b8d674386d6ad123e21d9d37e956bf4ef50fedf5044a18ad86364b90aad6d7cdee6a5e482275076f49cb7acf0e" // dave1 for gno.land/r/staging/gnoradio/data
	bob2       = "09f8520a818a9a3fffd0e6962a6626bf19530f7a72c38286f90cf2813b4ea520dc44adbe1b4d88f61665008a584c2779e7c5255ce1bbe24a2b3e9f380eb1f30b"
	alice3     = "5281b712fb5f94e9cd5bf8900b6c8d793f00317bf620230695717c3f1959f94e076009d9b9fe19661305893ba0d8b6740ae542bb7eb0e20e6c9a9cf545b27001"
	alice2     = "e97065ae51e2a75a7e4727d9d7a784a2bf416a2db125251c2b72e1a86ef790e966ee8d36e519770ffd17c168526c24f45cfde63390e8050335cf1d30ba3a350c"
	bob1late   = "1f645457736ee3cb39479bab3141a96c278431e8d67a8e0e66ced02275651f51ffdfa8cb2c15d103d409bf6d0f4fbd567b274d59755b9f9cbfbe56adc5865d05"
	alice2late = "e74d3d10b855b1deb4729ec052521ccbd7c092b78c0711bbd88c7986c4fa5341f8a4009982330b0d9d6fc213a6d2d0859926c07b24716fbd12d74bbb06391b0c"
)

var (
	alice = testutils.TestAddress("alice")
	bob   = testutils.TestAddress("bob")
	carol = testutils.TestAddress("carol")
	dave  = testutils.TestAddress("dave")
	cat   = chain.PackageAddress("gno.land/r/gnoradio/catalog/v1")
)

func check(ok bool, what string) {
	if !ok {
		println("FAIL:", what)
	}
}

// fails runs fn and checks that it aborts with a message holding want.
func fails(want string, fn func()) {
	r := revive(fn)
	s, _ := r.(string)
	if e, ok := r.(error); ok {
		s = e.Error()
	}
	if !strings.Contains(s, want) {
		println("FAIL: want abort", want, "got", s)
	}
}

// skip moves n blocks of 5 s ahead. testing.SkipHeights also clears the
// chain id, which certificates are bound to: put it back.
func skip(n int64) {
	testing.SkipHeights(n)
	ctx := testing.GetContext()
	ctx.ChainID = "dev"
	testing.SetContext(ctx)
}

func main(cur realm) {
	admin := catalog.Admin()
	testing.SetRealm(testing.NewUserRealm(admin))
	k := catalog.CreateArtist(cross(cur), catalog.OriginAudius, "", "", "audius-user:nt1")
	testing.SetRealm(testing.NewCodeRealm("gno.land/r/gnoradio/radio/v1")) // radio.ImportTrack does this
	tr := catalog.ImportFor(cross(cur), admin, k, "", 1, "3:00", "", "", "audius:Dk3aQ", "", "", "", "", "")
	testing.SetRealm(testing.NewUserRealm(alice))
	own := catalog.RegisterArtist(cross(cur), "Alice", "")
	testing.SetRealm(testing.NewUserRealm(admin))
	free := catalog.CreateArtist(cross(cur), catalog.OriginCurated, "Komiku", "", "")
	check(k == 1 && own == 2 && free == 3, "artist ids")

	// No robot key yet; then only a valid, unexpired certificate for the caller.
	testing.SetRealm(testing.NewUserRealm(dave))
	fails("paused", func() { catalog.Claim(cross(cur), k, proof, e0, dave1) })
	testing.SetRealm(testing.NewUserRealm(admin))
	fails("32-byte", func() { catalog.SetBot(cross(cur), "abcd") })
	catalog.SetBot(cross(cur), robotPub)
	testing.SetRealm(testing.NewUserRealm(dave))
	fails("not valid", func() { catalog.Claim(cross(cur), k, proof, e0, strings.Repeat("cd", 64)) })
	fails("expired", func() { catalog.Claim(cross(cur), k, proof, t0-1, dave1) })
	fails("expired", func() { catalog.Claim(cross(cur), k, proof, t0+2*3600+1, dave1) })
	fails("https link", func() { catalog.Claim(cross(cur), k, "http://x.y", e0, dave1) })
	// TestCertOtherDeployment: signed for a staging data realm on this chain.
	fails("not valid", func() { catalog.Claim(cross(cur), k, proof, e0, staging) })
	// TestCertOtherWallet: dave's certificate is worthless to bob.
	testing.SetRealm(testing.NewUserRealm(bob))
	fails("not valid", func() { catalog.Claim(cross(cur), k, proof, e0, dave1) })
	// A self-registered profile is verified for its own wallet only.
	fails("another wallet", func() { catalog.Claim(cross(cur), own, proof, e0, bob2) })
	// A wallet that already has a profile cannot take a second one.
	testing.SetRealm(testing.NewUserRealm(alice))
	fails("already has an artist", func() { catalog.Claim(cross(cur), free, proof, e0, alice3) })

	testing.SetRealm(testing.NewUserRealm(dave))
	catalog.Claim(cross(cur), k, proof, e0, dave1)
	check(strings.Contains(catalog.ClaimJSON(k), `"pending":true`), "dave pending")
	check(strings.Contains(catalog.ClaimJSON(k), `"bot":true`), "bot on")
	pending, to, readyAt := catalog.ClaimState(k)
	check(pending && to == dave && readyAt == t0+72*3600, "claim state")
	// Still not verified during the delay: no tips, no early finalize.
	fails("72 hours", func() { catalog.FinalizeClaim(cross(cur), k) })
	testing.IssueCoins(cat, chain.Coins{{"ugnot", 1_000_000}})
	testing.SetOriginSend(chain.Coins{{"ugnot", 1_000_000}})
	testing.SetRealm(testing.NewUserRealm(carol))
	fails("not verified", func() { catalog.Tip(cross(cur), tr) })
	testing.SetOriginSend(nil)

	// The admin cancels a pending claim; nobody else can. A rename cancels
	// one too (it was checked for the old name).
	testing.SetRealm(testing.NewUserRealm(alice))
	catalog.Claim(cross(cur), own, proof, e0, alice2)
	fails("admin only", func() { catalog.CancelClaim(cross(cur), own) })
	testing.SetRealm(testing.NewUserRealm(admin))
	catalog.CancelClaim(cross(cur), own)
	check(strings.Contains(catalog.ClaimJSON(own), `"pending":false`), "cancelled")
	testing.SetRealm(testing.NewUserRealm(alice))
	catalog.Claim(cross(cur), own, proof, e0, alice2)
	catalog.RegisterArtist(cross(cur), "Famous Star", "")
	check(strings.Contains(catalog.ClaimJSON(own), `"pending":false`), "rename cancels")
	catalog.Claim(cross(cur), own, proof, e0, alice2)

	skip(72*3600/5 + 1)
	// An old certificate has expired by now.
	testing.SetRealm(testing.NewUserRealm(dave))
	fails("expired", func() { catalog.Claim(cross(cur), k, proof, e0, dave1) })
	catalog.FinalizeClaim(cross(cur), k) // anyone can finalize
	a, _ := catalog.GetArtist(k)
	check(a.Owner == dave && a.Verified && catalog.ArtistVerified(k), "dave verified")
	check(strings.Contains(catalog.ClaimJSON(k), `"proof":"`+proof+`"`), "proof kept")
	fails("no pending", func() { catalog.FinalizeClaim(cross(cur), k) })
	testing.IssueCoins(cat, chain.Coins{{"ugnot", 1_000_000}})
	testing.SetOriginSend(chain.Coins{{"ugnot", 1_000_000}})
	testing.SetRealm(testing.NewUserRealm(carol))
	catalog.Tip(cross(cur), tr)
	testing.SetOriginSend(nil)
	check(catalog.TrackCount() == 1, "one track")
	tk, _ := catalog.GetTrack(tr)
	check(tk.Tips == 1_000_000, "dave tipped")

	// Verified profiles cannot be claimed again.
	testing.SetRealm(testing.NewUserRealm(bob))
	fails("already verified", func() { catalog.Claim(cross(cur), k, proof, e1, bob1late) })

	// Alice's claim counts; renaming then drops the badge.
	catalog.FinalizeClaim(cross(cur), own)
	check(catalog.ArtistVerified(own), "alice verified")
	testing.SetRealm(testing.NewUserRealm(alice))
	catalog.RegisterArtist(cross(cur), "Daft Punk", "")
	check(!catalog.ArtistVerified(own), "rename drops the badge")

	// A replaced robot key voids the claims it started: a stolen key is
	// undone in one call.
	catalog.Claim(cross(cur), own, proof, e1, alice2late)
	testing.SetRealm(testing.NewUserRealm(admin))
	catalog.SetBot(cross(cur), robotPub) // rotated
	check(strings.Contains(catalog.ClaimJSON(own), `"pending":false`), "rotation voids")
	skip(72*3600/5 + 1)
	fails("since replaced", func() { catalog.FinalizeClaim(cross(cur), own) })

	// Revoking the robot key stops every certificate at once.
	catalog.SetBot(cross(cur), "")
	check(strings.Contains(catalog.ClaimJSON(own), `"bot":false`), "bot off")
	testing.SetRealm(testing.NewUserRealm(alice))
	fails("paused", func() { catalog.Claim(cross(cur), own, proof, e1, alice2late) })

	// The admin undoes a wrong claim on an imported profile, not on a
	// self-registered one.
	testing.SetRealm(testing.NewUserRealm(admin))
	fails("imported profile", func() { catalog.ResetOwner(cross(cur), own) })
	catalog.AssignArtist(cross(cur), free, bob)
	catalog.ResetOwner(cross(cur), free)
	check(catalog.ArtistOwner(free) == "" && catalog.ArtistOf(bob) == 0, "reset")
	println("ok")
}

// Output:
// ok
