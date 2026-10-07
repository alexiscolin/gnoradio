package catalog

import "gno.land/p/gnoradio/store/v0"

// Promo share: an artist lets a part of each tip go to the listeners who
// brought the tipper, the one who picked the track on the radio and the one
// whose link they followed. The artist sets it (0..20%, 5% by default) and the
// tipper sees it before signing. The radio realm alone knows who picked what
// is on air, so the shared tips arrive through RadioTip, which only that realm
// may call; it never takes a picker from the client. The admin names that
// realm (SetRadioRealm), so a radio v1 works with this catalog.

const (
	defaultPromoPct = 5
	maxPromoPct     = 20
)

var (
	promo      = store.NewMap(8192) // artist id -> promo percent, once the artist set one
	radioRealm = "gno.land/r/gnoradio/radio/v0"
)

// SetRadioRealm names the radio realm allowed to call RadioTip; it also
// becomes a GnoRadio realm that never receives tips or support (SetSibling).
// Admin only.
func SetRadioRealm(cur realm, pkgPath string) {
	onlyAdmin(cur)
	mustRealmPath(pkgPath)
	addSibling(pkgPath)
	emitEvent("RadioRealm", "from", radioRealm, "to", pkgPath)
	radioRealm = pkgPath
}

// RadioRealm is the realm allowed to call RadioTip.
func RadioRealm() string { return radioRealm }

// SetPromoShare sets the percent of each tip on the caller's tracks that goes
// to the picker and the referrer (0..20).
func SetPromoShare(cur realm, pct int) {
	caller := userCaller(cur)
	noPayment()
	notFrozen()
	if pct < 0 || pct > maxPromoPct {
		panic("catalog: the promo share is between 0 and 20%")
	}
	a := ownArtist(caller)
	promo.Set(itoa(a.ID), itoa(pct))
	emitEvent("PromoShare", "artist", itoa(a.ID), "pct", itoa(pct))
}

// PromoShare returns an artist's promo percent.
func PromoShare(artistID int) int {
	if v, ok := promo.Get(itoa(artistID)); ok {
		return atoi(v)
	}
	return defaultPromoPct
}

// RadioTip pays a tip the radio realm received for the listener tipper
// (radio.TipOnAir): the radio has already forwarded total ugnot to this realm
// and names the picker of the slot on air. Only the radio realm may call it.
// It returns what the picker and the referrer received.
func RadioTip(cur realm, trackID, supportPct int, tipper, picker, ref address, total int64) (toPicker, toRef int64) {
	if cur.Previous().PkgPath() != radioRealm {
		panic("catalog: only the GnoRadio radio realm can call this")
	}
	return tip(cur, tipper, total, trackID, supportPct, picker, ref)
}

// promoShares splits an artist-side amount's promo share between the picker
// and the referrer still eligible ("" when not): half each, the odd ugnot to
// the picker, all of it to one alone.
func promoShares(amt int64, pct int, picker, ref address) (toPicker, toRef int64) {
	share := amt * int64(pct) / 100
	switch {
	case picker != "" && ref != "":
		toRef = share / 2
		return share - toRef, toRef
	case picker != "":
		return share, 0
	case ref != "":
		return 0, share
	}
	return 0, 0
}
