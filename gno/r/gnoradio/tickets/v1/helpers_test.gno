package tickets

import (
	"chain"
	"chain/banker"
	"strconv"
	"testing"
	"time"

	"gno.land/p/nt/testutils/v0"
	catalog "gno.land/r/gnoradio/catalog/v1"
)

// The data realm keeps what every test wrote (gno test runs the tests of a
// package on one store), so each test makes its own wallets and artists with
// who and artist, and reads ids from the calls that create them.

var (
	boss      = chain.PackageAddress("gno.land/r/gnoradio/tickets/v1/dev") // the tickets admin under gno test
	catBoss   = chain.PackageAddress("gno.land/r/gnoradio/catalog/v1/dev") // the catalog admin
	dataOwner = chain.PackageAddress("gno.land/r/gnoradio/data/dev")       // data's owner and guardian
	realmAddr = chain.PackageAddress("gno.land/r/gnoradio/tickets/v1")
	seq       int
)

// who returns a wallet no other test used.
func who(tag string) address {
	seq++
	return testutils.TestAddress(tag + strconv.Itoa(seq))
}

// artist registers a new artist profile for a new wallet; name gets a
// suffix no skeleton folds, so names never collide.
func artist(cur realm, name string) (address, int) {
	const abc = "abcdefghjkpqstwxyz" // no u or v: uu and vv fold to w
	w := who("artist")
	s := ""
	for n := seq; n > 0; n /= len(abc) {
		s = string(abc[n%len(abc)]) + s
	}
	testing.SetRealm(testing.NewUserRealm(w))
	return w, catalog.RegisterArtist(cross(cur), name+" "+s, "")
}

// verify marks an artist as verified, as FinalizeClaim would.
func verify(cur realm, artistID int, on bool) {
	testing.SetRealm(testing.NewUserRealm(catBoss))
	catalog.Verify(cross(cur), artistID, on)
}

// hideArtist hides or restores an artist profile, as catalog moderators do.
func hideArtist(cur realm, artistID int, hidden bool) {
	testing.SetRealm(testing.NewUserRealm(catBoss))
	catalog.HideArtist(cross(cur), artistID, hidden, "test reason")
}

func ugnots(n int64) chain.Coins { return chain.Coins{{Denom: denom, Amount: n}} }

func balance(addr address) int64 { return banker.NewReadonlyBanker().GetCoins(addr).AmountOf(denom) }

func inHours(h int) string {
	return time.Now().Add(time.Duration(h) * time.Hour).UTC().Format("2006-01-02 15:04")
}

// fee sets the service fee as the tickets admin.
func fee(cur realm, ugnot int64) {
	testing.SetRealm(testing.NewUserRealm(boss))
	SetServiceFee(cross(cur), ugnot)
}
