package nft

import (
	"chain"
	"strconv"
	"strings"
	"testing"

	"gno.land/p/gnoradio/svg/v0"
	"gno.land/p/nt/testutils/v0"
	"gno.land/p/nt/uassert/v0"
	catalog "gno.land/r/gnoradio/catalog/v1"
	"gno.land/r/gnoradio/data"
)

// Pins the ticket SVG byte for byte: the same bytes as tickets v0's art.
func TestTicketGolden(t *testing.T) {
	e := concert{id: 7, artist: 99, title: "Rock & Roll Night", venue: "Bar & Grill, Lyon", start: 1795000000, price: 2000000, capacity: 100}
	out := draw(e, 12, false).Data() + draw(e, 3, true).Data()
	e.cancelled = true
	out += draw(e, 1, false).Data()
	if svg.FNV(out) != 3078800029 || len(out) != 14486 {
		t.Fatalf("ticket art changed: %d %d", svg.FNV(out), len(out))
	}
}

// The artist line reads the catalog's records in the data realm: it agrees
// with the catalog's own readers, for a visible, a renamed and a hidden artist.
func TestArtistFromCatalogRecords(cur realm, t *testing.T) {
	testing.SetRealm(testing.NewUserRealm(testutils.TestAddress("nft_artist")))
	var ids []int
	for i := 0; i < 10; i++ { // across two chunks
		testing.SetRealm(testing.NewUserRealm(testutils.TestAddress("nft_artist" + strconv.Itoa(i))))
		ids = append(ids, catalog.RegisterArtist(cross(cur), "Nft Artist "+strconv.Itoa(i), ""))
	}
	catalog.RegisterArtist(cross(cur), "Nft Renamed & Co", "") // the last one renames itself
	testing.SetRealm(testing.NewUserRealm(catalog.Admin()))
	catalog.HideArtist(cross(cur), ids[3], true, "spam")
	for _, id := range append(ids, 0, 99) {
		uassert.Equal(t, catalog.ArtistVisible(id), artistVisible(id))
		want := ""
		if catalog.ArtistVisible(id) {
			want = catalog.ArtistName(id)
		}
		uassert.Equal(t, want, ArtistName(id))
	}
	uassert.Equal(t, "Nft Renamed & Co", ArtistName(ids[9]))
	uassert.Equal(t, "", ArtistName(ids[3]))
}

// Only the tickets writer mints and transfers, and not while it is paused:
// wallets, other realms, MsgRun and a retired or proposed writer are refused.
func TestOnlyTicketsWriter(cur realm, t *testing.T) {
	alice, bob := testutils.TestAddress("nft_alice"), testutils.TestAddress("nft_bob")
	w := data.Writer("tickets")
	for _, caller := range []string{"", "gno.land/r/evil/minter", "gno.land/r/gnoradio/catalog/v1", "gno.land/r/gnoradio/tickets/v2", "gno.land/r/gnoradio/tickets/v0"} {
		if caller == "" {
			testing.SetRealm(testing.NewUserRealm(alice))
		} else {
			testing.SetRealm(testing.NewCodeRealm(caller))
		}
		uassert.AbortsContains(t, cur, "only "+w+" mints", func() { Mint(cross(cur), alice, 900) })
		uassert.AbortsContains(t, cur, "only "+w+" mints", func() { Transfer(cross(cur), alice, bob, 900) })
	}

	testing.SetOriginCaller(alice)
	testing.SetRealm(testing.NewCodeRealm(w))
	uassert.AbortsContains(t, cur, "minted to the wallet that signs", func() { Mint(cross(cur), bob, 900) })
	Mint(cross(cur), alice, 900)
	uassert.Equal(t, alice, OwnerOf("900"))
	uassert.AbortsContains(t, cur, "already exists", func() { Mint(cross(cur), alice, 900) })
	uassert.AbortsContains(t, cur, "invalid ticket id", func() { Mint(cross(cur), alice, 0) })
	// Even the writer moves a ticket only in its holder's own transaction.
	uassert.AbortsContains(t, cur, "holder's own transaction", func() { Transfer(cross(cur), bob, alice, 900) })
	testing.SetOriginCaller(bob)
	testing.SetRealm(testing.NewCodeRealm(w))
	uassert.AbortsContains(t, cur, "not token owner", func() { Transfer(cross(cur), bob, alice, 900) })
	testing.SetOriginCaller(alice)
	testing.SetRealm(testing.NewCodeRealm(w))
	// Not to the upper-case spelling of a wallet: no key signs for that string.
	uassert.AbortsContains(t, cur, "not an address", func() {
		Transfer(cross(cur), alice, address(strings.ToUpper(bob.String())), 900)
	})
	Transfer(cross(cur), alice, bob, 900)
	uassert.Equal(t, bob, Holder(900))
	uassert.Equal(t, int64(1), BalanceOf(bob))
	uassert.Equal(t, int64(0), BalanceOf(alice))
	uassert.Equal(t, address(""), Holder(901))

	// A paused tickets role mints and moves nothing.
	owner := chain.PackageAddress("gno.land/r/gnoradio/data/dev")
	testing.SetRealm(testing.NewUserRealm(owner))
	data.Pause(cross(cur), "tickets", true)
	testing.SetOriginCaller(bob)
	testing.SetRealm(testing.NewCodeRealm(w))
	uassert.AbortsContains(t, cur, "tickets is paused", func() { Mint(cross(cur), bob, 902) })
	uassert.AbortsContains(t, cur, "tickets is paused", func() { Transfer(cross(cur), bob, alice, 900) })
	testing.SetRealm(testing.NewUserRealm(owner))
	data.Pause(cross(cur), "tickets", false)

	uassert.True(t, strings.Contains(Render(""), "GnoRadio Ticket ($GRTIX)"))
	uassert.Equal(t, "", TicketSVG(900)) // no tickets record behind this test mint
	uassert.PanicsContains(t, cur, "unknown ticket", func() { TokenURI("900") })
}

// A release moves the minting right with the tickets role, and no ticket
// moves: the retired writer is refused, the new one mints. Runs last, as the
// release stays in force.
func TestReleaseMovesMinter(cur realm, t *testing.T) {
	alice, bob := testutils.TestAddress("nft_alice"), testutils.TestAddress("nft_bob")
	v1, v2 := data.Writer("tickets"), "gno.land/r/gnoradio/tickets/v2"
	testing.SetOriginCaller(alice)
	testing.SetRealm(testing.NewCodeRealm(v1))
	Mint(cross(cur), alice, 910)
	testing.SetRealm(testing.NewUserRealm(chain.PackageAddress("gno.land/r/gnoradio/data/dev")))
	data.Propose(cross(cur), "tickets", v2)
	testing.SetRealm(testing.NewCodeRealm(v2))
	uassert.AbortsContains(t, cur, "only "+v1+" mints", func() { Mint(cross(cur), alice, 911) })
	data.Ready(cross(cur))
	testing.SkipHeights(data.DELAY/5 + 1)
	testing.SetRealm(testing.NewCodeRealm(v1))
	uassert.AbortsContains(t, cur, "only "+v2+" mints", func() { Transfer(cross(cur), alice, bob, 910) })
	testing.SetOriginCaller(alice)
	testing.SetRealm(testing.NewCodeRealm(v2))
	Transfer(cross(cur), alice, bob, 910)
	Mint(cross(cur), alice, 911)
	uassert.Equal(t, bob, Holder(910))
	uassert.Equal(t, alice, Holder(911))
}
