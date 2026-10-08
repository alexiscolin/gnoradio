// PKGPATH: gno.land/r/test/rehearsal
package rehearsal

// Release rehearsal (ARCHITECTURE-v1 P6), with the filetest's clock standing
// in for the 72 hours a devnet cannot skip: release 1 holds data, a guardian
// apart from the owner cancels a first release 2, pauses and the owner
// resumes, a funder withdraws while paused, then release 2 is proposed
// again, every role says Ready, and the whole set takes over after the
// delay, never before. Every byte of data is the same across the takeover,
// the old rules refuse writes, and the site and the old readers still work.

import (
	"chain"
	"chain/banker"
	"strconv"
	"strings"
	"testing"

	"gno.land/p/gnoradio/store/v0"
	"gno.land/p/nt/testutils/v0"
	catalog "gno.land/r/gnoradio/catalog/v1"
	"gno.land/r/gnoradio/data"
	home "gno.land/r/gnoradio/home/v1"
	radio "gno.land/r/gnoradio/radio/v1"
	tickets "gno.land/r/gnoradio/tickets/v1"
)

var (
	owner = chain.PackageAddress("gno.land/r/gnoradio/data/dev")       // data's owner and guardian under gno test
	admin = chain.PackageAddress("gno.land/r/gnoradio/catalog/v1/dev") // the catalog admin under gno test
	guard = testutils.TestAddress("guard")
	alice = testutils.TestAddress("alice")
	bob   = testutils.TestAddress("bob")
	roles = []string{"catalog", "radio", "tickets", "home"}
	colls = []string{
		"catalog/artists", "catalog/alists", "catalog/owners", "catalog/names", "catalog/tracks", "catalog/genres",
		"catalog/albums", "catalog/playlists", "catalog/users", "catalog/likes", "catalog/tipped", "catalog/reports",
		"catalog/removed", "catalog/hosts", "catalog/meta", "catalog/tops", "catalog/activity", "catalog/config",
		"catalog/supporters", "catalog/monthly", "catalog/promo", "catalog/budgets", "catalog/walletday",
		"catalog/claims", "catalog/proofs",
		"radio/stations", "radio/rot", "radio/homes", "radio/meta", "radio/curators", "radio/tops", "radio/dropped",
		"radio/notes", "radio/muted", "radio/strikes", "radio/sponsor", "radio/activity", "radio/config",
		"tickets/byartist", "tickets/upcoming", "tickets/ahead", "tickets/owned", "tickets/buyers",
		"tickets/attended", "tickets/meta", "tickets/config", "home/config",
	}
)

func v2(role string) string { return "gno.land/r/gnoradio/" + role + "/v2" }

func check(ok bool, what string) {
	if !ok {
		println("FAIL:", what)
	}
}

func fails(want string, fn func()) {
	r := revive(fn)
	s, _ := r.(string)
	if !strings.Contains(s, want) {
		println("FAIL: want abort", want, "got", s)
	}
}

// snapshot is every key and value of every collection, in order.
func snapshot() string {
	var b strings.Builder
	for _, c := range colls {
		b.WriteString("#" + c + "\n")
		for off := 0; off < data.Size(c); off += 100 {
			b.WriteString(data.PageAt(c, off, 100, false))
		}
	}
	return b.String()
}

func ugnot(n int64) chain.Coins { return chain.Coins{{Denom: "ugnot", Amount: n}} }

func balance(a address) int64 { return banker.NewReadonlyBanker().GetCoins(a).AmountOf("ugnot") }

func propose(cur realm) {
	testing.SetRealm(testing.NewUserRealm(owner))
	for _, r := range roles {
		data.Propose(cross(cur), r, v2(r))
	}
	for _, r := range roles {
		testing.SetRealm(testing.NewCodeRealm(v2(r)))
		data.Ready(cross(cur))
	}
}

func main(cur realm) {
	// Release 1 holds data: an artist, a track, a like, a budget, a concert.
	testing.SetRealm(testing.NewUserRealm(alice))
	aid := catalog.RegisterArtist(cross(cur), "Alice", "")
	id := radio.PublishTrack(cross(cur), "Song", 2, "3:30", "cc by", "none", "", "ipfs://bafybeigdyrzt5sfp7udm7hu76uh7y26nf3efuylqabf3oclgtqy55fbzdi", "", "", "", "", "yes")
	testing.SetRealm(testing.NewUserRealm(admin))
	catalog.Verify(cross(cur), aid, true)
	testing.IssueCoins(chain.PackageAddress("gno.land/r/gnoradio/catalog/v1"), ugnot(1_000_000))
	testing.SetOriginSend(ugnot(1_000_000))
	testing.SetRealm(testing.NewUserRealm(alice))
	catalog.FundPromo(cross(cur))
	testing.SetOriginSend(nil)
	tickets.CreateEvent(cross(cur), "Show", "Venue", "", "2030-01-01 20:00", "0", 10)
	testing.SetRealm(testing.NewUserRealm(bob))
	catalog.Like(cross(cur), id)

	// The owner's guardian role goes to a separate key, in two steps.
	testing.SetRealm(testing.NewUserRealm(owner))
	data.GuardianOffer(cross(cur), guard)
	testing.SetRealm(testing.NewUserRealm(guard))
	data.GuardianAccept(cross(cur))
	check(data.Guardian() == guard, "guardian moved")

	// A first release 2: proposed, Ready, then cancelled by the guardian.
	propose(cur)
	check(strings.Contains(data.Writers(), `"proposed":"`+v2("catalog")+`","ready":true`), "release 2 ready")
	testing.SetRealm(testing.NewUserRealm(guard))
	fails("owner", func() { data.Propose(cross(cur), "catalog", "gno.land/r/gnoradio/catalog/v3") })
	data.Cancel(cross(cur))
	check(!strings.Contains(data.Writers(), v2("catalog")), "cancelled")
	testing.SkipHeights(data.DELAY/5 + 1)
	check(data.Writer("catalog") == "gno.land/r/gnoradio/catalog/v1", "release 1 stays after a cancel")

	// Pause: the guardian pauses, cannot resume; writes stop, the funder
	// still withdraws; the owner resumes.
	testing.SetRealm(testing.NewUserRealm(guard))
	data.Pause(cross(cur), "", true)
	fails("owner", func() { data.Pause(cross(cur), "", false) })
	testing.SetRealm(testing.NewUserRealm(bob))
	fails("catalog is paused", func() { catalog.Unlike(cross(cur), id) })
	before := balance(alice)
	testing.SetRealm(testing.NewUserRealm(alice))
	data.VaultWithdraw(cross(cur), "catalog/"+store.Pad(aid))
	check(balance(alice)-before == 1_000_000, "funder withdrew while paused")
	testing.SetRealm(testing.NewUserRealm(owner))
	data.Pause(cross(cur), "", false)

	// Release 2 again: v1 keeps writing until the delay is over.
	propose(cur)
	testing.SkipHeights(data.DELAY/5 - 10)
	check(data.Writer("catalog") == "gno.land/r/gnoradio/catalog/v1", "no takeover before the delay")
	testing.SetRealm(testing.NewUserRealm(bob))
	catalog.Unlike(cross(cur), id)
	catalog.Like(cross(cur), id)
	snap := snapshot()
	check(strings.Contains(snap, "Alice") && strings.Contains(snap, "#home/config"), "snapshot holds the data")

	// The takeover: every role at once, no byte of data changed.
	testing.SkipHeights(11)
	for _, r := range roles {
		check(data.Writer(r) == v2(r), r+" taken over")
	}
	testing.SetRealm(testing.NewUserRealm(owner))
	data.Pause(cross(cur), "home", true) // any owner write applies the release
	data.Pause(cross(cur), "home", false)
	check(strings.Contains(data.Writers(), `"catalog":{"writer":"`+v2("catalog")+`","paused":false,"proposed":""`), "release applied")
	check(snapshot() == snap, "data unchanged by the takeover")

	// The old rules refuse writes; their readers, the site and the vault
	// still answer, and the old realms still count as GnoRadio.
	testing.SetRealm(testing.NewUserRealm(bob))
	fails("only "+v2("catalog")+" writes catalog", func() { catalog.Unlike(cross(cur), id) })
	testing.SetRealm(testing.NewUserRealm(alice))
	fails("only "+v2("tickets")+" writes tickets", func() {
		tickets.CreateEvent(cross(cur), "Show 2", "Venue", "", "2030-02-01 20:00", "0", 10)
	})
	check(strings.Contains(catalog.TrackJSON(id), `"likes":1`), "the like is kept")
	check(strings.Contains(catalog.Info(), `"current":"`+v2("catalog")+`"`), "catalog names its successor")
	check(strings.Contains(home.Render("track/"+strconv.Itoa(id)), "Song"), "home still renders")
	check(data.IsGnoRadio(chain.PackageAddress("gno.land/r/gnoradio/catalog/v1")), "a past writer stays GnoRadio")

	// The new rules write the same collections.
	testing.SetRealm(testing.NewCodeRealm(v2("catalog")))
	data.Set(cross(cur), "catalog/config", "rehearsal", "v2")
	v, _ := data.Get("catalog/config", "rehearsal")
	check(v == "v2", "v2 writes")
	println("ok")
}

// Output:
// ok
