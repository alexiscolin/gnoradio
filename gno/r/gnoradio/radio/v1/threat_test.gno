package radio

import (
	"chain"
	"chain/runtime"
	"strings"
	"testing"

	"gno.land/p/gnoradio/store/v0"
	"gno.land/p/gnoradio/text/v0"
	"gno.land/p/nt/testutils/v0"
	"gno.land/p/nt/uassert/v0"
	"gno.land/p/nt/urequire/v0"
	"gno.land/r/gnoradio/data"
)

// Threat model rows of docs/ARCHITECTURE-v1.md section 8 that radio owns.

// Payment bypass through a realm: the payable entrypoint takes coins only
// from a wallet's direct call, and every listener call refuses realms. A
// MsgRun ephemeral realm has a pkgpath like any realm, so it fails
// IsUserCall the same way (v1.5.0's test harness cannot make an ephemeral
// caller: NewCodeRealm refuses /e/ paths). The other calls take no coins.
func TestPayRefusesRealms(cur realm, t *testing.T) {
	a, _ := onAirSetup(cur, "Pay Realm Artist", true)
	testing.SetOriginSend(ugnots(ugnot))
	testing.SetRealm(testing.NewCodeRealm("gno.land/r/evil/proxy"))
	uassert.AbortsContains(t, cur, "directly from your wallet", func() { TipOnAir(cross(cur), 5, a, 0, "") })
	testing.SetOriginSend(nil)
	for _, call := range []func(){
		func() { Queue(cross(cur), 5, a) },
		func() { QueueAt(cross(cur), 5, a, now()+3600) },
		func() { QueueWithNote(cross(cur), 5, a, "hi", now()+60, "") },
		func() { QueueSponsored(cross(cur), 5, a) },
		func() { ReportNote(cross(cur), 5, now()) },
		func() { ClaimPickPayout(cross(cur), 5, now()) },
	} {
		uassert.AbortsContains(t, cur, "directly from your wallet", call)
	}
	testing.SetOriginSend(ugnots(1))
	testing.SetRealm(testing.NewUserRealm(dave))
	for _, call := range []func(){
		func() { Queue(cross(cur), 5, a) },
		func() { Sync(cross(cur), 1) },
		func() { Refresh(cross(cur), a) },
		func() { ClaimPickPayout(cross(cur), 5, now()) },
		func() { Ready(cross(cur)) },
	} {
		uassert.AbortsContains(t, cur, "does not take coins", call)
	}
	testing.SetRealm(testing.NewUserRealm(erin))
	uassert.AbortsContains(t, cur, "does not take coins", func() { SetModBot(cross(cur), "") })
	testing.SetOriginSend(nil)
}

// Rules realms end every transaction holding nothing: a tip passes through.
func TestRulesHoldNothing(cur realm, t *testing.T) {
	a, _ := onAirSetup(cur, "Hold Nothing", true)
	tipOnAir(cur, dave, 5, a, bob, 3*ugnot)
	uassert.Equal(t, int64(0), balance(radioAddr))
	uassert.Equal(t, int64(0), balance(catalogAddr))
	syncVault()
	uassert.True(t, balance(dataAddr) >= data.VaultTotal())
}

// A realm or account writes no radio data: the data realm lets only the
// current radio writer through, whoever calls.
func TestOnlyRadioWritesRadio(cur realm, t *testing.T) {
	for _, r := range []runtime.Realm{
		testing.NewCodeRealm("gno.land/r/gnoradio/catalog/v1"),
		testing.NewCodeRealm("gno.land/r/evil/proxy"),
		testing.NewUserRealm(erin),
	} {
		testing.SetRealm(r)
		uassert.AbortsContains(t, cur, "writes radio", func() { data.Set(cross(cur), cStations, store.Pad(0), "x") })
		uassert.AbortsContains(t, cur, "writes radio", func() { data.Batch(cross(cur), store.Ops{}.Set(cCurators, carol.String(), "x")) })
	}
	uassert.Equal(t, "gno.land/r/gnoradio/radio/v1", data.Writer("radio"))
}

// The admin passes in two steps, every change mirrored to the data realm
// for the next release; the mirror is the authority.
func TestAdminTwoStep(cur realm, t *testing.T) {
	reset(cur)
	newAdmin := testutils.TestAddress("newadmin")
	testing.SetRealm(testing.NewUserRealm(carol))
	uassert.AbortsWithMessage(t, cur, "radio: admin only", func() { OfferAdmin(cross(cur), carol) })
	testing.SetRealm(testing.NewUserRealm(erin))
	OfferAdmin(cross(cur), newAdmin)
	uassert.Equal(t, erin, Admin()) // nothing changes before the accept
	testing.SetRealm(testing.NewUserRealm(carol))
	uassert.AbortsContains(t, cur, "nothing offered to you", func() { AcceptAdmin(cross(cur)) })
	testing.SetRealm(testing.NewUserRealm(newAdmin))
	testing.SetOriginSend(ugnots(1))
	uassert.AbortsContains(t, cur, "does not take coins", func() { AcceptAdmin(cross(cur)) })
	testing.SetOriginSend(nil)
	AcceptAdmin(cross(cur))
	uassert.Equal(t, newAdmin, Admin())
	v, _ := data.Get(cConfig, "admin")
	uassert.Equal(t, newAdmin.String(), v)
	testing.SetRealm(testing.NewUserRealm(erin))
	uassert.AbortsWithMessage(t, cur, "radio: admin only", func() { SetModBot(cross(cur), "") })

	// The previous release (or this one's mirror) is the authority.
	seedAdmin(cur, erin.String())
	uassert.Equal(t, erin, Admin())
	testing.SetRealm(testing.NewUserRealm(newAdmin))
	uassert.AbortsWithMessage(t, cur, "radio: admin only", func() { SetModBot(cross(cur), "") })
	seedAdmin(cur, "") // renounced by the previous release
	testing.SetRealm(testing.NewUserRealm(erin))
	uassert.AbortsWithMessage(t, cur, "radio: admin only", func() { SetModBot(cross(cur), "") })
	uassert.Equal(t, address(""), Admin())
	seedAdmin(cur, erin.String())

	// Renounce is for good, here and in the next releases (the mirror says so).
	testing.SetRealm(testing.NewUserRealm(erin))
	OfferAdmin(cross(cur), newAdmin)
	RenounceAdmin(cross(cur))
	v, _ = data.Get(cConfig, "admin")
	uassert.Equal(t, "", v)
	testing.SetRealm(testing.NewUserRealm(newAdmin))
	uassert.AbortsContains(t, cur, "nothing offered", func() { AcceptAdmin(cross(cur)) })
	seedAdmin(cur, erin.String()) // the dev admin back for the next tests
	testing.SetRealm(testing.NewUserRealm(erin))
	SetModBot(cross(cur), "")
}

// A paused radio writes nothing and moves no coin through the catalog;
// reads go on.
func TestPausedRadio(cur realm, t *testing.T) {
	a, _ := onAirSetup(cur, "Paused Radio", true)
	owner := chain.PackageAddress("gno.land/r/gnoradio/data/dev")
	testing.SetRealm(testing.NewUserRealm(owner))
	data.Pause(cross(cur), "radio", true)
	uassert.AbortsContains(t, cur, "paused", func() { tipOnAir(cur, dave, 5, a, "", ugnot) })
	testing.SetOriginSend(nil)
	testing.SetRealm(testing.NewUserRealm(dave))
	uassert.AbortsContains(t, cur, "radio is paused", func() { Queue(cross(cur), NewStation, a) })
	id, _, _ := NowPlaying(5)
	uassert.Equal(t, a, id)
	uassert.True(t, strings.Contains(ScheduleJSON(5, 600), `"track":`+text.Itoa(a)))
	testing.SetRealm(testing.NewUserRealm(owner))
	data.Pause(cross(cur), "radio", false)
}

// Records stay under the data realm's 16 KiB: Main and Choice's full ring,
// each with 30 picks waiting whose dedications are 40 four-byte characters. A burst past that is refused, cleanly.
func TestRecordSizes(cur realm, t *testing.T) {
	reset(cur)
	note := strings.Repeat("𝄞", maxNote)
	by := testutils.TestAddress("worstcase")
	ts := now()
	worst := func(n int) []Slot {
		var sl []Slot
		for i := 0; i < n; i++ {
			sl = append(sl, Slot{Track: 1 << 23, Start: ts + int64(i)*1200, Dur: 1200, By: by, Note: note, Pay: 50_000, At: ts + bookMax, artist: 1 << 23})
		}
		return sl
	}
	edit(cur, func(t *tx) {
		t.station(MainStation).setSlots(worst(maxQueue))
		ch := t.station(ChoiceStation)
		for i := 0; i < choiceCap; i++ {
			ch.joinAt(i, false, 1<<23+i, 1200, ts, choiceCap)
		}
		ch.setSlots(worst(maxQueue))
	})
	rec, _ := data.Get(cStations, store.Pad(ChoiceStation))
	urequire.True(t, len(rec) < maxRecord, text.Itoa(len(rec)))
	rec, _ = data.Get(cStations, store.Pad(MainStation))
	urequire.True(t, len(rec) < maxRecord, text.Itoa(len(rec)))
	uassert.PanicsContains(t, cur, "this station is full for now", func() {
		edit(cur, func(t *tx) { t.station(4).setSlots(worst(80)) })
	})
}

// seedAdmin writes the admin mirror as a release of the radio would.
func seedAdmin(cur realm, h string) {
	testing.SetRealm(testing.NewCodeRealm(self))
	data.Set(cross(cur), cConfig, "admin", h)
}
