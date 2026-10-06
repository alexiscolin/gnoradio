package gnoradio

import (
	"chain"
	"chain/banker"
	"strings"
	"testing"
	"time"

	"gno.land/p/nt/avl/v0"
	"gno.land/p/nt/testutils/v0"
	"gno.land/p/nt/uassert/v0"
	"gno.land/p/nt/urequire/v0"
)

var (
	alice = testutils.TestAddress("alice")
	bob   = testutils.TestAddress("bob")
	carol = testutils.TestAddress("carol")
	dave  = testutils.TestAddress("dave")
)

var realmAddr = chain.PackageAddress("gno.land/r/g1y2tswmrtlany2ffmpyc0uyunk4gt4gv8gtf736/gnoradio")

const cid = "bafybeigdyrzt5sfp7udm7hu76uh7y26nf3efuylqabf3oclgtqy55fbzdi"

func reset() {
	artists, names, tracks, events, tickets = avl.Tree{}, avl.Tree{}, avl.Tree{}, avl.Tree{}, avl.Tree{}
	owned, listeners, reports = avl.Tree{}, avl.Tree{}, avl.Tree{}
	nTracks, nEvents, nTickets, nReports = 0, 0, 0, 0
	schedule, epoch, rotTotal = nil, 0, 0
	topArtists, topFans, topLiked = nil, nil, nil
	ticketTok, ticketLed = nil, nil
	frozen, successor = false, ""
	admin = bob
}

func ugnots(n int64) chain.Coins { return chain.Coins{{Denom: denom, Amount: n}} }

func balance(addr address) int64 {
	return banker.NewReadonlyBanker().GetCoins(addr).AmountOf(denom)
}

func publish(cur realm, title, dur string) int {
	return Publish(cross(cur), title, "", "", cid, "cc-by", "none", dur, "", "oui")
}

func TestArtistAndTrack(cur realm, t *testing.T) {
	reset()
	testing.SetRealm(testing.NewUserRealm(alice))
	Register(cross(cur), "Léa K", "Synthwave depuis Lyon")
	id := Publish(cross(cur), "Neon Rivers", "synthwave", "Léa K, prod Moko", cid, "cc by", "none", "4:02", carol.String()+":30", "oui")
	uassert.Equal(t, 1, id)
	tr := getTrack(1)
	uassert.Equal(t, "CC-BY-4.0", tr.License)
	uassert.Equal(t, int64(242), tr.Duration)
	uassert.Equal(t, int64(30), tr.Splits[0].Pct)

	testing.SetRealm(testing.NewUserRealm(bob))
	uassert.AbortsContains(t, cur, "déjà pris", func() { Register(cross(cur), "léa k", "") })
	uassert.AbortsContains(t, cur, "nom d'artiste", func() { Register(cross(cur), "Lеa", "") }) // Cyrillic е
	uassert.AbortsContains(t, cur, "profil d'artiste", func() { publish(cur, "Nope", "1:00") })

	testing.SetRealm(testing.NewUserRealm(alice))
	uassert.AbortsContains(t, cur, "déclarer détenir les droits", func() {
		Publish(cross(cur), "X", "", "", cid, "CC0", "none", "1:00", "", "")
	})
	uassert.AbortsContains(t, cur, "licence inconnue", func() {
		Publish(cross(cur), "X", "", "", cid, "MIT", "none", "1:00", "", "oui")
	})
	uassert.AbortsContains(t, cur, "SACEM", func() {
		Publish(cross(cur), "X", "", "", cid, "CC-BY", "sacem-nc", "1:00", "", "oui")
	})
	Publish(cross(cur), "Ok NC", "", "", cid, "CC-BY-NC", "sacem-nc", "1:00", "", "oui")
	uassert.AbortsContains(t, cur, "m:ss", func() { publish(cur, "X", "1:7") })
	uassert.AbortsContains(t, cur, "g1...:30", func() {
		Publish(cross(cur), "X", "", "", cid, "CC0", "none", "1:00", alice.String()+":30", "oui")
	})
	uassert.AbortsContains(t, cur, "g1...:30", func() {
		Publish(cross(cur), "X", "", "", cid, "CC0", "none", "1:00", realmAddr.String()+":30", "oui")
	})
	uassert.AbortsContains(t, cur, "90 %", func() {
		Publish(cross(cur), "X", "", "", cid, "CC0", "none", "1:00", bob.String()+":50,"+carol.String()+":50", "oui")
	})

	EditTrack(cross(cur), 1, "Neon Rivers radio edit", "synthwave", "", cid, "CC-BY-SA", "none", "3:30")
	uassert.Equal(t, int64(210), getTrack(1).Duration)
	uassert.Equal(t, "CC-BY-SA-4.0", getTrack(1).License)
	testing.SetRealm(testing.NewUserRealm(carol))
	uassert.AbortsContains(t, cur, "seul l'artiste", func() {
		EditTrack(cross(cur), 1, "Hijack", "", "", cid, "CC0", "none", "1:00")
	})
}

func TestLikeAndEarlyBadges(cur realm, t *testing.T) {
	reset()
	testing.SetRealm(testing.NewUserRealm(alice))
	Register(cross(cur), "Alice", "")
	publish(cur, "Song", "1:40")
	uassert.AbortsContains(t, cur, "ton propre morceau", func() { Like(cross(cur), 1) })

	testing.SetRealm(testing.NewUserRealm(carol))
	Like(cross(cur), 1)
	uassert.AbortsContains(t, cur, "aimes déjà", func() { Like(cross(cur), 1) })
	uassert.Equal(t, 1, getTrack(1).Likes)
	uassert.Equal(t, carol, getTrack(1).early[0])
	uassert.Equal(t, "1", topLiked[0].key)
	urequire.True(t, strings.Contains(Render("listener/"+carol.String()), "data:image/svg+xml"))
}

func TestTipSplits(cur realm, t *testing.T) {
	reset()
	testing.SetRealm(testing.NewUserRealm(alice))
	Register(cross(cur), "Alice", "")
	Publish(cross(cur), "Song", "", "", cid, "CC-BY", "none", "1:40", bob.String()+":30", "oui")

	testing.IssueCoins(realmAddr, ugnots(10*ugnot))
	testing.SetOriginSend(ugnots(10 * ugnot))
	testing.SetRealm(testing.NewUserRealm(carol))
	Tip(cross(cur), 1)

	uassert.Equal(t, int64(7*ugnot), balance(alice))
	uassert.Equal(t, int64(3*ugnot), balance(bob))
	uassert.Equal(t, int64(0), balance(realmAddr))
	uassert.Equal(t, int64(10*ugnot), getTrack(1).Tips)
	uassert.Equal(t, 1, getTrack(1).Supporters)
	uassert.Equal(t, alice.String(), topArtists[0].key)
	uassert.Equal(t, carol.String(), topFans[0].key)

	// Payment guards.
	testing.SetOriginSend(chain.Coins{{Denom: "foo", Amount: ugnot}})
	uassert.AbortsContains(t, cur, "montant en ugnot", func() { Tip(cross(cur), 1) })
	testing.SetOriginSend(ugnots(10))
	uassert.AbortsContains(t, cur, "un tip va de", func() { Tip(cross(cur), 1) })
	testing.SetOriginSend(ugnots(ugnot))
	testing.SetRealm(testing.NewUserRealm(alice))
	uassert.AbortsContains(t, cur, "ton propre morceau", func() { Tip(cross(cur), 1) })
	testing.SetRealm(testing.NewCodeRealm("gno.land/r/evil/proxy"))
	uassert.AbortsContains(t, cur, "depuis ton wallet", func() { Tip(cross(cur), 1) })
	testing.SetRealm(testing.NewUserRealm(carol))
	uassert.AbortsContains(t, cur, "ne prend pas de GNOT", func() { Like(cross(cur), 1) })
	testing.SetOriginSend(nil)
}

func TestRadio(cur realm, t *testing.T) {
	reset()
	testing.SetRealm(testing.NewUserRealm(alice))
	Register(cross(cur), "Alice", "")
	publish(cur, "One", "1:00")
	publish(cur, "Two", "2:00")
	testing.SetRealm(testing.NewUserRealm(dave))
	Register(cross(cur), "Dave", "")
	publish(cur, "Three", "1:00")

	// Rotation: track 1 plays first from its publication.
	id, off, queued := NowPlaying()
	uassert.Equal(t, 1, id)
	uassert.Equal(t, int64(0), off)
	uassert.False(t, queued)

	// 20s in, publishing more does not move listeners.
	testing.SkipHeights(4)
	id, off, _ = NowPlaying()
	before := off
	publish(cur, "Four", "1:00")
	id2, off2, _ := NowPlaying()
	uassert.Equal(t, id, id2)
	uassert.Equal(t, before, off2)

	// Carol programs track 3: it starts when track 1 ends, nothing is cut.
	testing.SetRealm(testing.NewUserRealm(carol))
	Queue(cross(cur), 3)
	uassert.Equal(t, 1, len(UpNext()))
	ts := time.Now().Unix()
	uassert.Equal(t, ts+60-off2, schedule[0].Start)
	uassert.AbortsContains(t, cur, "déjà un morceau en attente", func() { Queue(cross(cur), 2) })

	// Duplicate and per-artist limits (Dave owns tracks 3 and 4).
	testing.SetRealm(testing.NewUserRealm(bob))
	uassert.AbortsContains(t, cur, "déjà programmé", func() { Queue(cross(cur), 3) })
	Queue(cross(cur), 4)
	testing.SetRealm(testing.NewUserRealm(alice))
	publish(cur, "Five", "1:00")
	testing.SetRealm(testing.NewUserRealm(dave))
	Queue(cross(cur), 5)
	uassert.Equal(t, 3, len(UpNext()))

	// When track 1 ends, carol's slot is on air; after the slots the
	// rotation resumes with track 2 (it was paused, not skipped).
	testing.SkipHeights((schedule[0].Start - ts + 5) / 5)
	id, _, queued = NowPlaying()
	uassert.Equal(t, 3, id)
	uassert.True(t, queued)
	ts = time.Now().Unix()
	last := schedule[len(schedule)-1]
	testing.SkipHeights((last.Start + last.Dur - ts + 5) / 5)
	id, off, queued = NowPlaying()
	uassert.Equal(t, 2, id)
	uassert.False(t, queued)
	urequire.True(t, off < 15)

	// Hiding the track on air moves the rotation to the next one, cleanly.
	testing.SetRealm(testing.NewUserRealm(bob))
	HideTrack(cross(cur), 2, true)
	id, off, _ = NowPlaying()
	uassert.Equal(t, 3, id)
	uassert.Equal(t, int64(0), off)

	js := ScheduleJSON(600)
	urequire.True(t, strings.Contains(js, `"track":3`))
	urequire.True(t, strings.Contains(Render(""), "data:image/svg+xml"))
}

func TestEventsAndTickets(cur realm, t *testing.T) {
	reset()
	testing.SetRealm(testing.NewUserRealm(alice))
	Register(cross(cur), "Alice", "")
	start := time.Now().Add(72 * time.Hour).UTC().Format("2006-01-02 15:04")
	eid := CreateEvent(cross(cur), "Release Party", "La Station, Paris", "https://live.example.org/watch?v=abc_1", start, "2.5", 2)
	uassert.Equal(t, 1, eid)
	past := time.Now().Add(-time.Hour).UTC().Format("2006-01-02 15:04")
	uassert.AbortsContains(t, cur, "dans le futur", func() { CreateEvent(cross(cur), "Past", "Here", "", past, "0", 10) })
	uassert.AbortsContains(t, cur, "https://", func() { CreateEvent(cross(cur), "Bad", "Here", "javascript:x", start, "0", 10) })

	testing.IssueCoins(realmAddr, ugnots(2_500_000))
	testing.SetOriginSend(ugnots(2_500_000))
	testing.SetRealm(testing.NewUserRealm(carol))
	tid := BuyTicket(cross(cur), 1)
	uassert.Equal(t, 1, tid)
	uassert.Equal(t, carol, TicketOwner(1))
	uassert.Equal(t, int64(2_500_000), balance(alice))
	testing.SetOriginSend(ugnots(1))
	uassert.AbortsContains(t, cur, "joins exactement", func() { BuyTicket(cross(cur), 1) })
	testing.SetOriginSend(nil)

	TransferTicket(cross(cur), dave, 1)
	uassert.Equal(t, dave, TicketOwner(1))
	uassert.Equal(t, 0, len(ownedBy(carol)))
	uassert.Equal(t, 1, len(ownedBy(dave)))
	uassert.AbortsContains(t, cur, "pas le détenteur", func() { TransferTicket(cross(cur), bob, 1) })

	// Check-in: artist only, from 12h before the start.
	testing.SetRealm(testing.NewUserRealm(dave))
	uassert.AbortsContains(t, cur, "seul l'artiste", func() { CheckIn(cross(cur), 1) })
	testing.SetRealm(testing.NewUserRealm(alice))
	uassert.AbortsContains(t, cur, "12h avant", func() { CheckIn(cross(cur), 1) })
	testing.SkipHeights(int64(62 * 3600 / 5))
	CheckIn(cross(cur), 1)
	urequire.True(t, getTicket(1).Attended)
	uassert.Equal(t, 1, listener(dave).Attended)
	testing.SetRealm(testing.NewUserRealm(dave))
	uassert.AbortsContains(t, cur, "déjà utilisé", func() { TransferTicket(cross(cur), bob, 1) })

	urequire.True(t, strings.Contains(Render("ticket/1"), "data:image/svg+xml"))
	urequire.True(t, strings.Contains(Render("listener/"+dave.String()), "j'y étais"))
	urequire.True(t, strings.HasPrefix(TokenURI("1"), "data:application/json;base64,"))
	urequire.True(t, strings.Contains(TicketsOfJSON(dave), `"attended":true`))

	// Cancel stops sales.
	testing.SetRealm(testing.NewUserRealm(alice))
	CancelEvent(cross(cur), 1)
	testing.SetOriginSend(ugnots(2_500_000))
	testing.SetRealm(testing.NewUserRealm(bob))
	uassert.AbortsContains(t, cur, "annulé", func() { BuyTicket(cross(cur), 1) })
	testing.SetOriginSend(nil)
	urequire.True(t, strings.Contains(Render("event/1"), "annulé"))
}

func TestModeration(cur realm, t *testing.T) {
	reset()
	testing.SetRealm(testing.NewUserRealm(alice))
	Register(cross(cur), "Alice", "")
	publish(cur, "Song", "1:40")
	start := time.Now().Add(72 * time.Hour).UTC().Format("2006-01-02 15:04")
	CreateEvent(cross(cur), "Fake Party", "Nowhere", "", start, "0", 10)

	testing.SetRealm(testing.NewUserRealm(carol))
	Report(cross(cur), "event", "1", "Arnaque, faux concert")
	urequire.True(t, strings.Contains(Render("moderation"), "Arnaque"))
	uassert.AbortsContains(t, cur, "track, event ou artist", func() { Report(cross(cur), "x", "1", "spam spam") })
	uassert.AbortsWithMessage(t, cur, "gnoradio: réservé aux modérateurs", func() { HideTrack(cross(cur), 1, true) })

	testing.SetRealm(testing.NewUserRealm(bob))
	HideEvent(cross(cur), 1, true)
	urequire.True(t, strings.Contains(Render("event/1"), "Introuvable"))
	HideTrack(cross(cur), 1, true)
	id, _, _ := NowPlaying()
	uassert.Equal(t, 0, id)
	urequire.True(t, strings.Contains(Render("track/1"), "Retiré par la modération"))
	HideTrack(cross(cur), 1, false)
	Verify(cross(cur), alice, true)
	urequire.True(t, strings.Contains(Render("artist/alice"), "✓"))
	HideArtist(cross(cur), alice, true)
	urequire.True(t, strings.Contains(Render("artist/alice"), "Introuvable"))
	testing.SetRealm(testing.NewUserRealm(carol))
	uassert.AbortsContains(t, cur, "morceau inconnu", func() { Like(cross(cur), 1) })

	testing.SetRealm(testing.NewUserRealm(bob))
	Freeze(cross(cur), true)
	testing.SetRealm(testing.NewUserRealm(carol))
	uassert.AbortsContains(t, cur, "en pause", func() { Register(cross(cur), "Carol", "") })
	testing.SetRealm(testing.NewUserRealm(bob))
	SetSuccessor(cross(cur), "gno.land/r/demo/gnoradio2")
	urequire.True(t, strings.Contains(Render(""), "déménagé"))
	testing.SetOriginSend(ugnots(1))
	uassert.AbortsContains(t, cur, "ne prend pas de GNOT", func() { Freeze(cross(cur), false) })
	testing.SetOriginSend(nil)
}

func TestRenderPages(cur realm, t *testing.T) {
	reset()
	for _, p := range []string{"", "charts", "join", "about", "catalog", "artists", "concerts", "moderation", "track/99", "artist/x", "../etc", "catalog?p=abc"} {
		urequire.True(t, len(Render(p)) > 0)
	}
	urequire.True(t, strings.Contains(Render("join"), `<gno-form exec="Publish">`))
	urequire.True(t, strings.Contains(Info(), `"version":"0.2.0"`))
}

// TestRenderGas seeds a busy catalog: gnoweb pages are served by vm/qrender,
// which has a 3B gas budget per page.
func TestRenderGas(cur realm, t *testing.T) {
	reset()
	testing.SetRealm(testing.NewUserRealm(alice))
	Register(cross(cur), "Alice", "")
	for i := 0; i < 60; i++ {
		publish(cur, "Song "+itoa(i), "3:00")
	}
	start := time.Now().Add(72 * time.Hour).UTC().Format("2006-01-02 15:04")
	CreateEvent(cross(cur), "Release Party", "Paris", "", start, "0", 100)
	for _, p := range []string{"", "track/1", "artist/alice", "charts", "event/1", "catalog", "catalog?p=2"} {
		urequire.True(t, len(Render(p)) > 0)
	}
	urequire.True(t, len(TracksJSON(0, 50)) > 0)
	urequire.True(t, len(ScheduleJSON(7200)) > 0)
}
