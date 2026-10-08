package catalog

import (
	"chain"
	"chain/banker"
	"testing"

	"gno.land/p/gnoradio/text/v0"
	"gno.land/p/nt/testutils/v0"
	"gno.land/r/gnoradio/data"
)

// The data realm keeps what every test wrote (gno test runs the tests of a
// package on one store), so each test makes its own wallets and names with
// who and name, and reads ids from the calls that create them. Coins do
// reset between tests: syncVault puts the vault's coins back.

var (
	boss      = chain.PackageAddress("gno.land/r/gnoradio/catalog/v1/dev") // the admin under gno test
	dataOwner = chain.PackageAddress("gno.land/r/gnoradio/data/dev")       // data's owner and guardian under gno test
	realmAddr = chain.PackageAddress("gno.land/r/gnoradio/catalog/v1")
	dataAddr  = chain.PackageAddress(dataPath)
	seq       int
)

const (
	cid  = "bafybeigdyrzt5sfp7udm7hu76uh7y26nf3efuylqabf3oclgtqy55fbzdi"
	ipfs = "ipfs://" + cid
	sha  = "9f86d081884c7d659a2feaa0c55ad015a3bf4f1b2b0b822cd15d6c15b0f00a08"
	ia   = "https://archive.org/download/komiku-dreams/01-Dreams.mp3"
)

// who returns a wallet no other test used.
func who(tag string) address {
	seq++
	return testutils.TestAddress(tag + text.Itoa(seq))
}

// name returns an artist name no other test reserved: letters that no
// skeleton folds (no i, l, m, n, o, r).
func name(base string) string {
	const abc = "abcdefghjkpqstwxyz" // no u or v: uu and vv fold to w
	seq++
	s := ""
	for n := seq; n > 0; n /= len(abc) {
		s = string(abc[n%len(abc)]) + s
	}
	return base + " " + s
}

func ugnots(n int64) chain.Coins { return chain.Coins{{Denom: denom, Amount: n}} }

func balance(addr address) int64 { return banker.NewReadonlyBanker().GetCoins(addr).AmountOf(denom) }

// syncVault gives the data realm back the coins its vault accounts for.
func syncVault() {
	if d := data.VaultTotal() - balance(dataAddr); d > 0 {
		testing.IssueCoins(dataAddr, ugnots(d))
	}
}

// artist registers a new artist for a new wallet.
func artist(cur realm, tag string) (address, int) {
	w := who(tag)
	testing.SetRealm(testing.NewUserRealm(w))
	return w, RegisterArtist(cross(cur), name(tag), "")
}

// publish publishes a track as the artist's wallet w.
func publish(cur realm, w address, title string) int {
	testing.SetRealm(testing.NewUserRealm(w))
	return PublishTrack(cross(cur), title, 2, "3:30", "cc by", "none", "", ipfs, "", "", "", "", "yes")
}

// PublishTrack, ImportTrack and EditTrack stand for radio/v1's (which this
// package cannot import): the radio realm passes on who signed, here the
// realm the test set before the cross call.
func PublishTrack(cur realm, title string, genre int, duration, license, cmo, credits, audio, audioSHA, cover, coverSHA, splits, rights string) int {
	by := cur.Previous().Address()
	testing.SetRealm(testing.NewCodeRealm(radioPath()))
	return PublishFor(cross(cur), by, title, genre, duration, license, cmo, credits, audio, audioSHA, cover, coverSHA, splits, rights)
}

func ImportTrack(cur realm, artistID int, title string, genre int, duration, license, credits, audio, audioSHA, cover, coverSHA, sourceURL, attribution string) int {
	by := cur.Previous().Address()
	testing.SetRealm(testing.NewCodeRealm(radioPath()))
	return ImportFor(cross(cur), by, artistID, title, genre, duration, license, credits, audio, audioSHA, cover, coverSHA, sourceURL, attribution)
}

func EditTrack(cur realm, trackID int, title string, genre int, duration, credits, audio, audioSHA, cover, coverSHA string) {
	by := cur.Previous().Address()
	testing.SetRealm(testing.NewCodeRealm(radioPath()))
	EditFor(cross(cur), by, trackID, title, genre, duration, credits, audio, audioSHA, cover, coverSHA)
}

// verified marks an artist as verified, as FinalizeClaim would (the cert
// filetest covers the flow).
func verified(cur realm, artistID int) {
	testing.SetRealm(testing.NewUserRealm(boss))
	Verify(cross(cur), artistID, true)
}

// promoTrack publishes a verified track of a new artist with a 30%
// collaborator and returns the artist's wallet, the collaborator, the
// artist id and the track id.
func promoTrack(cur realm) (owner, collab address, aid, id int) {
	owner, aid = artist(cur, "promo")
	collab = who("collab")
	testing.SetRealm(testing.NewUserRealm(owner))
	id = PublishTrack(cross(cur), "Promo Song", 2, "1:40", "CC-BY", "none", "", ipfs, "", "", "", collab.String()+":30", "yes")
	verified(cur, aid)
	return owner, collab, aid, id
}

// radioPath is the realm the data realm names as radio writer now.
func radioPath() string { return data.Writer("radio") }

// radioTip calls RadioTip as the radio realm after it forwarded total.
func radioTip(cur realm, id, supportPct int, tipper, pk, ref address, total int64) (int64, int64) {
	testing.IssueCoins(realmAddr, ugnots(total))
	testing.SetRealm(testing.NewCodeRealm(radioPath()))
	return RadioTip(cross(cur), id, supportPct, tipper, pk, ref, total)
}

// pause pauses or resumes the catalog role, as the data realm's owner.
func pause(cur realm, on bool) {
	testing.SetRealm(testing.NewUserRealm(dataOwner))
	data.Pause(cross(cur), "catalog", on)
}

// seed writes a key of the catalog's collections as this realm does.
func seed(cur realm, c, k, v string) {
	testing.SetRealm(testing.NewCodeRealm(self))
	data.Set(cross(cur), c, k, v)
}
