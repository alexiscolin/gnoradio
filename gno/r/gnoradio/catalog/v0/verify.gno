package catalog

import (
	"chain/runtime"
	"crypto/ed25519"
	"encoding/hex"
	"strconv"

	"gno.land/p/gnoradio/text/v0"
	"gno.land/p/nt/avl/v0"
)

// Automatic verification, paid by the artist. The artist puts a proof line in
// a place only they control (their Audius bio, or /.well-known/gnoradio.txt on their own website); the
// GnoRadio robot reads it and, off-chain and for free, signs a certificate
// (Ed25519, ClaimMessage) valid for a short while. The artist submits it with
// Claim from their own wallet; after claimDelay anyone can finalize: the
// profile goes to that wallet and turns Verified, which opens tips and paid
// tickets. The robot key signs nothing else; the admin can revoke it, cancel
// a pending claim and undo a wrong one. Changing or revoking the key voids
// every claim it started that is still pending, so a stolen key is undone in
// one call; there is no daily cap that one person could use up for everyone.

const (
	claimDelay = 72 * 3600 // seconds a claim stays public before it counts
	certLife   = 2 * 3600  // longest validity of a robot certificate, seconds
)

type claim struct {
	To    address
	Proof string
	At    int64
	Gen   int // botGen when the claim was made
}

var (
	botKey []byte   // Ed25519 public key of the verification robot
	botGen int      // bumped by SetBot: pending claims of an older key do not finalize
	claims avl.Tree // padded artist id -> *claim (pending)
	proofs avl.Tree // padded artist id -> proof URL of the last finalized claim

	// verifySig checks certificates; tests stand in for the robot with it.
	verifySig = ed25519.Verify
)

// ProofLine is what the artist publishes on their page to claim artistID for wallet to.
func ProofLine(artistID int, to address) string {
	return "gnoradio:" + itoa(artistID) + ":" + to.String()
}

// ClaimMessage is what the robot signs: the chain, the profile, the wallet,
// where the proof was found and until when the certificate holds.
func ClaimMessage(artistID int, to address, proof string, expires int64) string {
	return "gnoradio-claim|" + runtime.ChainID() + "|" + itoa(artistID) + "|" + to.String() + "|" + proof + "|" + itoa64(expires)
}

// SetBot sets the robot's Ed25519 public key, hex ("" disables it). Every
// pending claim started with the previous key is voided: its artist claims
// again with a fresh certificate. Admin only.
func SetBot(cur realm, pubKeyHex string) {
	onlyAdmin(cur)
	key, err := hex.DecodeString(pubKeyHex)
	if err != nil || (len(key) != 0 && len(key) != 32) {
		panic("catalog: the robot key is a 32-byte Ed25519 public key in hex")
	}
	botKey = key
	botGen++
	emitEvent("BotSet", "key", pubKeyHex)
}

// Claim starts the verification of artistID for the caller with the robot's
// certificate (ClaimMessage signed, hex). It replaces any pending claim for the
// artist and restarts the delay. The artist pays its gas.
func Claim(cur realm, artistID int, proof string, expires int64, sigHex string) {
	caller := userCaller(cur)
	noPayment()
	notFrozen()
	ts := now()
	if len(botKey) == 0 {
		panic("catalog: verification is paused")
	}
	if expires < ts || expires > ts+certLife {
		panic("catalog: this certificate has expired, check your page again")
	}
	if !validHTTPS(proof) {
		panic("catalog: proof must be an https link")
	}
	sig, err := hex.DecodeString(sigHex)
	if err != nil || len(sig) != 64 || !verifySig(botKey, []byte(ClaimMessage(artistID, caller, proof, expires)), sig) {
		panic("catalog: this certificate is not valid for your wallet")
	}
	a := mustArtist(artistID)
	mustClaimable(a, caller)
	claims.Set(text.Key(artistID), &claim{To: caller, Proof: proof, At: ts, Gen: botGen})
	emitEvent("ClaimProposed", "artist", itoa(artistID), "to", caller.String(), "proof", proof)
}

// FinalizeClaim applies a pending claim once claimDelay has passed. Anyone
// can call it, usually the artist from the app.
func FinalizeClaim(cur realm, artistID int) {
	noPayment()
	notFrozen()
	v := claims.Get(text.Key(artistID))
	if v == nil {
		panic("catalog: no pending verification for this artist")
	}
	c := v.(*claim)
	if c.Gen != botGen {
		panic("catalog: this check was signed by a robot key since replaced, check your page again")
	}
	if now() < c.At+claimDelay {
		panic("catalog: verification completes 72 hours after the check")
	}
	a := mustArtist(artistID)
	mustClaimable(a, c.To)
	claims.Remove(text.Key(artistID))
	if a.Owner == "" {
		a.Owner = c.To
		byOwner.Set(c.To.String(), itoa(a.ID))
		recordActivity("claim", c.To, 0, a.ID, 0)
	}
	a.Verified = true
	putArtist(a)
	proofs.Set(text.Key(artistID), c.Proof)
	emitEvent("ArtistClaimed", "id", itoa(a.ID), "owner", c.To.String(), "proof", c.Proof)
}

// CancelClaim drops a pending claim (e.g. the proof page was hijacked). Admin only.
func CancelClaim(cur realm, artistID int) {
	onlyAdmin(cur)
	if _, ok := claims.Remove(text.Key(artistID)); !ok {
		panic("catalog: no pending verification for this artist")
	}
	emitEvent("ClaimCancelled", "artist", itoa(artistID))
}

// ResetOwner undoes a wrong claim on an imported profile (e.g. a hijacked
// proof page found too late): the profile is unclaimed again. Self-registered
// profiles keep their owner. Admin only.
func ResetOwner(cur realm, artistID int) {
	onlyAdmin(cur)
	a := mustArtist(artistID)
	if a.Kind == OriginArtist || a.Owner == "" {
		panic("catalog: only a claimed imported profile can be reset")
	}
	byOwner.Remove(a.Owner.String())
	a.Owner, a.Verified = "", false
	putArtist(a)
	proofs.Remove(text.Key(artistID))
	claims.Remove(text.Key(artistID))
	emitEvent("OwnerReset", "artist", itoa(artistID))
}

// mustClaimable: an unowned profile goes to a wallet without a profile; an
// owned one can only be verified for its own wallet.
func mustClaimable(a *Artist, to address) {
	if a.Hidden {
		panic("catalog: this artist is hidden")
	}
	if a.Verified {
		panic("catalog: this artist is already verified")
	}
	if a.Owner != "" {
		if a.Owner != to {
			panic("catalog: this profile belongs to another wallet")
		}
		return
	}
	if !to.IsValid() || artistOf(to) != 0 {
		panic("catalog: this wallet is invalid or already has an artist profile")
	}
}

// ArtistVerified reports whether an artist proved who they are (tips and
// paid tickets need it).
func ArtistVerified(artistID int) bool { return artistField(artistID, aVerified) == "1" }

// ClaimJSON is the verification state of an artist for the app:
// {"verified":b,"proof":"…","pending":b,"to":"…","pendingProof":"…","readyAt":n,"bot":"…"}.
func ClaimJSON(artistID int) string {
	p, _ := proofs.Get(text.Key(artistID)).(string)
	out := `{"verified":` + strconv.FormatBool(ArtistVerified(artistID)) + `,"proof":"` + p + `"`
	if c, _ := claims.Get(text.Key(artistID)).(*claim); c != nil && c.Gen == botGen {
		out += `,"pending":true,"to":"` + c.To.String() + `","pendingProof":"` + c.Proof + `","readyAt":` + itoa64(c.At+claimDelay)
	} else {
		out += `,"pending":false`
	}
	return out + `,"bot":` + strconv.FormatBool(len(botKey) != 0) + `}`
}
