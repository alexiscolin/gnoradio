// PKGPATH: gno.land/r/gnoradio/gas
package gas

// Gas and deposit of one catalog/v1 action (main) on a catalog of 20000 tracks
// by 80 artists and 300 likers, written by init as catalog/v1 would (chunks
// of 8 records, ranges of 512 ids; counts: tracks, 20 genres, artists), in use: a full activity ring and
// leaderboards. Gas counts init too: compare with
// z_gas_noop_20k (docs/ARCHITECTURE-v1.md, section 6). Storage is main's alone.

import (
	"chain"
	"strconv"
	"testing"

	"gno.land/p/gnoradio/store/v0"
	"gno.land/p/nt/testutils/v0"
	catalog "gno.land/r/gnoradio/catalog/v1"
	"gno.land/r/gnoradio/data"
)

const (
	nTracks   = 20000
	perArtist = 250
	ipfs      = "ipfs://bafybeigdyrzt5sfp7udm7hu76uh7y26nf3efuylqabf3oclgtqy55fbzdi"
)

var (
	_   = testutils.TestAddress
	fan = testutils.TestAddress("fan")
)

func owner(a int) address { return chain.PackageAddress("gno.land/r/seed/a" + strconv.Itoa(a-1)) }

func field(c, k string, i int) string {
	v, _ := data.Get(c, k)
	return store.Field(v, i)
}

func init(cur realm) {
	// A real artist and track give the record layouts.
	testing.SetRealm(testing.NewUserRealm(owner(1)))
	catalog.RegisterArtist(cross(cur), "Seed Artist", "")
	testing.SetRealm(testing.NewCodeRealm("gno.land/r/gnoradio/radio/v1")) // radio.PublishTrack does this
	catalog.PublishFor(cross(cur), owner(1), "Seed song", 1, "3:30", "cc by", "none", "", ipfs, "", "", "", "", "yes")
	ar, tr := field("catalog/artists", store.Pad(0), 0), field("catalog/tracks", store.Pad(0), 0)
	meta, _ := data.Get("catalog/meta", "n")

	testing.SetRealm(testing.NewCodeRealm("gno.land/r/gnoradio/catalog/v1"))
	var ops store.Ops
	add := func(c, k, v string) {
		if ops = ops.Set(c, k, v); len(ops) == 4*64 {
			data.Batch(cross(cur), ops)
			ops = nil
		}
	}
	chunks := func(c string, n int, rec func(id int) string) {
		var recs []string
		for id := 1; id <= n; id++ {
			if recs = append(recs, rec(id)); len(recs) == 8 || id == n {
				add(c, store.Pad((id-1)/8), store.Rec(recs...))
				recs = nil
			}
		}
	}
	nArtists := nTracks / perArtist
	chunks("catalog/artists", nArtists, func(a int) string {
		add("catalog/owners", owner(a).String(), strconv.Itoa(a))
		ids := make([]int, perArtist)
		for i := range ids {
			ids[i] = (a-1)*perArtist + i + 1
		}
		add("catalog/alists", store.Pad(a), store.Rec(store.Pack(ids), ""))
		return store.With(store.With(store.With(ar, 1, owner(a).String()), 2, "1"), 6, "Seed Artist "+strconv.Itoa(a))
	})
	genre := func(id int) int { return 1 + (id-1)%20 }
	chunks("catalog/tracks", nTracks, func(id int) string {
		return store.With(store.With(tr, 0, strconv.Itoa(1+(id-1)/perArtist)), 1, strconv.Itoa(genre(id)))
	})
	for g := 1; g <= 20; g++ {
		meta = store.With(meta, g, strconv.Itoa(nTracks/20))
		for r := 0; r <= nTracks>>9; r++ {
			var ids []int
			for id := r << 9; id < (r+1)<<9 && id <= nTracks; id++ {
				if id > 0 && genre(id) == g {
					ids = append(ids, id)
				}
			}
			add("catalog/genres", store.Pad(g)+"/"+store.Pad(r), store.Pack(ids))
		}
	}
	for u := 0; u < 300; u++ {
		id := 1 + (u*37)%nTracks
		add("catalog/likes", chain.PackageAddress("gno.land/r/seed/u"+strconv.Itoa(u)).String()+"/"+store.Pad(id>>9), store.Pack([]int{id}))
	}
	// A catalog in use: the activity ring is full and the leaderboards hold ten.
	act, _ := data.Get("catalog/activity", store.Pad(0))
	var liked, paid []string // 100 likes, 1,000 GNOT and down
	for i := 0; i < 64; i++ {
		add("catalog/activity", store.Pad(i), act)
		if i < 10 {
			liked = append(liked, strconv.Itoa(4000+i), strconv.Itoa(100-i))
			paid = append(paid, strconv.Itoa(4000+i), strconv.Itoa((1000-i)*1_000_000))
		}
	}
	add("catalog/tops", "liked", store.Rec(liked...))
	for _, k := range []string{"artists", "fans", "support"} {
		add("catalog/tops", k, store.Rec(paid...))
	}
	add("catalog/meta", "n", store.With(store.With(meta, 21, strconv.Itoa(nArtists)), 0, strconv.Itoa(nTracks)))
	data.Batch(cross(cur), ops)
}

func main(cur realm) {
	_ = catalog.TrackCount()
}

// Gas:
// 7379820943

// Storage:
// gno.land/r/gnoradio/catalog/v1: 0
// gno.land/r/gnoradio/data: 0
// gno.land/r/gnoradio/gas: 0
