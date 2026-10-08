package catalog

import (
	"chain"
	"strings"
	"testing"

	"gno.land/p/gnoradio/text/v0"
	"gno.land/p/nt/uassert/v0"
	"gno.land/p/nt/urequire/v0"
)

func TestArtistAndPublish(cur realm, t *testing.T) {
	alice, bob, carol := who("alice"), who("bob"), who("carol")
	lea := name("Lea Kosmos")
	testing.SetRealm(testing.NewUserRealm(alice))
	n0 := TrackCount()
	aid := RegisterArtist(cross(cur), lea, "Night synthwave from Lyon.")
	id := PublishTrack(cross(cur), "Neon Rivers", 2, "4:02", "cc by", "none", "Lea Kosmos, mix Moko", ia, sha, "", "", carol.String()+":30", "yes")
	tr := getTrack(rd(), id)
	uassert.Equal(t, "CC-BY-4.0", tr.License)
	uassert.Equal(t, int64(242), tr.Duration)
	uassert.Equal(t, OriginArtist, tr.Origin)
	uassert.Equal(t, n0+1, TrackCount())
	a, g, d, ok := TrackBrief(id)
	uassert.Equal(t, aid, a)
	uassert.Equal(t, 2, g)
	uassert.Equal(t, int64(242), d)
	uassert.True(t, ok)
	uassert.Equal(t, alice, ArtistOwner(aid))
	uassert.Equal(t, aid, ArtistOf(alice))
	uassert.Equal(t, "Synthwave", GenreName(2))
	uassert.Equal(t, "Funk & Disco", GenreName(NumGenres))

	// Media rules.
	uassert.AbortsContains(t, cur, "host is not allowed", func() {
		PublishTrack(cross(cur), "X", 2, "1:00", "CC0", "none", "", "https://evil.example/x.mp3", sha, "", "", "", "yes")
	})
	uassert.AbortsContains(t, cur, "needs the file's sha256", func() {
		PublishTrack(cross(cur), "X", 2, "1:00", "CC0", "none", "", ia, "", "", "", "", "yes")
	})
	uassert.AbortsContains(t, cur, "only valid for audio", func() {
		PublishTrack(cross(cur), "X", 2, "1:00", "CC0", "none", "", ipfs, "", "audius:abc", "", "", "yes")
	})
	uassert.AbortsContains(t, cur, "rights declaration", func() {
		PublishTrack(cross(cur), "X", 2, "1:00", "CC0", "none", "", ipfs, "", "", "", "", "")
	})
	uassert.AbortsContains(t, cur, "genre must be", func() {
		PublishTrack(cross(cur), "X", NumGenres+1, "1:00", "CC0", "none", "", ipfs, "", "", "", "", "yes")
	})
	uassert.AbortsContains(t, cur, "SACEM", func() {
		PublishTrack(cross(cur), "X", 2, "1:00", "CC-BY", "sacem-nc", "", ipfs, "", "", "", "", "yes")
	})
	uassert.AbortsContains(t, cur, "collaborators as", func() {
		PublishTrack(cross(cur), "X", 2, "1:00", "CC0", "none", "", ipfs, "", "", "", realmAddr.String()+":30", "yes")
	})

	// Names: unique, Latin only, old name released after a rename.
	testing.SetRealm(testing.NewUserRealm(bob))
	uassert.AbortsContains(t, cur, "already taken", func() { RegisterArtist(cross(cur), strings.ToLower(lea), "") })
	uassert.AbortsContains(t, cur, "Latin letters", func() { RegisterArtist(cross(cur), "Lеa", "") }) // Cyrillic е
	uassert.AbortsContains(t, cur, "artist profile first", func() {
		PublishTrack(cross(cur), "Nope", 2, "3:30", "cc by", "none", "", ipfs, "", "", "", "", "yes")
	})
	testing.SetRealm(testing.NewUserRealm(alice))
	RegisterArtist(cross(cur), name("Lea K"), "")
	uassert.Equal(t, 0, ArtistByName(lea))

	// Edit by the artist only.
	EditTrack(cross(cur), id, "Neon Rivers radio edit", 1, "3:30", "", ipfs, "", "", "")
	tr = getTrack(rd(), id)
	uassert.Equal(t, int64(210), tr.Duration)
	uassert.Equal(t, 1, tr.Genre)
	uassert.Equal(t, id, GenrePage(1, 0, 1)[0])
	testing.SetRealm(testing.NewUserRealm(carol))
	uassert.AbortsContains(t, cur, "only the artist", func() {
		EditTrack(cross(cur), id, "Hijack", 1, "1:00", "", ipfs, "", "", "")
	})
}

func TestCuratedAudiusAndClaim(cur realm, t *testing.T) {
	carol, dave, bob := who("carol"), who("dave"), who("bob")
	testing.SetRealm(testing.NewUserRealm(carol))
	uassert.AbortsWithMessage(t, cur, "catalog: admin only", func() {
		CreateArtist(cross(cur), OriginCurated, name("Komiku"), "", "https://archive.org/details/komiku")
	})
	testing.SetRealm(testing.NewUserRealm(boss))
	k := CreateArtist(cross(cur), OriginCurated, name("Komiku"), "French composer.", "https://archive.org/details/komiku")
	au := CreateArtist(cross(cur), OriginAudius, name("Night Tapes"), "", "https://audius.co/nighttapes")
	t1 := ImportTrack(cross(cur), k, "Dreams", 5, "2:58", "CC0", "Komiku", ia, sha, "", "",
		"https://archive.org/details/komiku-dreams", "Komiku, CC0 1.0, via archive.org")
	uassert.Equal(t, OriginCurated, getTrack(rd(), t1).Origin)
	uassert.AbortsContains(t, cur, "CC0, CC BY or CC BY-SA", func() {
		ImportTrack(cross(cur), k, "X", 5, "2:00", "CC-BY-NC", "", ia, sha, "", "", "https://archive.org/details/x", "Komiku")
	})
	t2 := ImportTrack(cross(cur), au, "Midnight Drive", 1, "3:41", "", "", "audius:Dk3aQ", "", "", "",
		"https://audius.co/nighttapes/midnight-drive", "Night Tapes, Audius Open Music License")
	uassert.Equal(t, AudiusLicense, getTrack(rd(), t2).License)
	uassert.AbortsContains(t, cur, "audius:<trackId>", func() {
		ImportTrack(cross(cur), au, "X", 1, "2:00", "", "", ipfs, "", "", "", "https://audius.co/x", "Night Tapes")
	})

	// Unverified artists cannot be tipped.
	testing.IssueCoins(realmAddr, ugnots(ugnot))
	testing.SetOriginSend(ugnots(ugnot))
	testing.SetRealm(testing.NewUserRealm(carol))
	uassert.AbortsContains(t, cur, "not verified", func() { Tip(cross(cur), t1) })
	testing.SetOriginSend(nil)

	// Claim: the admin assigns the profile; tips then flow to the owner.
	testing.SetRealm(testing.NewUserRealm(boss))
	AssignArtist(cross(cur), k, dave)
	uassert.True(t, getArtist(rd(), k).Verified)
	uassert.AbortsContains(t, cur, "already claimed", func() { AssignArtist(cross(cur), k, bob) })
	testing.SetOriginSend(ugnots(ugnot))
	testing.SetRealm(testing.NewUserRealm(carol))
	Tip(cross(cur), t1)
	uassert.Equal(t, int64(ugnot), balance(dave))
	testing.SetOriginSend(nil)
}

func TestTipSplitsAndGuards(cur realm, t *testing.T) {
	alice, aid := artist(cur, "alice")
	bob, carol := who("bob"), who("carol")
	testing.SetRealm(testing.NewUserRealm(alice))
	id := PublishTrack(cross(cur), "Song", 2, "1:40", "CC-BY", "none", "", ipfs, "", "", "", bob.String()+":30", "yes")
	verified(cur, aid)

	testing.IssueCoins(realmAddr, ugnots(20*ugnot))
	testing.SetOriginSend(ugnots(10 * ugnot))
	testing.SetRealm(testing.NewUserRealm(carol))
	Tip(cross(cur), id)
	Tip(cross(cur), id)
	uassert.Equal(t, int64(14*ugnot), balance(alice))
	uassert.Equal(t, int64(6*ugnot), balance(bob))
	uassert.Equal(t, int64(0), balance(realmAddr))
	uassert.Equal(t, 1, getTrack(rd(), id).Supporters)
	uassert.Equal(t, int64(20*ugnot), getArtist(rd(), aid).Tips)
	uassert.Equal(t, text.Itoa(aid), TopArtists()[0].Key)
	uassert.Equal(t, carol.String(), TopFans()[0].Key)

	testing.SetOriginSend(chain.Coins{{Denom: "foo", Amount: ugnot}})
	uassert.AbortsContains(t, cur, "amount in ugnot", func() { Tip(cross(cur), id) })
	testing.SetOriginSend(ugnots(10))
	uassert.AbortsContains(t, cur, "between 0.1", func() { Tip(cross(cur), id) })
	testing.SetOriginSend(ugnots(ugnot))
	testing.SetRealm(testing.NewUserRealm(alice))
	uassert.AbortsContains(t, cur, "own track", func() { Tip(cross(cur), id) })
	testing.SetRealm(testing.NewCodeRealm("gno.land/r/evil/proxy"))
	uassert.AbortsContains(t, cur, "directly from your wallet", func() { Tip(cross(cur), id) })
	testing.SetRealm(testing.NewUserRealm(carol))
	uassert.AbortsContains(t, cur, "does not take coins", func() { Like(cross(cur), id) })
	testing.SetOriginSend(nil)
}

func TestLikesFollowsAlbumsPlaylists(cur realm, t *testing.T) {
	alice, aid := artist(cur, "alice")
	bob, carol := who("bob"), who("carol")
	a := publish(cur, alice, "One")
	b := publish(cur, alice, "Two")
	testing.SetRealm(testing.NewUserRealm(alice))
	uassert.AbortsContains(t, cur, "own track", func() { Like(cross(cur), a) })
	uassert.AbortsContains(t, cur, "follow yourself", func() { Follow(cross(cur), aid) })

	testing.SetRealm(testing.NewUserRealm(carol))
	Like(cross(cur), a)
	uassert.AbortsContains(t, cur, "already liked", func() { Like(cross(cur), a) })
	Follow(cross(cur), aid)
	uassert.Equal(t, 1, getArtist(rd(), aid).Followers)
	uassert.Equal(t, a, LikedPage(carol, 0, 1)[0])
	uassert.Equal(t, aid, FollowsPage(carol, 0, 1)[0])
	uassert.Equal(t, carol, getTrack(rd(), a).Early[0])
	Unlike(cross(cur), a)
	uassert.Equal(t, 0, getTrack(rd(), a).Likes)
	Unfollow(cross(cur), aid)
	uassert.Equal(t, 0, getArtist(rd(), aid).Followers)

	// Album by its artist.
	testing.SetRealm(testing.NewUserRealm(alice))
	al := CreateAlbum(cross(cur), aid, "First Light", "", "", 2026, text.Itoa(a)+","+text.Itoa(b))
	uassert.Equal(t, al, getTrack(rd(), b).Album)
	uassert.AbortsContains(t, cur, "duplicate", func() {
		CreateAlbum(cross(cur), aid, "Twice", "", "", 2026, text.Itoa(a)+","+text.Itoa(a))
	})
	uassert.AbortsContains(t, cur, "already in an album", func() {
		CreateAlbum(cross(cur), aid, "Again", "", "", 2026, text.Itoa(a))
	})
	testing.SetRealm(testing.NewUserRealm(carol))
	uassert.AbortsContains(t, cur, "only the artist", func() {
		CreateAlbum(cross(cur), aid, "Fake", "", "", 2026, text.Itoa(b))
	})

	// Public playlist in one signature.
	p := PublishPlaylist(cross(cur), "Late night", text.Itoa(b)+","+text.Itoa(a))
	uassert.Equal(t, 2, len(getPlaylist(rd(), p).Tracks))
	uassert.AbortsContains(t, cur, "duplicate", func() { PublishPlaylist(cross(cur), "Dup", text.Itoa(a)+","+text.Itoa(a)) })
	uassert.AbortsContains(t, cur, "unknown track", func() { PublishPlaylist(cross(cur), "Bad", text.Itoa(TrackCount()+1)) })
	UpdatePlaylist(cross(cur), p, "Late night v2", text.Itoa(a))
	uassert.Equal(t, "Late night v2", getPlaylist(rd(), p).Title)
	testing.SetRealm(testing.NewUserRealm(bob))
	uassert.AbortsContains(t, cur, "not your playlist", func() { UpdatePlaylist(cross(cur), p, "Mine", text.Itoa(a)) })

	urequire.True(t, strings.Contains(strings.ReplaceAll(AlbumJSON(al), " ", ""), `"tracks":[`+text.Itoa(a)+","+text.Itoa(b)+"]")) // ids are space-padded in storage
	urequire.True(t, strings.Contains(PlaylistJSON(p), `"title":"Late night v2"`))
	urequire.True(t, strings.Contains(UserJSON(carol), `"playlists":[`+text.Itoa(p)+`]`))
}

func TestModeration(cur realm, t *testing.T) {
	alice, aid := artist(cur, "alice")
	carol := who("carol")
	id := publish(cur, alice, "Song")
	testing.SetRealm(testing.NewUserRealm(carol))
	Report(cross(cur), "track", id, "broken link")
	rid := ReportPage(0, 1)[0]
	r, ok := GetReport(rid)
	uassert.True(t, ok)
	uassert.Equal(t, "broken link", r.Reason)
	uassert.Equal(t, carol, r.By)
	uassert.AbortsContains(t, cur, "kind must be", func() { Report(cross(cur), "x", id, "spam spam") })
	uassert.AbortsWithMessage(t, cur, "catalog: admin only", func() { HideTrack(cross(cur), id, true, "copyright") })

	testing.SetRealm(testing.NewUserRealm(boss))
	uassert.AbortsContains(t, cur, "reason must be", func() { HideTrack(cross(cur), id, true, "") })
	HideTrack(cross(cur), id, true, "copyright notice")
	_, _, _, ok = TrackBrief(id)
	uassert.False(t, ok)
	uassert.Equal(t, "Removed by moderation: copyright notice", HiddenNote("track", id))
	HideTrack(cross(cur), id, false, "")
	uassert.Equal(t, "", HiddenNote("track", id))
	HideArtist(cross(cur), aid, true, "impersonation")
	_, _, _, ok = TrackBrief(id)
	uassert.False(t, ok)
	uassert.False(t, ArtistVisible(aid))
	HideArtist(cross(cur), aid, false, "")

	AllowHost(cross(cur), "cdn.gnoradio.example", true)
	uassert.True(t, HostAllowed("cdn.gnoradio.example"))
	testing.SetOriginSend(ugnots(1))
	uassert.AbortsContains(t, cur, "does not take coins", func() { AllowHost(cross(cur), "cdn.gnoradio.example", false) })
	testing.SetOriginSend(nil)
	AllowHost(cross(cur), "cdn.gnoradio.example", false)
	uassert.False(t, HostAllowed("cdn.gnoradio.example"))
	urequire.True(t, strings.Contains(Info(), `"version":"1.0.0"`))
	urequire.True(t, strings.Contains(Info(), `"current":"gno.land/r/gnoradio/catalog/v1"`))
	urequire.True(t, strings.Contains(GenresJSON(), `"Cinematic & Classical"`))
}

func TestCuratedLicense(t *testing.T) {
	for in, want := range map[string]string{
		"CC0": "CC0-1.0", "CC-BY-3.0": "CC-BY-3.0", "cc-by-sa-3.0-de": "CC-BY-SA-3.0-DE", "CC-BY-4.0": "CC-BY-4.0",
		"CC-BY-NC-4.0": "", "CC-BY-ND-3.0": "", "CC-BY-5.0": "", "ALL-RIGHTS-RESERVED": "",
	} {
		uassert.Equal(t, want, curatedLicense(in), in)
	}
}

// The artist hides and shows their own work; what the moderator hid stays hidden.
func TestHideOwn(cur realm, t *testing.T) {
	alice, aid := artist(cur, "alice")
	id := publish(cur, alice, "Song")
	testing.SetRealm(testing.NewUserRealm(alice))
	HideOwn(cross(cur), "track", id, true)
	_, _, _, ok := TrackBrief(id)
	uassert.False(t, ok)
	uassert.Equal(t, "Hidden by the artist.", HiddenNote("track", id))
	uassert.AbortsContains(t, cur, "already hidden", func() { HideOwn(cross(cur), "track", id, true) })
	HideOwn(cross(cur), "track", id, false)
	_, _, _, ok = TrackBrief(id)
	uassert.True(t, ok)

	HideOwn(cross(cur), "artist", aid, true)
	uassert.False(t, ArtistVisible(aid))
	HideOwn(cross(cur), "artist", aid, false)
	uassert.True(t, ArtistVisible(aid))

	bob, _ := artist(cur, "bob")
	testing.SetRealm(testing.NewUserRealm(bob))
	uassert.AbortsContains(t, cur, "not your track", func() { HideOwn(cross(cur), "track", id, true) })
	uassert.AbortsContains(t, cur, "not your profile", func() { HideOwn(cross(cur), "artist", aid, true) })
	uassert.AbortsContains(t, cur, "kind must be", func() { HideOwn(cross(cur), "playlist", 1, true) })

	// The moderator overrides an artist's hide; the artist cannot undo it.
	testing.SetRealm(testing.NewUserRealm(alice))
	HideOwn(cross(cur), "track", id, true)
	testing.SetRealm(testing.NewUserRealm(boss))
	HideTrack(cross(cur), id, true, "copyright notice")
	testing.SetRealm(testing.NewUserRealm(alice))
	uassert.AbortsContains(t, cur, "hidden by the moderator", func() { HideOwn(cross(cur), "track", id, false) })
	testing.SetRealm(testing.NewUserRealm(boss))
	HideTrack(cross(cur), id, false, "")
	_, _, _, ok = TrackBrief(id)
	uassert.True(t, ok)
}
