package catalog

import (
	"testing"

	"gno.land/p/nt/uassert/v0"
)

// coverSHA goes into the track JSON as is: it must be a hash, and only with a cover.
func TestCoverSHAInjection(cur realm, t *testing.T) {
	w, _ := artist(cur, "inj")
	testing.SetRealm(testing.NewUserRealm(w))
	evil := `","audio":"https://evil/x.mp3","title":"x`
	uassert.AbortsContains(t, cur, "cover sha256", func() {
		PublishTrack(cross(cur), "X", 2, "1:00", "CC0", "none", "", ipfs, "", "", evil, "", "yes")
	})
	uassert.AbortsContains(t, cur, "cover sha256", func() { // a hash with no cover
		PublishTrack(cross(cur), "X", 2, "1:00", "CC0", "none", "", ipfs, "", "", sha, "", "yes")
	})
	uassert.AbortsContains(t, cur, "audio sha256", func() {
		PublishTrack(cross(cur), "X", 2, "1:00", "CC0", "none", "", ipfs, evil, "", "", "", "yes")
	})
	id := PublishTrack(cross(cur), "Fine", 2, "1:00", "CC0", "none", "", ipfs, sha, ipfs, sha, "", "yes")
	uassert.Equal(t, sha, getTrack(rd(), id).CoverSHA)
}

// A pointer keeps its platform id and stores no cover, for the owner and the admin.
func TestPointerEditRules(cur realm, t *testing.T) {
	dave := who("dave")
	testing.SetRealm(testing.NewUserRealm(boss))
	au := CreateArtist(cross(cur), OriginAudius, "", "", "audius-user:pr1")
	tr := ImportTrack(cross(cur), au, "", 1, "3:41", "", "", "audius:pr1t", "", "", "", "", "")
	uassert.AbortsContains(t, cur, "already imported", func() {
		ImportTrack(cross(cur), au, "", 1, "3:41", "", "", "audius:pr1t", "", "", "", "", "")
	})
	uassert.AbortsContains(t, cur, "keeps its audio", func() { EditTrack(cross(cur), tr, "", 1, "3:41", "", "audius:other", "", "", "") })
	uassert.AbortsContains(t, cur, "keeps its audio", func() { EditTrack(cross(cur), tr, "", 1, "3:41", "", "audius:pr1t", "", ipfs, sha) })
	AssignArtist(cross(cur), au, dave)
	testing.SetRealm(testing.NewUserRealm(dave))
	RegisterArtist(cross(cur), name("Owner"), "")
	uassert.AbortsContains(t, cur, "keeps its audio", func() { EditTrack(cross(cur), tr, "Mine", 1, "3:41", "", "audius:someonelse", "", "", "") })
	uassert.AbortsContains(t, cur, "keeps its audio", func() { EditTrack(cross(cur), tr, "Mine", 1, "3:41", "", "audius:pr1t", "", ipfs, sha) })
	EditTrack(cross(cur), tr, "Mine", 3, "3:50", "", "audius:pr1t", "", "", "")
	uassert.Equal(t, "audius:pr1t", getTrack(rd(), tr).Audio)
	uassert.Equal(t, "Mine", getTrack(rd(), tr).Title)
}

// A self-hidden artist cannot show again after HideSource; ResetOwner clears a
// pointer's claimant name and bio; ReleaseName frees a pointer's platform key.
func TestPointerAdminFixes(cur realm, t *testing.T) {
	dave := who("dave")
	testing.SetRealm(testing.NewUserRealm(boss))
	au := CreateArtist(cross(cur), OriginAudius, "", "", "audius-user:pf1")
	AssignArtist(cross(cur), au, dave)
	testing.SetRealm(testing.NewUserRealm(dave))
	nm := name("Claimant")
	RegisterArtist(cross(cur), nm, "My bio")
	HideOwn(cross(cur), "artist", au, true)
	testing.SetRealm(testing.NewUserRealm(boss))
	HideSource(cross(cur), "audius", au, 1, "API access ended")
	testing.SetRealm(testing.NewUserRealm(dave))
	uassert.AbortsContains(t, cur, "hidden by the moderator", func() { HideOwn(cross(cur), "artist", au, false) })

	testing.SetRealm(testing.NewUserRealm(boss))
	HideArtist(cross(cur), au, false, "")
	ResetOwner(cross(cur), au)
	a := getArtist(rd(), au)
	uassert.Equal(t, "", a.Name)
	uassert.Equal(t, "", a.Bio)
	_, taken := rd().get(cNames, skeleton(nm))
	uassert.False(t, taken)

	uassert.AbortsContains(t, cur, "visible artist", func() { ReleaseName(cross(cur), "audius-user:pf1") })
	HideArtist(cross(cur), au, true, "wrong id")
	ReleaseName(cross(cur), "audius-user:pf1")
	CreateArtist(cross(cur), OriginAudius, "", "", "audius-user:pf1")
}

// A hidden pointer track's key can be released for a re-import; a visible one cannot.
func TestPointerReimport(cur realm, t *testing.T) {
	testing.SetRealm(testing.NewUserRealm(boss))
	au := CreateArtist(cross(cur), OriginAudius, "", "", "audius-user:ri1")
	tr := ImportTrack(cross(cur), au, "", 1, "3:41", "", "", "audius:ri1t", "", "", "", "", "")
	uassert.AbortsContains(t, cur, "is visible", func() { ReleaseName(cross(cur), "track-audius:ri1t") })
	HideTrack(cross(cur), tr, true, "wrong track")
	ReleaseName(cross(cur), "track-audius:ri1t")
	ImportTrack(cross(cur), au, "", 1, "3:41", "", "", "audius:ri1t", "", "", "", "", "")
}

// ResetOwner keeps a curated artist's name; HideSource keeps a moderator's reason.
func TestResetCuratedAndHideSourceReason(cur realm, t *testing.T) {
	dave := who("dave")
	testing.SetRealm(testing.NewUserRealm(boss))
	nm := name("Kept")
	c := CreateArtist(cross(cur), OriginCurated, nm, "", "")
	AssignArtist(cross(cur), c, dave)
	ResetOwner(cross(cur), c)
	uassert.Equal(t, nm, getArtist(rd(), c).Name)
	_, taken := rd().get(cNames, skeleton(nm))
	uassert.True(t, taken)

	au := CreateArtist(cross(cur), OriginAudius, "", "", "audius-user:hr1")
	HideArtist(cross(cur), au, true, "DMCA notice")
	HideSource(cross(cur), "audius", au, 1, "API access ended")
	uassert.Equal(t, "Removed by moderation: DMCA notice", HiddenNote("artist", au))
}
