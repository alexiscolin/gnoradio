package data

import (
	"chain"
	"strings"
	"testing"

	"gno.land/p/gnoradio/store/v0"
	bptree "gno.land/p/nt/bptree/v0"
	"gno.land/p/nt/testutils/v0"
	"gno.land/p/nt/uassert/v0"
)

var (
	dev      = chain.PackageAddress("gno.land/r/gnoradio/data/dev") // owner and guardian under gno test
	alice    = testutils.TestAddress("alice")
	bob      = testutils.TestAddress("bob")
	cat1     = "gno.land/r/gnoradio/catalog/v1"
	cat2     = "gno.land/r/gnoradio/catalog/v2"
	radio1   = "gno.land/r/gnoradio/radio/v1"
	radio2   = "gno.land/r/gnoradio/radio/v2"
	evil     = "gno.land/r/evil/x"
	day      = int64(daySecs)
	blocksIn = func(secs int64) int64 { return secs/5 + 1 } // test blocks are 5 s apart
)

// reset starts every test from a fresh deployment.
func reset() {
	paused, proposed, ready, at = [4]bool{}, [4]string{}, [4]bool{}, 0
	colls, past, nColls = map[string]*bptree.BPTree{}, bptree.NewBPTree32(), [4]int{}
	vault, vaultTotal = bptree.NewBPTree32(), 0
	nextGuardian, guardianAt = "", 0
	frozen, frozeAt = 0, 0
	start(dev)
}

func TestInit(t *testing.T) {
	uassert.Equal(t, "gno.land/r/gnoradio/data", self)
	uassert.Equal(t, dev, Owner())
	uassert.Equal(t, dev, Guardian())
	uassert.Equal(t, cat1, Writer("catalog"))
	uassert.Equal(t, "gno.land/r/gnoradio/home/v1", Writer("home"))
}

func TestOnlyWriterWritesItsRole(cur realm, t *testing.T) {
	reset()
	testing.SetRealm(testing.NewCodeRealm(cat1))
	Make(cross(cur), "catalog/meta")
	Set(cross(cur), "catalog/meta", "k", "v")
	v, _ := Get("catalog/meta", "k")
	uassert.Equal(t, "v", v)

	testing.SetRealm(testing.NewCodeRealm(evil))
	uassert.AbortsContains(t, cur, "only "+cat1, func() { Set(cross(cur), "catalog/meta", "k", "x") })
	uassert.AbortsContains(t, cur, "only "+cat1, func() { Make(cross(cur), "catalog/other") })
	testing.SetRealm(testing.NewUserRealm(dev))
	uassert.AbortsContains(t, cur, "only "+cat1, func() { Remove(cross(cur), "catalog/meta", "k") })
	testing.SetRealm(testing.NewUserRealm(alice))
	uassert.AbortsContains(t, cur, "only "+cat1, func() { Batch(cross(cur), store.Ops{}.Set("catalog/meta", "k", "x")) })
	// the catalog writer cannot write another role's collections, in a
	// batch either (on chain the panic reverts the ops before it)
	testing.SetRealm(testing.NewCodeRealm(cat1))
	uassert.AbortsContains(t, cur, "only "+radio1, func() { Make(cross(cur), "radio/x") })
	ops := store.Ops{}.Set("catalog/meta", "k", "y").Set("radio/x", "k", "v")
	uassert.AbortsContains(t, cur, "only "+radio1, func() { Batch(cross(cur), ops) })
	uassert.AbortsContains(t, cur, "no role", func() { Set(cross(cur), "nope/x", "k", "v") })
}

func TestReleaseTakesOverAfterDelay(cur realm, t *testing.T) {
	reset()
	testing.SetRealm(testing.NewCodeRealm(cat1))
	Make(cross(cur), "catalog/meta")
	testing.SetRealm(testing.NewUserRealm(alice))
	uassert.AbortsContains(t, cur, "owner only", func() { Propose(cross(cur), "catalog", cat2) })
	testing.SetRealm(testing.NewUserRealm(dev))
	Propose(cross(cur), "catalog", cat2)
	Propose(cross(cur), "radio", radio2)
	uassert.True(t, IsGnoRadio(chain.PackageAddress(cat2)))

	// only a proposed realm says Ready, once; no clock until all did
	testing.SetRealm(testing.NewCodeRealm(evil))
	uassert.AbortsContains(t, cur, "only a proposed realm", func() { Ready(cross(cur)) })
	testing.SetRealm(testing.NewCodeRealm(cat2))
	Ready(cross(cur))
	uassert.AbortsContains(t, cur, "only a proposed realm", func() { Ready(cross(cur)) })
	uassert.Equal(t, int64(0), at)
	testing.SetRealm(testing.NewCodeRealm(radio2))
	Ready(cross(cur))
	uassert.Equal(t, now()+DELAY, at)

	// any new proposal restarts the clock
	testing.SetRealm(testing.NewUserRealm(dev))
	Propose(cross(cur), "home", "gno.land/r/gnoradio/home/v2")
	uassert.Equal(t, int64(0), at)
	testing.SetRealm(testing.NewCodeRealm("gno.land/r/gnoradio/home/v2"))
	Ready(cross(cur))
	uassert.Equal(t, now()+DELAY, at)

	// before the delay: the old writer writes, the new one does not
	testing.SkipHeights(blocksIn(DELAY) - 2)
	uassert.Equal(t, cat1, Writer("catalog"))
	testing.SetRealm(testing.NewCodeRealm(cat2))
	uassert.AbortsContains(t, cur, "only "+cat1, func() { Set(cross(cur), "catalog/meta", "k", "early") })
	testing.SetRealm(testing.NewCodeRealm(cat1))
	Set(cross(cur), "catalog/meta", "k", "v1")

	// after it: the whole set at once, data unchanged
	testing.SkipHeights(2)
	uassert.Equal(t, cat2, Writer("catalog"))
	uassert.Equal(t, radio2, Writer("radio"))
	uassert.True(t, strings.Contains(Writers(), `"catalog":{"writer":"`+cat2+`","paused":false,"proposed":"","ready":false}`))
	testing.SetRealm(testing.NewCodeRealm(cat1))
	uassert.AbortsContains(t, cur, "only "+cat2, func() { Set(cross(cur), "catalog/meta", "k", "old") })
	testing.SetRealm(testing.NewCodeRealm(cat2))
	v, _ := Get("catalog/meta", "k")
	uassert.Equal(t, "v1", v)
	Set(cross(cur), "catalog/meta", "k", "v2")
	uassert.Equal(t, int64(0), at)
	uassert.True(t, IsGnoRadio(chain.PackageAddress(cat1))) // a past writer stays GnoRadio
}

func TestProposeChecksPath(cur realm, t *testing.T) {
	reset()
	testing.SetRealm(testing.NewUserRealm(dev))
	for _, p := range []string{
		"gno.land/r/gnoradio/data", "gno.land/r/gnoradio/tickets/nft", cat1, // itself, the NFT realm, the writer
		"gno.land/p/gnoradio/catalog/v2", "gno.land/e/x/run", "gno.land/r/x//y", "gno.land/r/x/../y",
		"gno.land/r/x/./y", "gno.land/r/x/", "gno.land/r/X", "gno.land/r/x y", "gno.land/r/" + strings.Repeat("x", 90),
	} {
		uassert.AbortsContains(t, cur, "data: ", func() { Propose(cross(cur), "catalog", p) })
	}
	uassert.AbortsContains(t, cur, "no role", func() { Propose(cross(cur), "nft", cat2) })
	Propose(cross(cur), "catalog", "gno.land/r/nym-x_1/gnoradio/catalog/v2.1")
}

func TestPauseResumeRenounce(cur realm, t *testing.T) {
	reset()
	testing.SetRealm(testing.NewCodeRealm(cat1))
	Make(cross(cur), "catalog/meta")
	testing.SetRealm(testing.NewUserRealm(alice))
	uassert.AbortsContains(t, cur, "owner only", func() { Pause(cross(cur), "", true) })
	testing.SetRealm(testing.NewUserRealm(dev))
	Pause(cross(cur), "catalog", true)
	testing.SetRealm(testing.NewCodeRealm(cat1))
	uassert.AbortsContains(t, cur, "catalog is paused", func() { Set(cross(cur), "catalog/meta", "k", "x") })
	testing.SetRealm(testing.NewCodeRealm(radio1))
	Make(cross(cur), "radio/x") // other roles go on

	// a pause keeps the pending release; Renounce waits for a resume
	testing.SetRealm(testing.NewUserRealm(dev))
	Propose(cross(cur), "radio", radio2)
	uassert.AbortsContains(t, cur, "resume every role first", func() { Renounce(cross(cur)) })
	Pause(cross(cur), "", false)
	uassert.Equal(t, radio2, proposed[1])
	testing.SetRealm(testing.NewCodeRealm(cat1))
	Set(cross(cur), "catalog/meta", "k", "x")

	// Renounce drops the release and ends every owner and guardian power
	testing.SetRealm(testing.NewUserRealm(dev))
	Renounce(cross(cur))
	uassert.Equal(t, "", proposed[1])
	uassert.Equal(t, address(""), Owner())
	uassert.AbortsContains(t, cur, "owner only", func() { Pause(cross(cur), "", true) }) // dev is still the guardian
	uassert.AbortsContains(t, cur, "owner only", func() { Propose(cross(cur), "catalog", cat2) })
	uassert.AbortsContains(t, cur, "no release pending", func() { Cancel(cross(cur)) })
	testing.SetRealm(testing.NewCodeRealm(cat1))
	Set(cross(cur), "catalog/meta", "k", "y")
}

func TestOwnerTwoStep(cur realm, t *testing.T) {
	reset()
	testing.SetRealm(testing.NewUserRealm(dev))
	Offer(cross(cur), alice)
	testing.SetRealm(testing.NewUserRealm(bob))
	uassert.AbortsContains(t, cur, "nothing offered to you", func() { Accept(cross(cur)) })
	testing.SetRealm(testing.NewUserRealm(dev))
	Offer(cross(cur), dev) // cancels
	testing.SetRealm(testing.NewUserRealm(alice))
	uassert.AbortsContains(t, cur, "nothing offered to you", func() { Accept(cross(cur)) })
	testing.SetRealm(testing.NewUserRealm(dev))
	Offer(cross(cur), alice)
	uassert.Equal(t, dev, Owner()) // nothing changes before Accept
	testing.SetRealm(testing.NewUserRealm(alice))
	Accept(cross(cur))
	uassert.Equal(t, alice, Owner())
	testing.SetRealm(testing.NewUserRealm(dev))
	uassert.AbortsContains(t, cur, "owner only", func() { Propose(cross(cur), "catalog", cat2) })
	// a realm owner (a multisig) works the same way
	testing.SetRealm(testing.NewUserRealm(alice))
	Offer(cross(cur), chain.PackageAddress("gno.land/r/team/multisig"))
	testing.SetRealm(testing.NewCodeRealm("gno.land/r/team/multisig"))
	Accept(cross(cur))
	Propose(cross(cur), "catalog", cat2)
}

// The guardian pauses and cancels, nothing else. A stolen owner key alone
// can neither remove nor replace it.
func TestGuardian(cur realm, t *testing.T) {
	reset()
	testing.SetRealm(testing.NewUserRealm(dev))
	Offer(cross(cur), alice)
	testing.SetRealm(testing.NewUserRealm(alice))
	Accept(cross(cur)) // alice owns, dev guards
	Propose(cross(cur), "catalog", cat2)

	// the owner cannot touch the guardian role
	uassert.AbortsContains(t, cur, "guardian only", func() { GuardianOffer(cross(cur), alice) })
	uassert.AbortsContains(t, cur, "guardian only", func() { GuardianRenounce(cross(cur)) })
	uassert.AbortsContains(t, cur, "nothing offered to you", func() { GuardianAccept(cross(cur)) })
	uassert.Equal(t, dev, Guardian())

	// nobody else cancels or pauses
	testing.SetRealm(testing.NewUserRealm(bob))
	uassert.AbortsContains(t, cur, "owner only", func() { Cancel(cross(cur)) })
	uassert.AbortsContains(t, cur, "owner only", func() { Pause(cross(cur), "", true) })

	// the guardian pauses and cancels, but never resumes, proposes or owns
	testing.SetRealm(testing.NewUserRealm(dev))
	Pause(cross(cur), "", true)
	uassert.AbortsContains(t, cur, "owner only", func() { Pause(cross(cur), "", false) })
	uassert.AbortsContains(t, cur, "owner only", func() { Propose(cross(cur), "radio", radio2) })
	uassert.AbortsContains(t, cur, "owner only", func() { Offer(cross(cur), dev) })
	uassert.AbortsContains(t, cur, "owner only", func() { Renounce(cross(cur)) })
	Cancel(cross(cur))
	uassert.Equal(t, "", proposed[0])
	testing.SetRealm(testing.NewUserRealm(alice))
	Pause(cross(cur), "", false)

	// the guardian alone passes its role on, in two steps
	testing.SetRealm(testing.NewUserRealm(dev))
	GuardianOffer(cross(cur), bob)
	testing.SetRealm(testing.NewUserRealm(alice))
	uassert.AbortsContains(t, cur, "nothing offered to you", func() { GuardianAccept(cross(cur)) })
	testing.SetRealm(testing.NewUserRealm(bob))
	GuardianAccept(cross(cur))
	uassert.Equal(t, bob, Guardian())

	// once the owner renounced, the guardian cannot pause (nobody could resume)
	testing.SetRealm(testing.NewUserRealm(alice))
	Renounce(cross(cur))
	testing.SetRealm(testing.NewUserRealm(bob))
	uassert.AbortsContains(t, cur, "owner only", func() { Pause(cross(cur), "", true) })
}

func TestOwnerCallsTakeNoCoins(cur realm, t *testing.T) {
	reset()
	testing.SetRealm(testing.NewUserRealm(dev))
	testing.SetOriginSend(chain.Coins{{"ugnot", 1}})
	uassert.AbortsContains(t, cur, "takes no coins", func() { Pause(cross(cur), "", true) })
	uassert.AbortsContains(t, cur, "takes no coins", func() { Offer(cross(cur), alice) })
	uassert.AbortsContains(t, cur, "takes no coins", func() { GuardianOffer(cross(cur), alice) })
	uassert.AbortsContains(t, cur, "takes no coins", func() { VaultWithdraw(cross(cur), "catalog/1") })
	testing.SetOriginSend(nil)
}

// Batch reads the caller's strings and keeps nothing of its slice.
func TestBatchDoesNotAliasSlice(cur realm, t *testing.T) {
	reset()
	testing.SetRealm(testing.NewCodeRealm(cat1))
	Make(cross(cur), "catalog/meta")
	ops := store.Ops{}.Set("catalog/meta", "a", "1").Set("catalog/meta", "b", "2")
	Batch(cross(cur), ops)
	ops[3], ops[7] = "changed", "changed"
	ops = ops.Set("catalog/meta", "c", "3")
	a, _ := Get("catalog/meta", "a")
	b, _ := Get("catalog/meta", "b")
	uassert.Equal(t, "12", a+b)
	uassert.False(t, Has("catalog/meta", "c"))
	Batch(cross(cur), store.Ops{}.Del("catalog/meta", "a"))
	uassert.False(t, Has("catalog/meta", "a"))
}

func TestLimits(cur realm, t *testing.T) {
	reset()
	testing.SetRealm(testing.NewCodeRealm(cat1))
	Make(cross(cur), "catalog/meta")
	Make(cross(cur), "catalog/meta") // nothing if it exists
	uassert.Equal(t, 1, nColls[0])
	Set(cross(cur), "catalog/meta", strings.Repeat("k", 128), strings.Repeat("v", 16<<10))
	uassert.AbortsContains(t, cur, "a key is 1 to 128 bytes", func() { Set(cross(cur), "catalog/meta", "", "v") })
	uassert.AbortsContains(t, cur, "a key is 1 to 128 bytes", func() { Set(cross(cur), "catalog/meta", strings.Repeat("k", 129), "v") })
	uassert.AbortsContains(t, cur, "a key is 1 to 128 bytes", func() { Remove(cross(cur), "catalog/meta", "") })
	uassert.AbortsContains(t, cur, "at most 16 KiB", func() { Set(cross(cur), "catalog/meta", "k", strings.Repeat("v", 16<<10+1)) })
	uassert.AbortsContains(t, cur, "no collection", func() { Set(cross(cur), "catalog/none", "k", "v") })
	uassert.AbortsContains(t, cur, "set or del", func() { Batch(cross(cur), []string{"put", "catalog/meta", "k", "v"}) })
	uassert.AbortsContains(t, cur, "up to 64 ops", func() { Batch(cross(cur), []string{"set", "catalog/meta", "k"}) })
	var ops store.Ops
	for i := 0; i < 64; i++ {
		ops = ops.Set("catalog/meta", store.Pad(i), "v")
	}
	Batch(cross(cur), ops)
	ops = ops.Set("catalog/meta", "x", "v")
	uassert.AbortsContains(t, cur, "up to 64 ops", func() { Batch(cross(cur), ops) })
	uassert.Equal(t, 65, Size("catalog/meta"))

	for _, bad := range []string{"catalog/", "catalog/Meta", "catalog/a-b", "catalog/a/b", "catalog/" + strings.Repeat("x", 25)} {
		uassert.AbortsContains(t, cur, "collection", func() { Make(cross(cur), bad) })
	}
	for i := 1; i < maxColls; i++ {
		Make(cross(cur), "catalog/c"+store.Pad(i))
	}
	uassert.AbortsContains(t, cur, "32 collections per role", func() { Make(cross(cur), "catalog/one_more") })

	uassert.PanicsWithMessage(t, cur, "data: a page is 1 to 100 rows", func() { Page("catalog/meta", "", "", 0, false) })
	uassert.PanicsWithMessage(t, cur, "data: a page is 1 to 100 rows", func() { PageAt("catalog/meta", 0, 101, true) })
	keys, _ := store.Rows(Page("catalog/meta", "", "", 100, false))
	uassert.Equal(t, 65, len(keys))
}

func TestReads(cur realm, t *testing.T) {
	reset()
	testing.SetRealm(testing.NewCodeRealm(cat1))
	Make(cross(cur), "catalog/likes")
	var ops store.Ops
	for _, k := range []string{"a/1", "a/2", "a/3", "b/1", "c/1"} {
		ops = ops.Set("catalog/likes", k, "v"+k)
	}
	Batch(cross(cur), ops)
	page := func(s string) string {
		k, v := store.Rows(s)
		return strings.Join(k, ",") + "|" + strings.Join(v, ",")
	}
	uassert.Equal(t, 5, Size("catalog/likes"))
	uassert.Equal(t, 0, Size("catalog/none"))
	_, ok := Get("catalog/likes", "")
	uassert.False(t, ok) // the seed is not a key
	uassert.False(t, Has("catalog/none", "a/1"))
	uassert.Equal(t, 3, Index("catalog/likes", "b")-Index("catalog/likes", "a")) // keys in [a, b)
	uassert.Equal(t, 0, Index("catalog/likes", "a/1"))
	uassert.Equal(t, 5, Index("catalog/likes", "z"))
	uassert.Equal(t, "a/1,a/2|va/1,va/2", page(Page("catalog/likes", "a", "b", 2, false)))
	uassert.Equal(t, "a/3,a/2,a/1|va/3,va/2,va/1", page(Page("catalog/likes", "a", "b", 10, true)))
	uassert.Equal(t, "c/1,b/1|vc/1,vb/1", page(Page("catalog/likes", "", "", 2, true)))
	uassert.Equal(t, "a/1|va/1", page(Page("catalog/likes", "", "", 1, false)))
	uassert.Equal(t, "a/3,b/1|va/3,vb/1", page(PageAt("catalog/likes", 2, 2, false)))
	uassert.Equal(t, "b/1,a/3,a/2,a/1|vb/1,va/3,va/2,va/1", page(PageAt("catalog/likes", 1, 10, true)))
	uassert.Equal(t, "", PageAt("catalog/likes", 5, 10, false))
	uassert.Equal(t, "", PageAt("catalog/likes", 1<<63-1, 10, false))
	uassert.Equal(t, "", Page("catalog/none", "", "", 10, false))
}

func TestIsGnoRadio(t *testing.T) {
	reset()
	for _, p := range []string{"gno.land/r/gnoradio/data", "gno.land/r/gnoradio/tickets/nft", cat1, radio1} {
		uassert.True(t, IsGnoRadio(chain.PackageAddress(p)), p)
	}
	uassert.False(t, IsGnoRadio(alice))
	uassert.False(t, IsGnoRadio(chain.PackageAddress(cat2)))
	// The upper-case spelling of a realm's address is the same account.
	for _, p := range []string{"gno.land/r/gnoradio/data", "gno.land/r/gnoradio/tickets/nft", cat1} {
		uassert.True(t, IsGnoRadio(address(strings.ToUpper(chain.PackageAddress(p).String()))), p)
	}
}

// A stolen guardian key takes the role (offer to itself, accept) and vetoes:
// the owner replaces it after 2x DELAY, and the thief can neither cancel nor
// outrun that. The guardian still cannot touch the owner.
func TestThiefGuardianIsReplaced(cur realm, t *testing.T) {
	reset()
	mallory := testutils.TestAddress("mallory")
	testing.SetRealm(testing.NewUserRealm(dev))
	GuardianOffer(cross(cur), alice)
	testing.SetRealm(testing.NewUserRealm(alice))
	GuardianAccept(cross(cur)) // dev owns, alice guards; then alice's key is stolen
	GuardianOffer(cross(cur), mallory)
	testing.SetRealm(testing.NewUserRealm(mallory))
	GuardianAccept(cross(cur))
	Pause(cross(cur), "", true)

	// only the owner replaces, with a canonical address
	upper := address(strings.ToUpper(bob.String()))
	uassert.AbortsContains(t, cur, "owner only", func() { GuardianReplace(cross(cur), mallory) })
	testing.SetRealm(testing.NewUserRealm(bob))
	uassert.AbortsContains(t, cur, "owner only", func() { GuardianReplace(cross(cur), bob) })
	testing.SetRealm(testing.NewUserRealm(dev))
	uassert.AbortsContains(t, cur, "not an address", func() { GuardianReplace(cross(cur), upper) })
	GuardianReplace(cross(cur), bob)
	Pause(cross(cur), "", false)
	Propose(cross(cur), "catalog", cat2)
	uassert.True(t, strings.Contains(Writers(), `"nextGuardian":"`+bob.String()+`","guardianAt":`))

	// the thief cancels releases and re-pauses, but cannot stop the replacement
	testing.SetRealm(testing.NewUserRealm(mallory))
	Cancel(cross(cur))
	uassert.AbortsContains(t, cur, "no release pending", func() { Cancel(cross(cur)) })
	Pause(cross(cur), "", true)
	uassert.AbortsContains(t, cur, "owner only", func() { GuardianReplace(cross(cur), mallory) })
	GuardianOffer(cross(cur), alice) // a pending offer dies with the role
	uassert.Equal(t, mallory, Guardian())
	testing.SkipHeights(blocksIn(2*DELAY) - 2)
	uassert.Equal(t, mallory, Guardian())
	testing.SkipHeights(2)
	uassert.Equal(t, bob, Guardian())
	uassert.AbortsContains(t, cur, "owner only", func() { Pause(cross(cur), "radio", true) })
	uassert.AbortsContains(t, cur, "guardian only", func() { GuardianOffer(cross(cur), mallory) })
	testing.SetRealm(testing.NewUserRealm(alice))
	uassert.AbortsContains(t, cur, "nothing offered to you", func() { GuardianAccept(cross(cur)) })
	testing.SetRealm(testing.NewUserRealm(dev))
	Pause(cross(cur), "", false)
	testing.SetRealm(testing.NewUserRealm(bob))
	Pause(cross(cur), "radio", true)
	uassert.True(t, Paused("radio"))
	uassert.Equal(t, dev, Owner())
	uassert.True(t, strings.Contains(Writers(), `"nextGuardian":"","guardianAt":0`))

	// the owner withdraws a replacement with ""; the guardian never touches the owner
	testing.SetRealm(testing.NewUserRealm(dev))
	GuardianReplace(cross(cur), mallory)
	GuardianReplace(cross(cur), "")
	testing.SkipHeights(blocksIn(2 * DELAY))
	uassert.Equal(t, bob, Guardian())
	testing.SetRealm(testing.NewUserRealm(bob))
	uassert.AbortsContains(t, cur, "owner only", func() { Offer(cross(cur), bob) })
	uassert.AbortsContains(t, cur, "owner only", func() { Renounce(cross(cur)) })
}
