package catalog

import (
	"strings"

	"gno.land/p/gnoradio/role/v0"
	"gno.land/p/gnoradio/store/v0"
	"gno.land/p/gnoradio/text/v0"
	"gno.land/r/gnoradio/data"
)

// RegisterArtist creates or updates the caller's artist profile. Names use
// Latin letters so look-alike names in other scripts cannot impersonate.
func RegisterArtist(cur realm, name, bio string) int {
	caller := userCaller(cur)
	noPayment()
	name, bio = strings.TrimSpace(name), strings.TrimSpace(bio)
	mustText("bio", bio, 0, maxBio)
	t := rd()
	id := artistOf(t, caller)
	if id != 0 {
		a := getArtist(t, id)
		if name != a.Name { // a kept name stays valid when the reserved list grows
			mustName(name)
		}
		rename(t, a, name)
		a.Bio = bio
		t.setRec(cArtists, id, fits(artistRecord(a)))
		save(cur, t)
		emitEvent("ArtistUpdated", "id", text.Itoa(id), "name", name)
		return id
	}
	mustName(name)
	a := newArtist(t, OriginArtist, name, bio, "", caller)
	t.set(cOwners, caller.String(), text.Itoa(a.ID))
	save(cur, t)
	emitEvent("ArtistRegistered", "id", text.Itoa(a.ID), "owner", caller.String(), "name", name)
	return a.ID
}

// CreateArtist adds an unclaimed curated or Audius artist. Admin only.
// source is the artist's page at the source (https), shown for attribution.
func CreateArtist(cur realm, kind, name, bio, source string) int {
	onlyAdmin(cur)
	if kind != OriginCurated && kind != OriginAudius {
		panic("catalog: kind must be curated or audius")
	}
	name, bio, source = strings.TrimSpace(name), strings.TrimSpace(bio), strings.TrimSpace(source)
	mustName(name)
	mustText("bio", bio, 0, maxBio)
	if source != "" && !text.HTTPS(source, 300) {
		panic("catalog: source must be an https link")
	}
	t := rd()
	a := newArtist(t, kind, name, bio, source, "")
	save(cur, t)
	emitEvent("ArtistCreated", "id", text.Itoa(a.ID), "kind", kind, "name", name)
	return a.ID
}

// AssignArtist hands an unclaimed artist to the wallet that proved it owns
// the profile (claim checked off-chain). Their tracks then receive tips.
func AssignArtist(cur realm, artistID int, owner address) {
	onlyAdmin(cur)
	t := rd()
	a := mustArtist(t, artistID)
	if a.Owner != "" {
		panic("catalog: artist already claimed")
	}
	if !role.Canonical(owner) || data.IsGnoRadio(owner) || artistOf(t, owner) != 0 {
		panic("catalog: this wallet is invalid or already has an artist profile")
	}
	a.Owner, a.Verified = owner, true
	putArtist(t, a)
	t.del(cClaims, store.Pad(a.ID))
	t.set(cOwners, owner.String(), text.Itoa(a.ID))
	t.activity("claim", owner, "0", text.Itoa(a.ID), "0")
	save(cur, t)
	emitEvent("ArtistClaimed", "id", text.Itoa(a.ID), "owner", owner.String())
}

// Follow and Unfollow an artist.
func Follow(cur realm, artistID int) {
	caller := userCaller(cur)
	noPayment()
	t := rd()
	a := mustArtist(t, artistID)
	if a.Owner == caller {
		panic("catalog: you cannot follow yourself")
	}
	u := user(t, caller)
	follows, ok := store.Add(u.Follows, artistID)
	if !ok {
		panic("catalog: already following")
	}
	if store.Count(u.Follows) >= maxFollows {
		panic("catalog: follows limit reached")
	}
	u.Follows = follows
	putUser(t, caller, u)
	a.Followers++
	putArtist(t, a)
	t.activityOnce("follow", caller, "0", text.Itoa(artistID))
	save(cur, t)
	emitEvent("Followed", "artist", text.Itoa(artistID), "by", caller.String())
}

func Unfollow(cur realm, artistID int) {
	caller := userCaller(cur)
	noPayment()
	t := rd()
	u := user(t, caller)
	follows, ok := store.Remove(u.Follows, artistID)
	if !ok {
		panic("catalog: not following")
	}
	u.Follows = follows
	putUser(t, caller, u)
	if a := getArtist(t, artistID); a != nil && a.Followers > 0 {
		a.Followers--
		putArtist(t, a)
	}
	save(cur, t)
	emitEvent("Unfollowed", "artist", text.Itoa(artistID), "by", caller.String())
}

func newArtist(t *tx, kind, name, bio, source string, owner address) *Artist {
	k := skeleton(name)
	if _, taken := t.get(cNames, k); taken {
		panic("catalog: this artist name is already taken")
	}
	a := &Artist{ID: int(t.bump(mArtists, 1)), Owner: owner, Kind: kind, Name: name, Bio: bio, Source: source, Joined: now()}
	t.addRec(cArtists, a.ID, fits(artistRecord(a)))
	t.set(cNames, k, text.Itoa(a.ID))
	return a
}

// rename moves the artist to a new name and frees the old one (the caller
// saves a). A hidden artist keeps its name so it cannot dodge moderation.
func rename(t *tx, a *Artist, name string) {
	k, old := skeleton(name), skeleton(a.Name)
	if k == old {
		a.Name = name
		return
	}
	if a.Hidden {
		panic("catalog: a hidden artist cannot change its name")
	}
	if id, ok := t.get(cNames, k); ok && text.Atoi(id) != a.ID {
		panic("catalog: this artist name is already taken")
	}
	t.set(cNames, k, text.Itoa(a.ID))
	if id, ok := t.get(cNames, old); ok && text.Atoi(id) == a.ID {
		t.del(cNames, old)
	}
	a.Name = name
	if a.Verified {
		emitEvent("Verified", "artist", text.Itoa(a.ID), "verified", "false")
	}
	a.Verified = false
	// A pending claim was checked for the old name: a rename must not inherit
	// it, nor the old proof (a later Verify by the admin shows no host).
	t.del(cClaims, store.Pad(a.ID))
	t.del(cProofs, store.Pad(a.ID))
}

// ReleaseName frees a reserved name no visible artist is using. Admin only.
func ReleaseName(cur realm, name string) {
	onlyAdmin(cur)
	t := rd()
	k := skeleton(strings.TrimSpace(name))
	v, ok := t.get(cNames, k)
	if !ok {
		panic("catalog: this name is not reserved")
	}
	if a := getArtist(t, text.Atoi(v)); a != nil && !a.Hidden && skeleton(a.Name) == k {
		panic("catalog: this name belongs to a visible artist")
	}
	t.del(cNames, k)
	save(cur, t)
	emitEvent("NameReleased", "name", k)
}
