package tickets

import (
	"encoding/base64"
	"strings"
	"testing"

	"gno.land/p/gnoradio/store/v0"
	"gno.land/p/gnoradio/text/v0"
	"gno.land/p/nt/uassert/v0"
	"gno.land/p/nt/urequire/v0"
	catalog "gno.land/r/gnoradio/catalog/v1"
	"gno.land/r/gnoradio/data"
	"gno.land/r/gnoradio/tickets/nft"
)

// Ported from tickets v0: fees, pages, hidden concerts, the upcoming index.

func decodeURI(t *testing.T, uri, prefix string) string {
	urequire.True(t, strings.HasPrefix(uri, prefix), uri)
	raw, err := base64.StdEncoding.DecodeString(strings.TrimPrefix(uri, prefix))
	urequire.NoError(t, err)
	return string(raw)
}

// The fee goes to the treasury, the price to the artist, in the same
// transaction; free tickets never carry it.
func TestServiceFee(cur realm, t *testing.T) {
	alice, aid := artist(cur, "Fee Alice")
	verify(cur, aid, true)
	carol := who("carol")
	treasury := catalog.Treasury()

	testing.SetRealm(testing.NewUserRealm(carol))
	uassert.AbortsWithMessage(t, cur, "tickets: admin only", func() { SetServiceFee(cross(cur), 500_000) })
	testing.SetRealm(testing.NewUserRealm(boss))
	uassert.AbortsContains(t, cur, "between 0 and 10 GNOT", func() { SetServiceFee(cross(cur), 11_000_000) })
	uassert.AbortsContains(t, cur, "between 0 and 10 GNOT", func() { SetServiceFee(cross(cur), -1) })
	SetServiceFee(cross(cur), 500_000)
	uassert.Equal(t, int64(500_000), ServiceFee())
	uassert.Equal(t, `{"serviceFee":500000,"treasury":"`+treasury.String()+`"}`, FeesJSON())

	testing.SetRealm(testing.NewUserRealm(alice))
	paidID := CreateEvent(cross(cur), "Fee Party", "Club", "", inHours(48), "2", 10)
	freeID := CreateEvent(cross(cur), "Free Party", "Park", "", inHours(48), "0", 10)
	urequire.True(t, strings.Contains(EventsJSON(0, 2, false), `"fee":500000}`))

	a0, t0 := balance(alice), balance(treasury)
	testing.SetRealm(testing.NewUserRealm(carol))
	testing.SetOriginSend(ugnots(2_000_000))
	uassert.AbortsContains(t, cur, "attach exactly 2.5 GNOT", func() { BuyTicket(cross(cur), paidID) })
	testing.IssueCoins(realmAddr, ugnots(2_500_000))
	testing.SetOriginSend(ugnots(2_500_000))
	BuyTicket(cross(cur), paidID)
	uassert.Equal(t, a0+2_000_000, balance(alice))
	uassert.Equal(t, t0+500_000, balance(treasury))
	uassert.Equal(t, int64(0), balance(realmAddr))

	testing.SetOriginSend(nil)
	BuyTicket(cross(cur), freeID)
	uassert.Equal(t, a0+2_000_000, balance(alice))
	uassert.Equal(t, t0+500_000, balance(treasury))

	fee(cur, 0)
	urequire.True(t, strings.Contains(EventsJSON(0, 2, false), `"fee":0}`))
	testing.IssueCoins(realmAddr, ugnots(2_000_000))
	testing.SetOriginSend(ugnots(2_000_000))
	testing.SetRealm(testing.NewUserRealm(carol))
	BuyTicket(cross(cur), paidID)
	uassert.Equal(t, a0+4_000_000, balance(alice))
	uassert.Equal(t, int64(0), balance(realmAddr))
	testing.SetOriginSend(nil)
}

// EventsJSON(all) jumps to its offset and hands back the next one; hidden
// concerts are left out of the page instead of ending the list. Upcoming
// pages count listed concerts.
func TestEventsJSONOffsetCursor(cur realm, t *testing.T) {
	before := len(Upcoming(50)) // every listed concert so far starts sooner
	alice, _ := artist(cur, "Gig Alice")
	testing.SetRealm(testing.NewUserRealm(alice))
	var ids []int
	for i := 0; i < 5; i++ {
		ids = append(ids, CreateEvent(cross(cur), "Gig "+text.Itoa(i), "Club", "", inHours(4000+i), "0", 10))
	}
	testing.SetRealm(testing.NewUserRealm(boss))
	HideEvent(cross(cur), ids[3], true, "test hide")

	page := EventsJSON(0, 2, false) // newest first: Gig 4, Gig 3 (hidden)
	uassert.True(t, strings.Contains(page, `"title":"Gig 4"`), page)
	uassert.False(t, strings.Contains(page, `"title":"Gig 3"`), page)
	uassert.True(t, strings.HasSuffix(page, `],"next":2}`), page)
	page = EventsJSON(4, 1, false)
	uassert.True(t, strings.Contains(page, `"title":"Gig 0"`), page)
	next := 5
	if next >= EventCount() {
		next = 0
	}
	uassert.True(t, strings.HasSuffix(page, `],"next":`+text.Itoa(next)+`}`), page)
	uassert.True(t, strings.HasSuffix(EventsJSON(EventCount(), 5, false), `"events":[],"next":0}`))

	// Listed: Gig 0, 1, 2, 4 after the ones before.
	page = EventsJSON(before, 2, true)
	uassert.True(t, strings.Contains(page, `"title":"Gig 1"`), page)
	uassert.True(t, strings.HasSuffix(page, `],"next":`+text.Itoa(before+2)+`}`), page)
	page = EventsJSON(before+2, 2, true)
	uassert.True(t, strings.Contains(page, `"title":"Gig 4"`), page)
	uassert.True(t, strings.HasSuffix(page, `],"next":0}`), page)
}

// A ticket for a concert hidden by moderation, or of a hidden artist, keeps
// no detail of it.
func TestHiddenConcertTicket(cur realm, t *testing.T) {
	alice, aid := artist(cur, "Secret Alice")
	carol := who("carol")
	testing.SetRealm(testing.NewUserRealm(alice))
	id := CreateEvent(cross(cur), "Secret Gig", "Hidden Venue", "", inHours(48), "0", 10)
	testing.SetRealm(testing.NewUserRealm(carol))
	tk := BuyTicket(cross(cur), id)
	meta := decodeURI(t, nft.TokenURI(text.Itoa(tk)), "data:application/json;base64,")
	uassert.True(t, strings.Contains(meta, "Secret Gig"))
	uassert.True(t, strings.Contains(meta, "Secret Alice"))

	testing.SetRealm(testing.NewUserRealm(boss))
	HideEvent(cross(cur), id, true, "fake concert")
	for _, hidden := range []bool{true, false} {
		meta = decodeURI(t, nft.TokenURI(text.Itoa(tk)), "data:application/json;base64,")
		uassert.False(t, strings.Contains(meta, "Secret Gig"), meta)
		uassert.False(t, strings.Contains(meta, "Secret Alice"), meta)
		uassert.True(t, strings.Contains(meta, "Removed by moderation"))
		img := TicketSVG(tk)
		svg := decodeURI(t, img[strings.Index(img, "(")+1:len(img)-1], "data:image/svg+xml;base64,")
		uassert.False(t, strings.Contains(svg, "Hidden Venue"))
		uassert.False(t, strings.Contains(svg, "Secret Gig"))
		if hidden { // then the concert is back, but its artist is hidden
			testing.SetRealm(testing.NewUserRealm(boss))
			HideEvent(cross(cur), id, false, "")
			hideArtist(cur, aid, true)
		}
	}
	_, ok := EventInfo(id)
	uassert.False(t, ok)
	uassert.Equal(t, 0, len(ArtistEvents(aid, 10)))
	hideArtist(cur, aid, false)
	uassert.Equal(t, 1, len(ArtistEvents(aid, 10)))
}

// Check-in refuses a cancelled concert; & is allowed in concert text.
func TestCheckInCancelledAndAmpersand(cur realm, t *testing.T) {
	alice, _ := artist(cur, "Amp Alice")
	testing.SetRealm(testing.NewUserRealm(alice))
	id := CreateEvent(cross(cur), "Simon & Friends", "Bar & Club", "", inHours(6), "0", 10)
	uassert.True(t, strings.Contains(EventsJSON(0, 1, false), `"title":"Simon & Friends"`))
	testing.SetRealm(testing.NewUserRealm(who("carol")))
	tk := BuyTicket(cross(cur), id)
	testing.SetRealm(testing.NewUserRealm(alice))
	CancelEvent(cross(cur), id)
	uassert.AbortsContains(t, cur, "cancelled", func() { CheckIn(cross(cur), tk, "4821") })
}

func TestRenderPointsHome(t *testing.T) {
	uassert.True(t, strings.Contains(Render(""), "(/r/gnoradio/home/v1)"))
	uassert.True(t, strings.Contains(Render(""), "(/r/gnoradio/tickets/nft)"))
	uassert.False(t, strings.Contains(Render(""), "retired"))
}

// Y5 (v0): upcoming reads the start-ordered index, skips hidden, cancelled
// and past concerts; an artist holds at most 10 open future concerts.
func TestUpcomingIndexAndOpenCap(cur realm, t *testing.T) {
	alice, aid := artist(cur, "Cap Alice")
	testing.SetRealm(testing.NewUserRealm(alice))
	var ids []int
	for i := 0; i < maxOpenAhead; i++ {
		ids = append(ids, CreateEvent(cross(cur), "Show", "Club", "", inHours(30+i*2), "0", 10))
	}
	uassert.AbortsContains(t, cur, "upcoming concerts at a time", func() {
		CreateEvent(cross(cur), "Show", "Club", "", inHours(100), "0", 10)
	})
	mine := func() []int {
		var out []int
		for _, e := range Upcoming(50) {
			if e.ArtistID == aid {
				out = append(out, e.ID)
			}
		}
		return out
	}
	up := mine()
	urequire.Equal(t, maxOpenAhead, len(up))
	uassert.Equal(t, ids[0], up[0]) // soonest first

	CancelEvent(cross(cur), ids[9])
	testing.SetRealm(testing.NewUserRealm(boss))
	HideEvent(cross(cur), ids[8], true, "duplicate listing")
	uassert.Equal(t, maxOpenAhead-2, len(mine()))
	js := EventsJSON(0, 50, true)
	uassert.False(t, strings.Contains(js, `"id":`+text.Itoa(ids[8])+`,`))
	uassert.True(t, strings.Contains(js, `"id":`+text.Itoa(ids[7])+`,`))
	HideEvent(cross(cur), ids[8], false, "")
	uassert.Equal(t, maxOpenAhead-1, len(mine()))

	// The cancelled slot is free again; then a concert passing frees another.
	testing.SetRealm(testing.NewUserRealm(alice))
	CreateEvent(cross(cur), "Late", "Club", "", inHours(200), "0", 10)
	uassert.AbortsContains(t, cur, "upcoming concerts at a time", func() {
		CreateEvent(cross(cur), "Show", "Club", "", inHours(201), "0", 10)
	})
	testing.SkipHeights(31 * 720) // 31 hours: the soonest concert (in 30h) is over
	uassert.Equal(t, maxOpenAhead-1, len(mine()))
	CreateEvent(cross(cur), "Next", "Club", "", inHours(202), "0", 10)
}

// A hidden artist's concerts leave the Upcoming index once anyone refreshes
// the artist, so hidden spam cannot fill the scan; restored, they come back.
func TestRefreshArtistPrunesUpcoming(cur realm, t *testing.T) {
	alice, aid := artist(cur, "Spam Alice")
	testing.SetRealm(testing.NewUserRealm(alice))
	a := CreateEvent(cross(cur), "Show", "Club", "", inHours(48), "0", 10)
	b := CreateEvent(cross(cur), "Gone", "Club", "", inHours(50), "0", 10)
	CancelEvent(cross(cur), b)
	ea, eb := getEvent(a), getEvent(b)
	uassert.True(t, data.Has(cUpcoming, upKey(ea)))
	uassert.False(t, data.Has(cUpcoming, upKey(eb)))

	hideArtist(cur, aid, true)
	testing.SetRealm(testing.NewUserRealm(who("carol")))
	testing.SetOriginSend(ugnots(1))
	uassert.AbortsContains(t, cur, "takes no coins", func() { RefreshArtist(cross(cur), aid) })
	testing.SetOriginSend(nil)
	RefreshArtist(cross(cur), aid)
	uassert.False(t, data.Has(cUpcoming, upKey(ea)))

	hideArtist(cur, aid, false)
	RefreshArtist(cross(cur), aid)
	uassert.True(t, data.Has(cUpcoming, upKey(ea)))
	uassert.False(t, data.Has(cUpcoming, upKey(eb))) // the cancelled one stays out
}

// Review R57: an artist's concert count is capped at maxPerArtist.
func TestConcertCap(cur realm, t *testing.T) {
	alice, aid := artist(cur, "Cap Count")
	p := store.Pad(aid)
	testing.SetRealm(testing.NewCodeRealm("gno.land/r/gnoradio/tickets/v1"))
	for i := 0; i < maxPerArtist; i++ {
		data.Set(cross(cur), cByArtist, p+"/"+store.Pad(9_000_000+i), "")
	}
	testing.SetRealm(testing.NewUserRealm(alice))
	uassert.AbortsContains(t, cur, "concert limit reached", func() {
		CreateEvent(cross(cur), "One More", "Club", "", inHours(40), "0", 10)
	})
}

// Restoring a concert puts it back in Upcoming only while it is visible,
// not cancelled and still to come.
func TestHideEventRestoreChecks(cur realm, t *testing.T) {
	w, aid := artist(cur, "Restore Artist")
	listed := func(id int) bool {
		for _, e := range Upcoming(50) {
			if e.ID == id {
				return true
			}
		}
		return false
	}
	testing.SetRealm(testing.NewUserRealm(w))
	soon := CreateEvent(cross(cur), "Soon", "Club", "", inHours(1), "0", 5)
	later := CreateEvent(cross(cur), "Later", "Club", "", inHours(48), "0", 5)
	testing.SetRealm(testing.NewUserRealm(boss))
	HideEvent(cross(cur), later, true, "test hide")
	hideArtist(cur, aid, true)
	testing.SetRealm(testing.NewUserRealm(boss))
	HideEvent(cross(cur), later, false, "")
	uassert.False(t, listed(later)) // its artist is hidden
	hideArtist(cur, aid, false)
	testing.SetRealm(testing.NewUserRealm(boss))
	HideEvent(cross(cur), later, false, "")
	uassert.True(t, listed(later))
	HideEvent(cross(cur), soon, true, "test hide")
	testing.SkipHeights(2 * 720) // the concert is over
	HideEvent(cross(cur), soon, false, "")
	uassert.False(t, listed(soon))
}
