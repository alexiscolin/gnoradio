package catalog

import (
	"strings"

	"gno.land/p/gnoradio/store/v0"
	"gno.land/p/gnoradio/text/v0"
)

// RegisterArtist creates or updates the caller's artist profile. Names use
// Latin letters so look-alike names in other scripts cannot impersonate.
func RegisterArtist(cur realm, name, bio string) int {
	caller := userCaller(cur)
	noPayment()
	notFrozen()
	name, bio = strings.TrimSpace(name), strings.TrimSpace(bio)
	mustName(name)
	mustText("bio", bio, 0, 280)

	if id := artistOf(caller); id != 0 {
		a := getArtist(id)
		rename(a, name)
		a.Bio = bio
		putArtist(a)
		emitEvent("ArtistUpdated", "id", itoa(id), "name", name)
		return id
	}
	a := newArtist(OriginArtist, name, bio, "")
	a.Owner = caller
	putArtist(a)
	byOwner.Set(caller.String(), itoa(a.ID))
	emitEvent("ArtistRegistered", "id", itoa(a.ID), "owner", caller.String(), "name", name)
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
	mustText("bio", bio, 0, 280)
	if source != "" && !validHTTPS(source) {
		panic("catalog: source must be an https link")
	}
	a := newArtist(kind, name, bio, source)
	emitEvent("ArtistCreated", "id", itoa(a.ID), "kind", kind, "name", name)
	return a.ID
}

// AssignArtist hands an unclaimed artist to the wallet that proved it owns
// the profile (claim checked off-chain). Their tracks then receive tips.
func AssignArtist(cur realm, artistID int, owner address) {
	onlyAdmin(cur)
	a := mustArtist(artistID)
	if a.Owner != "" {
		panic("catalog: artist already claimed")
	}
	if !owner.IsValid() || artistOf(owner) != 0 {
		panic("catalog: this wallet is invalid or already has an artist profile")
	}
	a.Owner = owner
	a.Verified = true
	putArtist(a)
	claims.Remove(text.Key(a.ID))
	byOwner.Set(owner.String(), itoa(a.ID))
	recordActivity("claim", owner, 0, a.ID, 0)
	emitEvent("ArtistClaimed", "id", itoa(a.ID), "owner", owner.String())
}

// Follow and Unfollow an artist.
func Follow(cur realm, artistID int) {
	caller := userCaller(cur)
	noPayment()
	notFrozen()
	a := mustArtist(artistID)
	if a.Owner == caller {
		panic("catalog: you cannot follow yourself")
	}
	u := user(caller)
	follows, ok := store.Add(u.Follows, artistID)
	if !ok {
		panic("catalog: already following")
	}
	u.Follows = follows
	putUser(caller, u)
	a.Followers++
	putArtist(a)
	recordActivity("follow", caller, 0, artistID, 0)
	emitEvent("Followed", "artist", itoa(artistID), "by", caller.String())
}

func Unfollow(cur realm, artistID int) {
	caller := userCaller(cur)
	noPayment()
	notFrozen()
	u := user(caller)
	follows, ok := store.Remove(u.Follows, artistID)
	if !ok {
		panic("catalog: not following")
	}
	u.Follows = follows
	putUser(caller, u)
	if a := getArtist(artistID); a != nil && a.Followers > 0 {
		a.Followers--
		putArtist(a)
	}
	emitEvent("Unfollowed", "artist", itoa(artistID), "by", caller.String())
}

func newArtist(kind, name, bio, source string) *Artist {
	k := skeleton(name)
	if names.Has(k) {
		panic("catalog: this artist name is already taken")
	}
	nArtists++
	a := &Artist{ID: nArtists, Kind: kind, Name: name, Bio: bio, Source: source, Joined: now()}
	artists.Append(artistRecord(a))
	artistLists.Append(store.Rec("", ""))
	names.Set(k, itoa(a.ID))
	return a
}

// rename moves the artist to a new name and frees the old one (the caller
// saves a). A hidden artist keeps its name so it cannot dodge moderation.
func rename(a *Artist, name string) {
	k, old := skeleton(name), skeleton(a.Name)
	if k == old {
		a.Name = name
		return
	}
	if a.Hidden {
		panic("catalog: a hidden artist cannot change its name")
	}
	if id, ok := names.Get(k); ok && atoi(id) != a.ID {
		panic("catalog: this artist name is already taken")
	}
	names.Set(k, itoa(a.ID))
	if id, ok := names.Get(old); ok && atoi(id) == a.ID {
		names.Remove(old)
	}
	a.Name = name
	if a.Verified {
		emitEvent("Verified", "artist", itoa(a.ID), "verified", "false")
	}
	a.Verified = false
	// A pending claim was checked for the old name: a rename must not inherit it.
	claims.Remove(text.Key(a.ID))
}

// ReleaseName frees a reserved name no visible artist is using. Admin only.
func ReleaseName(cur realm, name string) {
	onlyAdmin(cur)
	k := skeleton(strings.TrimSpace(name))
	v, ok := names.Get(k)
	if !ok {
		panic("catalog: this name is not reserved")
	}
	if a := getArtist(atoi(v)); a != nil && !a.Hidden && skeleton(a.Name) == k {
		panic("catalog: this name belongs to a visible artist")
	}
	names.Remove(k)
	emitEvent("NameReleased", "name", k)
}
