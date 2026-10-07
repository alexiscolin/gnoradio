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
// Tips and support are forwarded in the same transaction; the only coins this
// realm keeps are the artists' promo budgets, accounted in sponsor.gno.
package catalog

import (
	"chain"
	"chain/runtime/unsafe"
	"strconv"
	"time"

	"gno.land/p/gnoradio/store/v0"

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
	likeRange      = 9 // likes are kept per range of 1<<likeRange track ids
)

// NumGenres is the size of the fixed genre list; genre ids are 1..NumGenres.
const NumGenres = 20

var genres = [NumGenres + 1]string{"",
	"Electronica", "Synthwave", "Ambient", "Techno", "House", "Drum & Bass", "Dubstep & Trap",
	"Lo-fi Beats", "Hip-hop & Rap", "R&B & Soul", "Rock & Indie", "Metal & Punk", "Pop",
	"Jazz & Blues", "Folk & Acoustic", "Cinematic & Classical", "World", "Latin", "Reggae & Dub", "Funk & Disco"}

// licenses an artist may pick; curated imports are limited to the first three.
var licenses = []string{
	"CC0-1.0", "CC-BY-4.0", "CC-BY-SA-4.0", "CC-BY-ND-4.0",
	"CC-BY-NC-4.0", "CC-BY-NC-SA-4.0", "CC-BY-NC-ND-4.0", "ALL-RIGHTS-RESERVED",
}

// AudiusLicense is the license id of tracks streamed from Audius.
const AudiusLicense = "Audius-OML"

const rightsTerms = "I own or control the rights to this recording and its composition, or hold a licence that allows this, and I grant the operator of GnoRadio and its users a worldwide, non-exclusive, royalty-free licence to store, stream, broadcast and display it through GnoRadio and gno.land for as long as it is published."

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
	list     string // Tracks as stored (JSON-ready)
}

type Playlist struct {
	ID      int
	Owner   address
	Title   string
	Tracks  []int
	Updated int64
	Hidden  bool
	list    string // Tracks as stored (JSON-ready)
}

// User groups what a listener writes, so a follow only touches that
// listener's own record. Id sets are sorted packed lists (see store): 9 bytes
// per follow. Likes live apart (likeSets), in ranges of 512 track ids, so a
// like rewrites at most one 4.6KB list whatever the listener's total, and a
// heavy liker never weighs on the listeners stored next to them.
type User struct {
	Follows   string // sorted packed artist ids
	Tipped    int64
	tipped    string // sorted packed track ids (distinct supporters)
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

// Storage is compact (see records.gno): on gno.land each stored byte costs a
// 100 ugnot deposit, and an avl node or a struct costs about 2KB on its own.
// Tracks, artists, albums and playlists are string records in chunked
// sequences (index = id-1); per-key indexes are hashed maps; id lists are
// packed 8-digit strings.
var (
	admin     address
	frozen    bool
	successor string

	// Chunks of 16: a write rewrites one chunk (2-5KB, about 45k gas per KB)
	// plus one small node per tree level. Buckets are sparse and sized for the
	// largest expected collection (about 16 entries each at that size).
	artists     = store.NewSeq(16)   // artist head records
	artistLists = store.NewSeq(8)    // per artist: track id list, album id list
	byOwner     = store.NewMap(8192) // owner address -> artist id
	names       = store.NewMap(8192) // name skeleton -> artist id
	tracks      = store.NewSeq(16)   // track records
	byGenre     [NumGenres + 1]store.IDs
	albums      = store.NewSeq(16)    // album records
	playlists   = store.NewSeq(16)    // playlist records
	users       = store.NewMap(65536) // address -> index in userRecs
	userRecs    = store.NewSeq(16)    // listener records
	likeSets    = store.NewMap(65536) // address + "/" + track id>>likeRange -> the listener's likes in that range (sorted packed)
	reports     avl.Tree              // padded id -> *ReportInfo (bounded, removed when resolved)
	removed     = store.NewMap(256)   // "kind:id" of hidden content -> the moderator's reason, "" if its artist hid it
	hosts       avl.Tree              // allowed https hosts -> true

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

func artistOf(owner address) int {
	v, _ := byOwner.Get(owner.String())
	return atoi(v)
}

func visibleArtist(a *Artist) bool { return a != nil && !a.Hidden }

func playable(t *Track) bool {
	return t != nil && !t.Hidden && artistVisible(t.Artist)
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

// user returns a listener's record (a new empty one if none); save it with putUser.
func user(addr address) *User {
	if u := getUser(addr); u != nil {
		return u
	}
	return &User{}
}

// updateTop keeps a short leaderboard sorted by value, highest first.
func updateTop(list []Rank, k string, v int64) []Rank {
	// Most writes do not touch the ranking: return the same slice so it is not
	// stored again (each element is a stored object).
	if len(list) == topSize && v <= list[topSize-1].Value {
		ranked := false
		for _, r := range list {
			ranked = ranked || r.Key == k
		}
		if !ranked {
			return list
		}
	}
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
		return fit(out)
	}
	out = append(out, Rank{})
	copy(out[i+1:], out[i:])
	out[i] = Rank{k, v}
	if len(out) > topSize {
		out = out[:topSize]
	}
	return fit(out)
}

// fit copies a ranking into a slice of its own length: a stored slice keeps
// its whole backing array, each spare element an empty struct (about 400
// bytes of deposit).
func fit(rs []Rank) []Rank {
	out := make([]Rank, len(rs))
	copy(out, rs)
	return out
}

func appendCapped(list []int, id, max int, what string) []int {
	if len(list) >= max {
		panic("catalog: " + what + " limit reached")
	}
	return append(list, id)
}

func emitEvent(name string, kv ...string) { chain.Emit(name, kv...) }
