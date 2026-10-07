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

// Hide or restore content. Admin only. Hidden content stays on-chain (and on
// IPFS); it is no longer listed, played or tippable. Radio stations drop a
// hidden track on their next Refresh (radio.RefreshArtist for a whole artist).
func HideTrack(cur realm, trackID int, hidden bool) {
	onlyAdmin(cur)
	t := getTrack(trackID)
	if t == nil {
		panic("catalog: unknown track")
	}
	t.Hidden = hidden
	putTrack(t)
	emitEvent("Moderated", "kind", "track", "target", itoa(trackID), "hidden", strconv.FormatBool(hidden))
}

func HideAlbum(cur realm, albumID int, hidden bool) {
	onlyAdmin(cur)
	al := getAlbum(albumID)
	if al == nil {
		panic("catalog: unknown album")
	}
	al.Hidden = hidden
	putAlbum(al)
	emitEvent("Moderated", "kind", "album", "target", itoa(albumID), "hidden", strconv.FormatBool(hidden))
}

func HideArtist(cur realm, artistID int, hidden bool) {
	onlyAdmin(cur)
	a := getArtist(artistID)
	if a == nil {
		panic("catalog: unknown artist")
	}
	a.Hidden = hidden
	putArtist(a)
	emitEvent("Moderated", "kind", "artist", "target", itoa(artistID), "hidden", strconv.FormatBool(hidden))
}

func HidePlaylist(cur realm, playlistID int, hidden bool) {
	onlyAdmin(cur)
	p := getPlaylist(playlistID)
	if p == nil {
		panic("catalog: unknown playlist")
	}
	p.Hidden = hidden
	putPlaylist(p)
	emitEvent("Moderated", "kind", "playlist", "target", itoa(playlistID), "hidden", strconv.FormatBool(hidden))
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
	if pkgPath != "" && (!strings.HasPrefix(pkgPath, "gno.land/r/") || !validURLChars(pkgPath) || len(pkgPath) > 120) {
		panic("catalog: invalid realm path")
	}
	successor = pkgPath
	emitEvent("Successor", "path", pkgPath)
}
