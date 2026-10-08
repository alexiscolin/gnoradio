package role

import (
	"chain"
	"strings"
	"testing"

	"gno.land/p/nt/testutils/v0"
	"gno.land/p/nt/uassert/v0"
)

var alice = testutils.TestAddress("alice")

const refused = "role: not the home realm's live cur"

// A role answers only its home realm's live cur. The positive paths (offer,
// accept, cancel, renounce) run through the data realm's tests, which hold
// a live cur of the home realm.
func TestRoleRefusesStaleRealm(cur realm, t *testing.T) {
	testing.SetRealm(testing.NewCodeRealm("gno.land/r/gnoradio/home"))
	r := New("owner", alice)
	uassert.Equal(t, "gno.land/r/gnoradio/home", r.home)
	// cur.Previous() and a made-up realm value carry the right path or
	// address but are not the live frame.
	stale := testing.MakeRealm(chain.PackageAddress("gno.land/r/gnoradio/home"), "gno.land/r/gnoradio/home", cur)
	for _, rlm := range []realm{cur.Previous(), stale} {
		uassert.PanicsWithMessage(t, cur, refused, func() { r.Is(0, rlm) })
		uassert.PanicsWithMessage(t, cur, refused, func() { r.Offer(0, rlm, alice) })
		uassert.PanicsWithMessage(t, cur, refused, func() { r.Accept(0, rlm) })
		uassert.PanicsWithMessage(t, cur, refused, func() { r.Renounce(0, rlm) })
	}
	uassert.Equal(t, alice, r.Holder())
}

// A live cur of another realm is refused too: a *Role that leaked is inert.
func TestRoleFromForeignRealm(cur realm, t *testing.T) {
	testing.SetRealm(testing.NewCodeRealm("gno.land/r/gnoradio/home"))
	r := New("owner", alice)
	testing.SetRealm(testing.NewCodeRealm("gno.land/r/evil/x"))
	uassert.True(t, cur.IsCurrent())
	uassert.PanicsWithMessage(t, cur, refused, func() { r.Must(0, cur) })
	uassert.PanicsWithMessage(t, cur, refused, func() { r.Offer(0, cur, alice) })
	uassert.PanicsWithMessage(t, cur, refused, func() { r.Accept(0, cur) })
	uassert.PanicsWithMessage(t, cur, refused, func() { r.Renounce(0, cur) })
	uassert.Equal(t, alice, r.Holder())
	uassert.Equal(t, address(""), r.Pending())
}

func TestNewNeedsAnAddress(cur realm, t *testing.T) {
	uassert.PanicsWithMessage(t, cur, "role: not an address", func() { New("owner", "") })
}

// An upper-case bech32 address passes IsValid and names the same account,
// but realms compare addresses as strings: Canonical refuses it, and so do
// New and Offer.
func TestCanonical(cur realm, t *testing.T) {
	upper := address(strings.ToUpper(alice.String()))
	uassert.True(t, upper.IsValid())
	uassert.True(t, Canonical(alice))
	for _, a := range []address{upper, "", "g1notanaddress"} {
		uassert.False(t, Canonical(a))
	}
	uassert.PanicsWithMessage(t, cur, "role: not an address", func() { New("owner", upper) })
}

func TestUpper(t *testing.T) {
	uassert.True(t, Upper(address(strings.ToUpper(alice.String()))))
	uassert.False(t, Upper(alice))
	uassert.False(t, Upper(""))
	mixed := address("G" + alice.String()[1:])
	uassert.False(t, mixed.IsValid()) // bech32 refuses mixed case, so the first byte is enough
	uassert.False(t, Canonical(mixed))
}

// Mirror and Adopt: the data realm's mirror wins over a release's own role.
func TestMirrorAndAdopt(cur realm, t *testing.T) {
	testing.SetRealm(testing.NewCodeRealm("gno.land/r/gnoradio/home"))
	bob := testutils.TestAddress("bob")
	r := New("admin", alice)
	uassert.Equal(t, alice, Mirror(r, "", false))
	uassert.Equal(t, bob, Mirror(r, bob.String(), true))
	uassert.Equal(t, address(""), Mirror(r, "", true))
	uassert.Equal(t, address(""), Mirror(nil, "", false))
	uassert.True(t, Adopt(r, "admin", "", false) == r)            // no mirror: keep
	uassert.True(t, Adopt(r, "admin", alice.String(), true) == r) // same holder: keep
	uassert.True(t, Adopt(r, "admin", "", true) == nil)           // renounced
	b := Adopt(r, "admin", bob.String(), true)                    // changed: adopt
	uassert.Equal(t, bob, b.Holder())
	uassert.Equal(t, "gno.land/r/gnoradio/home", b.home)
	n := Adopt(nil, "admin", alice.String(), true) // a nil role takes the mirror
	uassert.Equal(t, alice, n.Holder())
	uassert.Equal(t, "admin", n.name)
	uassert.True(t, Adopt(nil, "admin", "", false) == nil)
}

// A role renounced in an earlier release is nil in the next: reading its offer must not panic.
func TestNilRolePending(t *testing.T) {
	var r *Role
	if r.Pending() != "" {
		t.Fatal("a nil role has no pending offer")
	}
}
