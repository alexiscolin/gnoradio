package catalog

import (
	"crypto/ed25519"
	"encoding/hex"
	"strings"
	"testing"

	"gno.land/p/nt/uassert/v0"
)

const (
	proofURL = "https://audius.co/nighttapes"
	// A real robot key and certificate (seed 0x07 * 32, signed with Node's crypto).
	robotPub = "ea4a6c63e29c520abef5507b132ec5f9954776aebebe7b92421eea691446d22c"
	daveCert = "135c37e7e92cb37d6ee10a1e8ef778ef802ac9d8570572b580c260869165b815356e8ecd79b5ff7e42f1dd7feb89add3ea256298045a1f7b816e3ead41bc0c08"
)

// good is the certificate the stand-in robot accepts: tests sign nothing, so
// verifySig is swapped for one that only checks it (TestRealCertificate covers
// the real signature over ClaimMessage).
var good = strings.Repeat("ab", 64)

// submit sends a certificate to Claim, with the stand-in robot set right before.
func submit(cur realm, artistID int, proof string, expires int64, sig string) {
	verifySig = func(_, _, sig []byte) bool { return hex.EncodeToString(sig) == good }
	Claim(cross(cur), artistID, proof, expires, sig)
}

// The certificate format and Ed25519 wiring, with a real signature.
func TestRealCertificate(t *testing.T) {
	pub, _ := hex.DecodeString(robotPub)
	sig, _ := hex.DecodeString(daveCert)
	msg := ClaimMessage(1, dave, proofURL, 1234569690)
	uassert.True(t, ed25519.Verify(pub, []byte(msg), sig))
	uassert.False(t, ed25519.Verify(pub, []byte(ClaimMessage(1, bob, proofURL, 1234569690)), sig))  // another wallet
	uassert.False(t, ed25519.Verify(pub, []byte(ClaimMessage(2, dave, proofURL, 1234569690)), sig)) // another artist
}

func TestVerifyFlow(cur realm, t *testing.T) {
	reset()
	testing.SetRealm(testing.NewUserRealm(boss))
	k := CreateArtist(cross(cur), OriginAudius, "Night Tapes", "", proofURL)
	tr := ImportTrack(cross(cur), k, "Drive", 1, "3:00", "", "", "audius:Dk3aQ", "", "", "", "https://audius.co/x", "Night Tapes")
	exp := now() + 600

	// No robot key yet; then only a valid, unexpired certificate for the caller.
	testing.SetRealm(testing.NewUserRealm(dave))
	uassert.AbortsContains(t, cur, "paused", func() { submit(cur, k, proofURL, exp, good) })
	testing.SetRealm(testing.NewUserRealm(boss))
	uassert.AbortsContains(t, cur, "32-byte", func() { SetBot(cross(cur), "abcd") })
	SetBot(cross(cur), robotPub)
	testing.SetRealm(testing.NewUserRealm(dave))
	uassert.AbortsContains(t, cur, "not valid", func() { submit(cur, k, proofURL, exp, strings.Repeat("cd", 64)) })
	uassert.AbortsContains(t, cur, "expired", func() { submit(cur, k, proofURL, now()-1, good) })
	uassert.AbortsContains(t, cur, "expired", func() { submit(cur, k, proofURL, now()+certLife+1, good) })
	uassert.AbortsContains(t, cur, "https link", func() { submit(cur, k, "http://x.y", exp, good) })

	submit(cur, k, proofURL, exp, good)
	uassert.True(t, strings.Contains(ClaimJSON(k), `"pending":true`))
	uassert.True(t, strings.Contains(ClaimJSON(k), `"bot":true`))

	// Still not verified during the delay: no tips, no early finalize.
	uassert.AbortsContains(t, cur, "72 hours", func() { FinalizeClaim(cross(cur), k) })
	testing.IssueCoins(realmAddr, ugnots(ugnot))
	testing.SetOriginSend(ugnots(ugnot))
	testing.SetRealm(testing.NewUserRealm(carol))
	uassert.AbortsContains(t, cur, "not verified", func() { Tip(cross(cur), tr) })
	testing.SetOriginSend(nil)

	testing.SkipHeights(claimDelay/5 + 1)
	FinalizeClaim(cross(cur), k) // anyone can finalize
	a := getArtist(k)
	uassert.Equal(t, dave, a.Owner)
	uassert.True(t, a.Verified)
	uassert.True(t, ArtistVerified(k))
	uassert.True(t, strings.Contains(ClaimJSON(k), `"proof":"`+proofURL+`"`))
	uassert.AbortsContains(t, cur, "no pending", func() { FinalizeClaim(cross(cur), k) })

	testing.SetOriginSend(ugnots(ugnot))
	Tip(cross(cur), tr)
	uassert.Equal(t, int64(ugnot), balance(dave))
	testing.SetOriginSend(nil)

	// Verified profiles cannot be claimed again.
	testing.SetRealm(testing.NewUserRealm(bob))
	uassert.AbortsContains(t, cur, "already verified", func() { submit(cur, k, proofURL, now()+600, good) })
}

func TestVerifyGuards(cur realm, t *testing.T) {
	reset()
	testing.SetRealm(testing.NewUserRealm(alice))
	own := RegisterArtist(cross(cur), "Alice", "")
	testing.SetRealm(testing.NewUserRealm(boss))
	free := CreateArtist(cross(cur), OriginCurated, "Komiku", "", "")
	SetBot(cross(cur), robotPub)

	// A self-registered profile can only be verified for its own wallet.
	testing.SetRealm(testing.NewUserRealm(bob))
	uassert.AbortsContains(t, cur, "another wallet", func() { submit(cur, own, proofURL, now()+600, good) })
	// A wallet that already has a profile cannot take a second one.
	testing.SetRealm(testing.NewUserRealm(alice))
	uassert.AbortsContains(t, cur, "already has an artist", func() { submit(cur, free, proofURL, now()+600, good) })
	submit(cur, own, proofURL, now()+600, good)

	// The admin can cancel a pending claim; nobody else can.
	uassert.AbortsContains(t, cur, "admin only", func() { CancelClaim(cross(cur), own) })
	testing.SetRealm(testing.NewUserRealm(boss))
	CancelClaim(cross(cur), own)
	testing.SkipHeights(claimDelay/5 + 1)
	uassert.AbortsContains(t, cur, "no pending", func() { FinalizeClaim(cross(cur), own) })

	// Revoking the robot key stops every certificate at once.
	SetBot(cross(cur), "")
	testing.SetRealm(testing.NewUserRealm(alice))
	uassert.AbortsContains(t, cur, "paused", func() { submit(cur, own, proofURL, now()+600, good) })

	// A stolen robot key is capped per day.
	testing.SetRealm(testing.NewUserRealm(boss))
	SetBot(cross(cur), robotPub)
	testing.SetRealm(testing.NewUserRealm(alice))
	botCount = maxBotPerDay
	botDay = now() / 86400
	uassert.AbortsContains(t, cur, "limit reached", func() { submit(cur, own, proofURL, now()+600, good) })

	// Resubmitting one's own pending claim does not use up the daily quota.
	botCount = 0
	submit(cur, own, proofURL, now()+600, good)
	submit(cur, own, proofURL, now()+600, good)
	uassert.Equal(t, 1, botCount)
	testing.SetRealm(testing.NewUserRealm(boss))
	CancelClaim(cross(cur), own)
	testing.SetRealm(testing.NewUserRealm(alice))

	// A rename during the wait cancels the claim (it was checked for the old name).
	botCount = 0
	submit(cur, own, proofURL, now()+600, good)
	RegisterArtist(cross(cur), "Famous Star", "")
	uassert.True(t, strings.Contains(ClaimJSON(own), `"pending":false`))

	submit(cur, own, proofURL, now()+600, good)
	testing.SkipHeights(claimDelay/5 + 1)
	FinalizeClaim(cross(cur), own)
	// Renaming drops the badge, so a verified name cannot be swapped for another.
	uassert.True(t, ArtistVerified(own))
	testing.SetRealm(testing.NewUserRealm(alice))
	RegisterArtist(cross(cur), "Daft Punk", "")
	uassert.False(t, ArtistVerified(own))

	// The admin can undo a wrong claim on an imported profile, not on a self-registered one.
	testing.SetRealm(testing.NewUserRealm(boss))
	uassert.AbortsContains(t, cur, "imported profile", func() { ResetOwner(cross(cur), own) })
	AssignArtist(cross(cur), free, dave)
	ResetOwner(cross(cur), free)
	uassert.Equal(t, address(""), ArtistOwner(free))
	uassert.Equal(t, 0, ArtistOf(dave))
}
