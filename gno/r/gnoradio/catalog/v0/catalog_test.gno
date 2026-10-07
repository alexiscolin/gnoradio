package catalog

import (
	"chain"
	"chain/banker"
	"crypto/ed25519"
	"strings"
	"testing"

	"gno.land/p/gnoradio/store/v0"
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
	boss  = testutils.TestAddress("boss")
)

var realmAddr = chain.PackageAddress("gno.land/r/gnoradio/catalog/v0")

const (
	cid  = "bafybeigdyrzt5sfp7udm7hu76uh7y26nf3efuylqabf3oclgtqy55fbzdi"
	ipfs = "ipfs://" + cid
	sha  = "9f86d081884c7d659a2feaa0c55ad015a3bf4f1b2b0b822cd15d6c15b0f00a08"
	ia   = "https://archive.org/download/komiku-dreams/01-Dreams.mp3"
)

func reset() {
	artists, artistLists, tracks, albums, playlists = store.NewSeq(16), store.NewSeq(8), store.NewSeq(16), store.NewSeq(16), store.NewSeq(16)
	byOwner, names, users, userRecs = store.NewMap(128), store.NewMap(128), store.NewMap(256), store.NewSeq(16)
	likeSets = store.NewMap(256)
	reports, hosts, removed = avl.Tree{}, avl.Tree{}, store.NewMap(16)
	byGenre = [NumGenres + 1]store.IDs{}
	hosts.Set("archive.org", true)
	nArtists, nTracks, nAlbums, nPlaylists, nReports, openReports = 0, 0, 0, 0, 0, 0
	topLiked, topArtists, topFans = nil, nil, nil
	frozen, successor = false, ""
	admin = boss
	botKey, claims, proofs = nil, avl.Tree{}, avl.Tree{}
	radioRealm = "gno.land/r/gnoradio/radio/v0"
	budgets, walletDay, promoHeld = store.NewMap(16), store.NewMap(16), 0
	siblingRealms = []string{radioRealm, "gno.land/r/gnoradio/tickets/v0", "gno.land/r/gnoradio/home/v0"}
	verifySig = ed25519.Verify
}

// verified marks an artist as verified, as FinalizeClaim would (verify_test covers the flow).
func verified(cur realm, artistID int) {
	testing.SetRealm(testing.NewUserRealm(admin))
	Verify(cross(cur), artistID, true)
}

func ugnots(n int64) chain.Coins { return chain.Coins{{Denom: denom, Amount: n}} }

func balance(addr address) int64 { return banker.NewReadonlyBanker().GetCoins(addr).AmountOf(denom) }

func publish(cur realm, title string) int {
	return PublishTrack(cross(cur), title, 2, "3:30", "cc by", "none", "", ipfs, "", "", "", "", "yes")
}

func TestArtistAndPublish(cur realm, t *testing.T) {
	reset()
	testing.SetRealm(testing.NewUserRealm(alice))
	aid := RegisterArtist(cross(cur), "Lea Kosmos", "Night synthwave from Lyon.")
	uassert.Equal(t, 1, aid)
	id := PublishTrack(cross(cur), "Neon Rivers", 2, "4:02", "cc by", "none", "Lea Kosmos, mix Moko", ia, sha, "", "", carol.String()+":30", "yes")
	tr := getTrack(id)
	uassert.Equal(t, "CC-BY-4.0", tr.License)
	uassert.Equal(t, int64(242), tr.Duration)
	uassert.Equal(t, OriginArtist, tr.Origin)
	uassert.Equal(t, 1, TrackCount())
	a, g, d, ok := TrackBrief(id)
	uassert.Equal(t, 1, a)
	uassert.Equal(t, 2, g)
	uassert.Equal(t, int64(242), d)
	uassert.True(t, ok)
	uassert.Equal(t, alice, ArtistOwner(1))
	uassert.Equal(t, 1, ArtistOf(alice))
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
	uassert.AbortsContains(t, cur, "already taken", func() { RegisterArtist(cross(cur), "lea kosmos", "") })
	uassert.AbortsContains(t, cur, "Latin letters", func() { RegisterArtist(cross(cur), "Lеa", "") }) // Cyrillic е
	uassert.AbortsContains(t, cur, "artist profile first", func() { publish(cur, "Nope") })
	testing.SetRealm(testing.NewUserRealm(alice))
	RegisterArtist(cross(cur), "Lea K", "")
	uassert.Equal(t, 0, ArtistByName("Lea Kosmos"))
	testing.SetRealm(testing.NewUserRealm(bob))

	// Edit by the artist only.
	testing.SetRealm(testing.NewUserRealm(alice))
	EditTrack(cross(cur), id, "Neon Rivers radio edit", 1, "3:30", "", ipfs, "", "", "")
	uassert.Equal(t, int64(210), getTrack(id).Duration)
	uassert.Equal(t, 1, getTrack(id).Genre)
	testing.SetRealm(testing.NewUserRealm(carol))
	uassert.AbortsContains(t, cur, "only the artist", func() {
		EditTrack(cross(cur), id, "Hijack", 1, "1:00", "", ipfs, "", "", "")
	})
}

func TestCuratedAudiusAndClaim(cur realm, t *testing.T) {
	reset()
	testing.SetRealm(testing.NewUserRealm(carol))
	uassert.AbortsWithMessage(t, cur, "catalog: admin only", func() {
		CreateArtist(cross(cur), OriginCurated, "Komiku", "", "https://archive.org/details/komiku")
	})
	testing.SetRealm(testing.NewUserRealm(boss))
	k := CreateArtist(cross(cur), OriginCurated, "Komiku", "French composer.", "https://archive.org/details/komiku")
	au := CreateArtist(cross(cur), OriginAudius, "Night Tapes", "", "https://audius.co/nighttapes")
	t1 := ImportTrack(cross(cur), k, "Dreams", 5, "2:58", "CC0", "Komiku", ia, sha, "", "",
		"https://archive.org/details/komiku-dreams", "Komiku, CC0 1.0, via archive.org")
	uassert.Equal(t, OriginCurated, getTrack(t1).Origin)
	uassert.AbortsContains(t, cur, "CC0, CC BY or CC BY-SA", func() {
		ImportTrack(cross(cur), k, "X", 5, "2:00", "CC-BY-NC", "", ia, sha, "", "", "https://archive.org/details/x", "Komiku")
	})
	t2 := ImportTrack(cross(cur), au, "Midnight Drive", 1, "3:41", "", "", "audius:Dk3aQ", "", "", "",
		"https://audius.co/nighttapes/midnight-drive", "Night Tapes, Audius Open Music License")
	uassert.Equal(t, AudiusLicense, getTrack(t2).License)
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
	uassert.True(t, getArtist(k).Verified)
	uassert.AbortsContains(t, cur, "already claimed", func() { AssignArtist(cross(cur), k, bob) })
	testing.SetOriginSend(ugnots(ugnot))
	testing.SetRealm(testing.NewUserRealm(carol))
	Tip(cross(cur), t1)
	uassert.Equal(t, int64(ugnot), balance(dave))
	testing.SetOriginSend(nil)
}

func TestTipSplitsAndGuards(cur realm, t *testing.T) {
	reset()
	testing.SetRealm(testing.NewUserRealm(alice))
	RegisterArtist(cross(cur), "Alice", "")
	id := PublishTrack(cross(cur), "Song", 2, "1:40", "CC-BY", "none", "", ipfs, "", "", "", bob.String()+":30", "yes")
	verified(cur, 1)

	testing.IssueCoins(realmAddr, ugnots(20*ugnot))
	testing.SetOriginSend(ugnots(10 * ugnot))
	testing.SetRealm(testing.NewUserRealm(carol))
	Tip(cross(cur), id)
	Tip(cross(cur), id)
	uassert.Equal(t, int64(14*ugnot), balance(alice))
	uassert.Equal(t, int64(6*ugnot), balance(bob))
	uassert.Equal(t, int64(0), balance(realmAddr))
	uassert.Equal(t, 1, getTrack(id).Supporters)
	uassert.Equal(t, int64(20*ugnot), getArtist(1).Tips)
	uassert.Equal(t, "1", topArtists[0].Key)
	uassert.Equal(t, carol.String(), topFans[0].Key)

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
	reset()
	testing.SetRealm(testing.NewUserRealm(alice))
	RegisterArtist(cross(cur), "Alice", "")
	a := publish(cur, "One")
	b := publish(cur, "Two")
	uassert.AbortsContains(t, cur, "own track", func() { Like(cross(cur), a) })
	uassert.AbortsContains(t, cur, "follow yourself", func() { Follow(cross(cur), 1) })

	testing.SetRealm(testing.NewUserRealm(carol))
	Like(cross(cur), a)
	uassert.AbortsContains(t, cur, "already liked", func() { Like(cross(cur), a) })
	Follow(cross(cur), 1)
	uassert.Equal(t, 1, getArtist(1).Followers)
	uassert.Equal(t, a, LikedPage(carol, 0, 1)[0])
	uassert.Equal(t, 1, FollowsPage(carol, 0, 1)[0])
	uassert.Equal(t, carol, getTrack(a).Early[0])
	Unlike(cross(cur), a)
	uassert.Equal(t, 0, getTrack(a).Likes)
	Unfollow(cross(cur), 1)
	uassert.Equal(t, 0, getArtist(1).Followers)

	// Album by its artist.
	testing.SetRealm(testing.NewUserRealm(alice))
	al := CreateAlbum(cross(cur), 1, "First Light", "", "", 2026, itoa(a)+","+itoa(b))
	uassert.Equal(t, al, getTrack(b).Album)
	uassert.AbortsContains(t, cur, "duplicate", func() {
		CreateAlbum(cross(cur), 1, "Twice", "", "", 2026, itoa(a)+","+itoa(a))
	})
	uassert.AbortsContains(t, cur, "already in an album", func() {
		CreateAlbum(cross(cur), 1, "Again", "", "", 2026, itoa(a))
	})
	testing.SetRealm(testing.NewUserRealm(carol))
	uassert.AbortsContains(t, cur, "only the artist", func() {
		CreateAlbum(cross(cur), 1, "Fake", "", "", 2026, itoa(b))
	})

	// Public playlist in one signature.
	p := PublishPlaylist(cross(cur), "Late night", itoa(b)+","+itoa(a))
	uassert.Equal(t, 2, len(getPlaylist(p).Tracks))
	uassert.AbortsContains(t, cur, "duplicate", func() { PublishPlaylist(cross(cur), "Dup", itoa(a)+","+itoa(a)) })
	uassert.AbortsContains(t, cur, "unknown track", func() { PublishPlaylist(cross(cur), "Bad", "999") })
	UpdatePlaylist(cross(cur), p, "Late night v2", itoa(a))
	uassert.Equal(t, "Late night v2", getPlaylist(p).Title)
	testing.SetRealm(testing.NewUserRealm(bob))
	uassert.AbortsContains(t, cur, "not your playlist", func() { UpdatePlaylist(cross(cur), p, "Mine", itoa(a)) })

	urequire.True(t, strings.Contains(strings.ReplaceAll(AlbumJSON(al), " ", ""), `"tracks":[1,2]`)) // ids are space-padded in storage
	urequire.True(t, strings.Contains(PlaylistJSON(p), `"title":"Late night v2"`))
	urequire.True(t, strings.Contains(UserJSON(carol), `"playlists":[1]`))
}

func TestModeration(cur realm, t *testing.T) {
	reset()
	testing.SetRealm(testing.NewUserRealm(alice))
	RegisterArtist(cross(cur), "Alice", "")
	id := publish(cur, "Song")
	testing.SetRealm(testing.NewUserRealm(carol))
	Report(cross(cur), "track", id, "broken link")
	r, ok := GetReport(1)
	uassert.True(t, ok)
	uassert.Equal(t, "broken link", r.Reason)
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
	HideArtist(cross(cur), 1, true, "impersonation")
	_, _, _, ok = TrackBrief(id)
	uassert.False(t, ok)
	uassert.False(t, ArtistVisible(1))
	HideArtist(cross(cur), 1, false, "")

	AllowHost(cross(cur), "cdn.gnoradio.example", true)
	uassert.True(t, HostAllowed("cdn.gnoradio.example"))
	Freeze(cross(cur), true)
	testing.SetRealm(testing.NewUserRealm(carol))
	uassert.AbortsContains(t, cur, "paused", func() { RegisterArtist(cross(cur), "Carol", "") })
	testing.SetRealm(testing.NewUserRealm(boss))
	testing.SetOriginSend(ugnots(1))
	uassert.AbortsContains(t, cur, "does not take coins", func() { Freeze(cross(cur), false) })
	testing.SetOriginSend(nil)
	TransferAdmin(cross(cur), alice)
	uassert.Equal(t, alice, Admin())
	urequire.True(t, strings.Contains(Info(), `"version":"0.3.0"`))
	urequire.True(t, strings.Contains(GenresJSON(), `"Cinematic & Classical"`))
}

// Scale: the cost of a like and of a publish must not grow with the catalog.
// Compare the GAS lines of TestScaleSmall and TestScaleLarge.
func seedTracks(cur realm, n int) {
	reset()
	testing.SetRealm(testing.NewUserRealm(alice))
	RegisterArtist(cross(cur), "Alice", "")
	for i := 0; i < n; i++ {
		if i > 0 && i%maxPerArtist == 0 {
			testing.SetRealm(testing.NewUserRealm(testutils.TestAddress("artist" + itoa(i))))
			RegisterArtist(cross(cur), "Artist "+itoa(i), "")
		}
		publish(cur, "Song "+itoa(i))
	}
}

func TestScaleSmall(cur realm, t *testing.T) {
	seedTracks(cur, 10)
	testing.SetRealm(testing.NewUserRealm(carol))
	for i := 1; i <= 10; i++ {
		Like(cross(cur), i)
	}
}

func TestScaleLarge(cur realm, t *testing.T) {
	seedTracks(cur, 2000)
	testing.SetRealm(testing.NewUserRealm(carol))
	for i := 1991; i <= 2000; i++ {
		Like(cross(cur), i)
	}
	uassert.Equal(t, 2000, TrackCount())
	uassert.Equal(t, 50, len(TrackPage(0, 50, true)))
	urequire.True(t, len(TracksJSON(1000, 50)) > 0)
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
	reset()
	testing.SetRealm(testing.NewUserRealm(alice))
	RegisterArtist(cross(cur), "Alice", "")
	id := publish(cur, "Song")
	HideOwn(cross(cur), "track", id, true)
	_, _, _, ok := TrackBrief(id)
	uassert.False(t, ok)
	uassert.Equal(t, "Hidden by the artist.", HiddenNote("track", id))
	uassert.AbortsContains(t, cur, "already hidden", func() { HideOwn(cross(cur), "track", id, true) })
	HideOwn(cross(cur), "track", id, false)
	_, _, _, ok = TrackBrief(id)
	uassert.True(t, ok)

	HideOwn(cross(cur), "artist", 1, true)
	uassert.False(t, ArtistVisible(1))
	HideOwn(cross(cur), "artist", 1, false)
	uassert.True(t, ArtistVisible(1))

	testing.SetRealm(testing.NewUserRealm(bob))
	RegisterArtist(cross(cur), "Bob", "")
	uassert.AbortsContains(t, cur, "not your track", func() { HideOwn(cross(cur), "track", id, true) })
	uassert.AbortsContains(t, cur, "not your profile", func() { HideOwn(cross(cur), "artist", 1, true) })
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
