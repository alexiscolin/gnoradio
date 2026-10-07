package catalog

import (
	"strconv"
	"strings"

	"gno.land/p/gnoradio/text/v0"
)

// Report flags a track, album, artist or playlist for the moderators
// (e.g. "broken link", "not the real artist", "copyright").
func Report(cur realm, kind string, target int, reason string) {
	caller := userCaller(cur)
	noPayment()
	notFrozen()
	reason = strings.TrimSpace(reason)
	mustText("reason", reason, 4, 200)
	switch kind {
	case "track":
		mustTrack(target)
	case "album":
		if al := getAlbum(target); al == nil || al.Hidden {
			panic("catalog: unknown album")
		}
	case "artist":
		mustArtist(target)
	case "playlist":
		if p := getPlaylist(target); p == nil || p.Hidden {
			panic("catalog: unknown playlist")
		}
	default:
		panic("catalog: kind must be track, album, artist or playlist")
	}
	if openReports >= maxReports {
		panic("catalog: the report queue is full, contact the moderators")
	}
	u := user(caller)
	if u.Reports >= maxUserReports {
		panic("catalog: you have " + itoa(maxUserReports) + " open reports, wait for the moderators")
	}
	u.Reports++
	putUser(caller, u)
	openReports++
	nReports++
	reports.Set(text.Key(nReports), &ReportInfo{ID: nReports, Kind: kind, Target: itoa(target), Reason: reason, By: caller, At: now()})
	emitEvent("Reported", "kind", kind, "target", itoa(target), "by", caller.String())
}

// ResolveReport closes a report once handled. Admin only.
func ResolveReport(cur realm, id int) {
	onlyAdmin(cur)
	v, ok := reports.Remove(text.Key(id))
	if !ok {
		panic("catalog: unknown report")
	}
	r := v.(*ReportInfo)
	if openReports > 0 {
		openReports--
	}
	if u := getUser(r.By); u != nil && u.Reports > 0 {
		u.Reports--
		putUser(r.By, u)
	}
	emitEvent("ReportResolved", "id", itoa(id))
}

// Hide or restore content. Admin only; hiding takes a public reason (4-200
// characters) and restoring works on anything, whoever hid it. Hidden content
// stays on-chain (and on IPFS); it is no longer listed, played or tippable.
// Radio stations drop a hidden track on their next Refresh
// (radio.RefreshArtist for a whole artist).
func HideTrack(cur realm, trackID int, hidden bool, reason string) {
	onlyAdmin(cur)
	t := getTrack(trackID)
	if t == nil {
		panic("catalog: unknown track")
	}
	t.Hidden = hidden
	putTrack(t)
	moderate("track", trackID, hidden, reason)
}

func HideAlbum(cur realm, albumID int, hidden bool, reason string) {
	onlyAdmin(cur)
	al := getAlbum(albumID)
	if al == nil {
		panic("catalog: unknown album")
	}
	al.Hidden = hidden
	putAlbum(al)
	moderate("album", albumID, hidden, reason)
}

func HideArtist(cur realm, artistID int, hidden bool, reason string) {
	onlyAdmin(cur)
	a := getArtist(artistID)
	if a == nil {
		panic("catalog: unknown artist")
	}
	a.Hidden = hidden
	putArtist(a)
	moderate("artist", artistID, hidden, reason)
}

func HidePlaylist(cur realm, playlistID int, hidden bool, reason string) {
	onlyAdmin(cur)
	p := getPlaylist(playlistID)
	if p == nil {
		panic("catalog: unknown playlist")
	}
	p.Hidden = hidden
	putPlaylist(p)
	moderate("playlist", playlistID, hidden, reason)
}

func moderate(kind string, id int, hidden bool, reason string) {
	reason = strings.TrimSpace(reason)
	k := kind + ":" + itoa(id)
	if hidden {
		mustText("reason", reason, 4, 200)
		removed.Set(k, reason)
	} else {
		removed.Remove(k)
	}
	emitEvent("Moderated", "kind", kind, "target", itoa(id), "hidden", strconv.FormatBool(hidden), "reason", reason, "by", "moderator")
}

// HideOwn hides or shows again the caller's own track, album or artist
// profile ("artist", with the profile's id). The artist can show again only
// what they hid themselves: what the moderator hid stays hidden.
func HideOwn(cur realm, kind string, id int, hidden bool) {
	caller := userCaller(cur)
	noPayment()
	notFrozen()
	a := getArtist(artistOf(caller))
	if a == nil {
		panic("catalog: create your artist profile first")
	}
	k := kind + ":" + itoa(id)
	if reason, ok := removed.Get(k); ok && reason != "" {
		panic("catalog: hidden by the moderator; contact them to restore it")
	}
	switch kind {
	case "track":
		t := getTrack(id)
		if t == nil || t.Artist != a.ID {
			panic("catalog: not your track")
		}
		mustToggle(t.Hidden, hidden)
		t.Hidden = hidden
		putTrack(t)
	case "album":
		al := getAlbum(id)
		if al == nil || al.Artist != a.ID {
			panic("catalog: not your album")
		}
		mustToggle(al.Hidden, hidden)
		al.Hidden = hidden
		putAlbum(al)
	case "artist":
		if id != a.ID {
			panic("catalog: not your profile")
		}
		mustToggle(a.Hidden, hidden)
		a.Hidden = hidden
		putArtist(a)
	default:
		panic("catalog: kind must be track, album or artist")
	}
	if hidden {
		removed.Set(k, "")
	} else {
		removed.Remove(k)
	}
	emitEvent("Moderated", "kind", kind, "target", itoa(id), "hidden", strconv.FormatBool(hidden), "reason", "", "by", "artist")
}

func mustToggle(was, hidden bool) {
	if was == hidden {
		if hidden {
			panic("catalog: already hidden")
		}
		panic("catalog: already shown")
	}
}

// HiddenNote says why a track, album, artist or playlist is hidden, for its
// page: "Removed by moderation: <reason>", "Hidden by the artist.", or "".
func HiddenNote(kind string, id int) string {
	reason, ok := removed.Get(kind + ":" + itoa(id))
	switch {
	case !ok:
		return ""
	case reason == "":
		return "Hidden by the artist."
	}
	return "Removed by moderation: " + reason
}

// Verify marks an artist whose identity was checked off-chain.
func Verify(cur realm, artistID int, verified bool) {
	onlyAdmin(cur)
	a := mustArtist(artistID)
	a.Verified = verified
	putArtist(a)
	claims.Remove(text.Key(artistID)) // settled by the admin either way
	if !verified {
		proofs.Remove(text.Key(artistID))
	}
	emitEvent("Verified", "artist", itoa(artistID), "verified", strconv.FormatBool(verified))
}

// AllowHost adds or removes an https host that audio and covers may use.
func AllowHost(cur realm, host string, allowed bool) {
	onlyAdmin(cur)
	host = strings.ToLower(strings.TrimSpace(host))
	if !validHost(host) {
		panic("catalog: invalid host")
	}
	if allowed {
		hosts.Set(host, true)
	} else {
		hosts.Remove(host)
	}
	emitEvent("HostAllowed", "host", host, "allowed", strconv.FormatBool(allowed))
}

func TransferAdmin(cur realm, to address) {
	onlyAdmin(cur)
	if !to.IsValid() {
		panic("catalog: invalid address")
	}
	emitEvent("AdminTransferred", "from", admin.String(), "to", to.String())
	admin = to
}

// Freeze stops new writes during a migration announced with SetSuccessor.
func Freeze(cur realm, on bool) {
	onlyAdmin(cur)
	frozen = on
	emitEvent("Frozen", "on", strconv.FormatBool(on))
}

func SetSuccessor(cur realm, pkgPath string) {
	onlyAdmin(cur)
	if pkgPath != "" {
		mustRealmPath(pkgPath)
	}
	successor = pkgPath
	emitEvent("Successor", "path", pkgPath)
}

func mustRealmPath(pkgPath string) {
	if !strings.HasPrefix(pkgPath, "gno.land/r/") || !validURLChars(pkgPath) || len(pkgPath) > 120 {
		panic("catalog: invalid realm path")
	}
}
