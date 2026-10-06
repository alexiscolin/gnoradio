// Package catalog is the core of GnoRadio: artists, tracks, albums,
// playlists, likes, follows and tips. Other GnoRadio realms (radio, tickets,
// home) read it through the value getters in read.gno; it imports none of them.
//
// Three track origins share one catalog:
//   - "artist":  published by the artist's own wallet, tips enabled;
//   - "curated": imported by the admin from CC0 / CC BY / CC BY-SA sources;
//   - "audius":  selected by the admin from Audius, streamed under the Audius
//     Open Music License (session cache only, attribution required).
//
// Curated and Audius artists start unclaimed; once the admin assigns them to
// a wallet (AssignArtist), their tracks receive tips.
//
// Money never stays in this realm: tips are forwarded in the same transaction.
package catalog

import (
	"chain"
	"chain/runtime/unsafe"
	"strconv"
	"strings"
	"time"

	"gno.land/p/nt/avl/v0"
)

const (
	version = "0.3.0"
	denom   = "ugnot"
	ugnot   = 1_000_000

	OriginArtist  = "artist"
	OriginCurated = "curated"
	OriginAudius  = "audius"

	minTip         = 100_000           // 0.1 GNOT
	maxTip         = 1_000_000 * ugnot // keeps share math far from overflow
	maxSplits      = 4
	maxSplitPct    = 90 // the artist always keeps at least 10%
	earlyBadges    = 10
	minDuration    = 10
	maxDuration    = 1200
	maxPerArtist   = 500 // tracks per artist
	maxAlbumTracks = 40
	maxListTracks  = 200
	maxUserLists   = 50
	maxReports     = 5000 // open reports
	maxUserReports = 5    // open reports per reporter
	topSize        = 10
	maxSupportPct  = 50
)

// NumGenres is the size of the fixed genre list; genre ids are 1..NumGenres.
const NumGenres = 12

var genres = [NumGenres + 1]string{"",
	"Electronic", "Synthwave", "Ambient", "Techno & House", "Lo-fi & Chill", "Hip-hop & Beats",
	"Rock & Indie", "Pop", "Jazz & Soul", "Folk & Acoustic", "Cinematic & Classical", "World"}

// licenses an artist may pick; curated imports are limited to the first three.
var licenses = []string{
	"CC0-1.0", "CC-BY-4.0", "CC-BY-SA-4.0", "CC-BY-ND-4.0",
	"CC-BY-NC-4.0", "CC-BY-NC-SA-4.0", "CC-BY-NC-ND-4.0", "ALL-RIGHTS-RESERVED",
}

const audiusLicense = "Audius-OML"

const rightsTerms = "I own the rights to this recording and composition and grant GnoRadio a non-exclusive right to stream, broadcast and display it."

type Split struct {
	To  address
	Pct int64 // percent of each tip
}

type Artist struct {
	ID        int
	Owner     address // "" while unclaimed (curated / Audius)
	Kind      string  // artist | curated | audius
	Name      string
	Bio       string
	Source    string // curated: source page; audius: profile URL
	Joined    int64
	Tips      int64
	Followers int
	Tracks    []int
	Albums    []int
	Verified  bool
	Hidden    bool
}

type Track struct {
	ID          int
	Artist      int
	Origin      string
	Title       string
	Genre       int
	Duration    int64 // seconds
	License     string
	CMO         string // none | sacem-nc
	Credits     string
	Audio       string // ipfs://… ar://… audius:… https://…
	AudioSHA    string // sha256 hex, required for https
	Cover       string
	CoverSHA    string
	SourceURL   string
	Attribution string
	Splits      []Split
	Album       int
	Created     int64
	Likes       int
	Tips        int64
	Supporters  int
	Hidden      bool
	Early       []address // first listeners to like it
}

type Album struct {
	ID       int
	Artist   int
	Title    string
	Cover    string
	CoverSHA string
	Year     int
	Tracks   []int
	Created  int64
	Hidden   bool
}

type Playlist struct {
	ID      int
	Owner   address
	Title   string
	Tracks  []int
	Updated int64
	Hidden  bool
}

// User groups everything a listener writes, so a like or a follow only
// touches that listener's own records.
type User struct {
	Likes     avl.Tree // padded track id -> true
	NLikes    int
	Follows   avl.Tree // padded artist id -> true
	NFollows  int
	Tipped    int64
	tipped    avl.Tree // padded track id -> true (distinct supporters)
	Playlists []int
	Reports   int // open reports filed by this user
}

type ReportInfo struct {
	ID     int
	Kind   string // track | album | artist | playlist
	Target string
	Reason string
	By     address
	At     int64
}

type Rank struct {
	Key   string
	Value int64
}

var (
	admin     address
	frozen    bool
	successor string

	artists   avl.Tree // padded id -> *Artist
	byOwner   avl.Tree // owner address -> artist id
	names     avl.Tree // lowercased artist name -> artist id
	tracks    avl.Tree // padded id -> *Track
	albums    avl.Tree // padded id -> *Album
	playlists avl.Tree // padded id -> *Playlist
	users     avl.Tree // address -> *User
	reports   avl.Tree // padded id -> *Report
	hosts     avl.Tree // allowed https hosts -> true

	nArtists, nTracks, nAlbums, nPlaylists, nReports int
	openReports                                      int // reports not yet resolved

	topLiked   []Rank // track ids by likes
	topArtists []Rank // artist ids by tips
	topFans    []Rank // addresses by tipped
)

func init() {
	admin = unsafe.OriginCaller()
	treasury = admin
	for _, h := range []string{"archive.org", "upload.wikimedia.org"} {
		hosts.Set(h, true)
	}
}

// ---- helpers shared by every file ----

func now() int64 { return time.Now().Unix() }

func key(id int) string {
	s := strconv.Itoa(id)
	return strings.Repeat("0", 10-len(s)) + s
}

func itoa(n int) string     { return strconv.Itoa(n) }
func itoa64(n int64) string { return strconv.FormatInt(n, 10) }

func userCaller(cur realm) address {
	if !cur.Previous().IsUserCall() {
		panic("catalog: call this directly from your wallet")
	}
	return cur.Previous().Address()
}

func onlyAdmin(cur realm) {
	if cur.Previous().Address() != admin {
		panic("catalog: admin only")
	}
	noPayment()
}

func notFrozen() {
	if frozen {
		panic("catalog: GnoRadio is paused for an upgrade")
	}
}

func noPayment() {
	if len(unsafe.OriginSend()) != 0 {
		panic("catalog: this action does not take coins")
	}
}

// paid returns the ugnot attached to the call; anything else is refused.
func paid() int64 {
	sent := unsafe.OriginSend()
	if len(sent) != 1 || sent[0].Denom != denom || sent[0].Amount <= 0 {
		panic("catalog: attach an amount in ugnot")
	}
	return sent[0].Amount
}

func getArtist(id int) *Artist {
	if a, ok := artists.Get(key(id)).(*Artist); ok {
		return a
	}
	return nil
}

func getTrack(id int) *Track {
	if t, ok := tracks.Get(key(id)).(*Track); ok {
		return t
	}
	return nil
}

func getAlbum(id int) *Album {
	if a, ok := albums.Get(key(id)).(*Album); ok {
		return a
	}
	return nil
}

func getPlaylist(id int) *Playlist {
	if p, ok := playlists.Get(key(id)).(*Playlist); ok {
		return p
	}
	return nil
}

func artistOf(owner address) int {
	if id, ok := byOwner.Get(owner.String()).(int); ok {
		return id
	}
	return 0
}

func visibleArtist(a *Artist) bool { return a != nil && !a.Hidden }

func playable(t *Track) bool {
	return t != nil && !t.Hidden && visibleArtist(getArtist(t.Artist))
}

func mustArtist(id int) *Artist {
	a := getArtist(id)
	if !visibleArtist(a) {
		panic("catalog: unknown artist")
	}
	return a
}

func mustTrack(id int) *Track {
	t := getTrack(id)
	if !playable(t) {
		panic("catalog: unknown track")
	}
	return t
}

// ownArtist returns the caller's artist profile.
func ownArtist(caller address) *Artist {
	a := getArtist(artistOf(caller))
	if !visibleArtist(a) {
		panic("catalog: create your artist profile first")
	}
	return a
}

// mayEdit reports whether caller manages artist a: its owner, or the admin
// while the artist is unclaimed.
func mayEdit(caller address, a *Artist) bool {
	if a.Owner != "" {
		return caller == a.Owner
	}
	return caller == admin
}

func user(addr address) *User {
	if u, ok := users.Get(addr.String()).(*User); ok {
		return u
	}
	u := &User{}
	users.Set(addr.String(), u)
	return u
}

// updateTop keeps a short leaderboard sorted by value, highest first.
func updateTop(list []Rank, k string, v int64) []Rank {
	out := make([]Rank, 0, topSize+1)
	for _, r := range list {
		if r.Key != k {
			out = append(out, r)
		}
	}
	i := len(out)
	for i > 0 && out[i-1].Value < v {
		i--
	}
	if i >= topSize {
		return out
	}
	out = append(out, Rank{})
	copy(out[i+1:], out[i:])
	out[i] = Rank{k, v}
	if len(out) > topSize {
		out = out[:topSize]
	}
	return out
}

func appendCapped(list []int, id, max int, what string) []int {
	if len(list) >= max {
		panic("catalog: " + what + " limit reached")
	}
	return append(list, id)
}

func emitEvent(name string, kv ...string) { chain.Emit(name, kv...) }
