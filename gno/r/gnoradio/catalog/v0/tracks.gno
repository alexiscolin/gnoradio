package catalog

import (
	"strconv"
	"strings"

	"gno.land/p/gnoradio/store/v0"
)

// PublishTrack adds a track by the caller's own artist profile.
// duration is "m:ss"; cmo is "none" or "sacem-nc"; splits is optional,
// "g1...:30,g1...:15" in percent (the artist keeps at least 10%);
// rights must be "yes" (the caller declares owning the rights).
// audio and cover are ipfs://, ar:// or https:// links (an allowed host,
// with the file's sha256).
func PublishTrack(cur realm, title string, genre int, duration, license, cmo, credits, audio, audioSHA, cover, coverSHA, splits, rights string) int {
	caller := userCaller(cur)
	noPayment()
	notFrozen()
	a := ownArtist(caller)
	if strings.ToLower(strings.TrimSpace(rights)) != "yes" {
		panic("catalog: declare that you own the rights (answer yes)")
	}
	t := &Track{Origin: OriginArtist, CMO: "none"}
	setInfo(t, title, genre, duration, credits)
	setLicense(t, license, cmo)
	setMedia(t, audio, audioSHA, cover, coverSHA)
	t.Splits = parseSplits(splits, caller, cur.Address())
	return addTrack(caller, a, t)
}

// ImportTrack adds a curated (CC0 / CC BY / CC BY-SA) or Audius track to an
// unclaimed artist. Admin only. Audius tracks use audio "audius:<trackId>".
func ImportTrack(cur realm, artistID int, title string, genre int, duration, license, credits, audio, audioSHA, cover, coverSHA, sourceURL, attribution string) int {
	onlyAdmin(cur)
	a := mustArtist(artistID)
	if a.Kind == OriginArtist {
		panic("catalog: artists publish their own tracks")
	}
	t := &Track{Origin: a.Kind, CMO: "none"}
	setInfo(t, title, genre, duration, credits)
	if a.Kind == OriginAudius {
		if !strings.HasPrefix(audio, "audius:") {
			panic("catalog: Audius tracks use audio audius:<trackId>")
		}
		t.License = AudiusLicense
	} else {
		lic := curatedLicense(license)
		if lic == "" {
			panic("catalog: curated imports must be CC0, CC BY or CC BY-SA")
		}
		t.License = lic
	}
	setMedia(t, audio, audioSHA, cover, coverSHA)
	sourceURL, attribution = strings.TrimSpace(sourceURL), strings.TrimSpace(attribution)
	if !validHTTPS(sourceURL) {
		panic("catalog: sourceURL must be the track's https page at the source")
	}
	mustText("attribution", attribution, 2, 160)
	t.SourceURL, t.Attribution = sourceURL, attribution
	return addTrack(admin, a, t)
}

// EditTrack fixes a track's details. Its artist only (the admin while the
// artist is unclaimed). Radio stations pick up a new duration on Refresh.
func EditTrack(cur realm, trackID int, title string, genre int, duration, credits, audio, audioSHA, cover, coverSHA string) {
	caller := userCaller(cur)
	noPayment()
	notFrozen()
	t := mustTrack(trackID)
	if !mayEdit(caller, getArtist(t.Artist)) {
		panic("catalog: only the artist can edit this track")
	}
	if t.Origin == OriginAudius && !strings.HasPrefix(audio, "audius:") {
		panic("catalog: Audius tracks use audio audius:<trackId>")
	}
	oldGenre := t.Genre
	setInfo(t, title, genre, duration, credits)
	if t.Genre != oldGenre {
		byGenre[oldGenre].Remove(t.ID)
		byGenre[t.Genre].Add(t.ID)
	}
	setMedia(t, audio, audioSHA, cover, coverSHA)
	putTrack(t)
	emitEvent("TrackEdited", "id", itoa(t.ID), "audio", t.Audio, "duration", itoa64(t.Duration), "genre", itoa(t.Genre))
}

func addTrack(publisher address, a *Artist, t *Track) int {
	trackIDs, albumIDs := lists(a.ID)
	if store.Count(trackIDs) >= maxPerArtist {
		panic("catalog: tracks per artist limit reached")
	}
	nTracks++
	t.ID, t.Artist, t.Created = nTracks, a.ID, now()
	tracks.Append(trackRecord(t))
	setLists(a.ID, trackIDs+store.Enc(t.ID), albumIDs)
	byGenre[t.Genre].Add(t.ID)
	recordActivity("publish", publisher, t.ID, a.ID, 0)
	emitEvent("TrackPublished", "id", itoa(t.ID), "artist", itoa(a.ID), "origin", t.Origin, "genre", itoa(t.Genre),
		"duration", itoa64(t.Duration), "title", t.Title, "audio", t.Audio, "license", t.License)
	return t.ID
}

func setInfo(t *Track, title string, genre int, duration, credits string) {
	title, credits = strings.TrimSpace(title), strings.TrimSpace(credits)
	mustText("title", title, 1, 64)
	mustText("credits", credits, 0, 160)
	if genre < 1 || genre > NumGenres {
		panic("catalog: genre must be 1.." + itoa(NumGenres))
	}
	d, ok := parseClock(duration)
	if !ok || d < minDuration || d > maxDuration {
		panic("catalog: duration as m:ss, between 0:10 and 20:00")
	}
	t.Title, t.Genre, t.Duration, t.Credits = title, genre, d, credits
}

func setLicense(t *Track, license, cmo string) {
	lic := normLicense(license)
	if lic == "" {
		panic("catalog: unknown license, use one of " + strings.Join(licenses, ", "))
	}
	cmo = strings.ToLower(strings.TrimSpace(cmo))
	switch cmo {
	case "", "none":
		cmo = "none"
	case "sacem-nc":
		if !strings.Contains(lic, "-NC") {
			panic("catalog: SACEM members may only publish works declared under a CC NC license")
		}
	default:
		panic("catalog: collective society must be none or sacem-nc")
	}
	t.License, t.CMO = lic, cmo
}

func setMedia(t *Track, audio, audioSHA, cover, coverSHA string) {
	audio, audioSHA = strings.TrimSpace(audio), strings.ToLower(strings.TrimSpace(audioSHA))
	cover, coverSHA = strings.TrimSpace(cover), strings.ToLower(strings.TrimSpace(coverSHA))
	mustMedia("audio", audio, audioSHA, true)
	if cover != "" {
		mustMedia("cover", cover, coverSHA, false)
	}
	t.Audio, t.AudioSHA, t.Cover, t.CoverSHA = audio, audioSHA, cover, coverSHA
}

func parseSplits(s string, artist, self address) []Split {
	s = strings.TrimSpace(s)
	if s == "" {
		return nil
	}
	parts := strings.Split(s, ",")
	if len(parts) > maxSplits {
		panic("catalog: at most 4 collaborators")
	}
	var out []Split
	var sum int64
	seen := map[string]bool{}
	for _, p := range parts {
		addrStr, pctStr, ok := strings.Cut(strings.TrimSpace(p), ":")
		to := address(strings.TrimSpace(addrStr))
		pct, err := strconv.ParseInt(strings.TrimSuffix(strings.TrimSpace(pctStr), "%"), 10, 64)
		if !ok || err != nil || !to.IsValid() || to == artist || to == self || seen[to.String()] || pct < 1 || pct > maxSplitPct {
			panic("catalog: collaborators as g1...:30,g1...:15 (percent)")
		}
		seen[to.String()] = true
		sum += pct
		out = append(out, Split{To: to, Pct: pct})
	}
	if sum > maxSplitPct {
		panic("catalog: collaborators may receive at most 90%")
	}
	return out
}
