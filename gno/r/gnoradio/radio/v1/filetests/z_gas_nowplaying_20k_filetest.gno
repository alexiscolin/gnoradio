// PKGPATH: gno.land/r/gnoradio/gas
package gas

// Gas and deposit of one radio/v1 action (main) on a catalog of 20000 tracks
// by 80 verified artists (track i*80+a is by artist a, genre
// 1+i%20: a genre's tracks alternate artists), synced into the stations, and a radio in use:
// Listeners' choice holding 210 tracks, weekly tops
// of ten, a full activity ring, picks waiting on station 5, a pick on
// station 6, a dedication on station 7, an artist (9) whose budget refunds
// sponsored picks and a listener with the reputation they need. The measured
// baseline is the same state under the same mains (docs/ARCHITECTURE-v1.md,
// section 6). init writes the catalog as
// catalog/v1 would and the rotations as radio/v1 would (p/blocks), then
// programs the rest through radio/v1's own calls. Gas counts init too:
// compare with z_gas_noop_20k (docs/ARCHITECTURE-v1.md, section 6).
// Storage is main's alone.

import (
	"chain"
	"strconv"
	"testing"

	"gno.land/p/gnoradio/blocks/v0"
	"gno.land/p/gnoradio/store/v0"
	"gno.land/p/nt/testutils/v0"
	catalog "gno.land/r/gnoradio/catalog/v1"
	"gno.land/r/gnoradio/data"
	radio "gno.land/r/gnoradio/radio/v1"
)

const (
	nTracks   = 20000
	perArtist = 250
	ipfs      = "ipfs://bafybeigdyrzt5sfp7udm7hu76uh7y26nf3efuylqabf3oclgtqy55fbzdi"
	t0        = int64(1234567890)
	robotPub  = "ea4a6c63e29c520abef5507b132ec5f9954776aebebe7b92421eea691446d22c"
	// the robot's certificates (seed 0x07 * 32) of radio.NoteMessage, expiring at t0+600
	authorCert = "061d4e19b7ef77d603e0fe510ba09e9d022d19fd86f686f78c48c8d031d37180bba09e18db883b68a156ffc9a728289bee2b8cdb682db1ba48d12393b6926a0c" // author, station 7
	fanCert    = "0d26fdcb5788bbc297200808a556cf82d5055af7ebff1168f0d63ba7dd223dcca74330af10cd777401dec5320ba8752afc88385dd6b301085a942738ebe02506" // fan, station 5
)

var (
	_         = blocks.Size
	fan       = testutils.TestAddress("fan")
	author    = testutils.TestAddress("author")
	reporter  = testutils.TestAddress("reporter")
	nArtists  = nTracks / perArtist
	radioAddr = chain.PackageAddress("gno.land/r/gnoradio/radio/v1")
)

// track is the k-th track of genre g by artist a.
func track(g, k, a int) int { return (k*20+g-1)*nArtists + a }

func owner(a int) address { return chain.PackageAddress("gno.land/r/seed/a" + strconv.Itoa(a-1)) }

func field(c, k string, i int) string {
	v, _ := data.Get(c, k)
	return store.Field(v, i)
}

const digits = "0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz-_"

func fixed(v int64, w int) string {
	b := make([]byte, w)
	for i := w - 1; i >= 0; i-- {
		b[i] = digits[v&63]
		v >>= 6
	}
	return string(b)
}

func init(cur realm) {
	// The catalog, as catalog/v1's gas filetests write it.
	testing.SetRealm(testing.NewUserRealm(owner(1)))
	catalog.RegisterArtist(cross(cur), "Seed Artist", "")
	radio.PublishTrack(cross(cur), "Seed song", 1, "3:30", "cc by", "none", "", ipfs, "", "", "", "", "yes")
	ar, tr := field("catalog/artists", store.Pad(0), 0), field("catalog/tracks", store.Pad(0), 0)
	meta, _ := data.Get("catalog/meta", "n")

	testing.SetRealm(testing.NewCodeRealm("gno.land/r/gnoradio/catalog/v1"))
	// writes go out as the current realm, 64 at a time
	var ops store.Ops
	flush := func() {
		if len(ops) > 0 {
			data.Batch(cross(cur), ops)
			ops = nil
		}
	}
	add := func(c, k, v string) {
		if ops = ops.Set(c, k, v); len(ops) == 4*64 {
			flush()
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
	chunks("catalog/artists", nArtists, func(a int) string {
		add("catalog/owners", owner(a).String(), strconv.Itoa(a))
		ids := make([]int, perArtist)
		for i := range ids {
			ids[i] = i*nArtists + a
		}
		add("catalog/alists", store.Pad(a), store.Rec(store.Pack(ids), ""))
		return store.With(store.With(store.With(ar, 1, owner(a).String()), 2, "1"), 6, "Seed Artist "+strconv.Itoa(a))
	})
	genre := func(id int) int { return 1 + (id-1)/nArtists%20 }
	chunks("catalog/tracks", nTracks, func(id int) string {
		return store.With(store.With(tr, 0, strconv.Itoa(1+(id-1)%nArtists)), 1, strconv.Itoa(genre(id)))
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
	act, _ := data.Get("catalog/activity", store.Pad(0))
	var liked, paid []string
	for i := 0; i < 64; i++ {
		add("catalog/activity", store.Pad(i), act)
		if i < 10 {
			liked = append(liked, strconv.Itoa(4000+i), strconv.Itoa(100-i))
			paid = append(paid, strconv.Itoa(4000+i), strconv.Itoa((1000-i)*1_000_000))
		}
	}
	add("catalog/promo", store.Pad(1), "5") // artist 1 shares 5% of its tips (v0's default; opt-in since P5)
	add("catalog/tops", "liked", store.Rec(liked...))
	for _, k := range []string{"artists", "fans", "support"} {
		add("catalog/tops", k, store.Rec(paid...))
	}
	add("catalog/meta", "n", store.With(store.With(meta, 21, strconv.Itoa(nArtists)), 0, strconv.Itoa(nTracks)))
	flush()

	// The stations, as radio/v1's ingestion leaves them: each genre station
	// its own tracks (Main has no rotation: it simulcasts them), New the last 300 (a ring) and
	// Choice 200 picks.
	testing.SetRealm(testing.NewCodeRealm("gno.land/r/gnoradio/radio/v1"))
	type rot struct {
		h, grp, blk string
		ring        []string // New and Choice: the blocks, kept in the record
		idx         string   // and their index: track (4) and slot (2), by track
	}
	rots := map[int]*rot{}
	put := func(st, id int) int {
		r := rots[st]
		if r == nil {
			r = &rot{}
			rots[st] = r
		}
		h, grp, blk, i := blocks.Append(r.h, r.grp, r.blk, id, 210)
		r.h, r.grp, r.blk = h, grp, blk
		if len(blk) == blocks.Size*6 {
			if st > 20 {
				r.ring = append(r.ring, blk)
			} else {
				add("radio/rot", store.Pad(st)+"/b/"+store.Pad(i/blocks.Size), blk)
			}
			r.blk = ""
		}
		if (i+1)%(blocks.Size*blocks.Size) == 0 {
			add("radio/rot", store.Pad(st)+"/g/"+store.Pad(i/(blocks.Size*blocks.Size)), grp)
			r.grp = ""
		}
		return i
	}
	homes := make([]string, nTracks+1)
	for id := 1; id <= nTracks; id++ {
		homes[id] = fixed(int64(genre(id)), 1) + fixed(int64(put(genre(id), id)), 4)
	}
	newest := nTracks - 300
	for id := newest + 1; id <= nTracks; id++ {
		i := put(21, id)
		rots[21].idx += fixed(int64(id), 4) + fixed(int64(i), 2)
	}
	for k := 1; k <= 200; k++ {
		i := put(22, 7*k)
		rots[22].idx += fixed(int64(7*k), 4) + fixed(int64(i), 2)
	}
	// In use: twelve curators who picked on station 5 this week (the tops
	// hold ten), one listener who may report, a full activity ring.
	wk := (t0 + 3*24*3600) / (7 * 24 * 3600)
	cur5 := func(picks int64) string {
		return fixed(picks, 4) + fixed(0, 4) + fixed(0, 8) + fixed(0, 8) + fixed(t0, 6) + fixed(t0/(15*24*3600), 4) +
			fixed(picks, 4) + fixed(0, 4) + fixed(wk, 4) + fixed(picks, 4) + fixed(0, 4) + fixed(0, 8) +
			fixed(5, 1) + fixed(wk, 4) + fixed(picks, 4) + fixed(0, 4) + fixed(0, 8) + fixed(t0, 6)
	}
	scores, whos := "", ""
	for i := 11; i >= 0; i-- {
		who := chain.PackageAddress("gno.land/r/seed/c" + strconv.Itoa(i)).String()
		add("radio/curators", who, cur5(int64(i+1)))
		if i >= 2 {
			scores += fixed(int64(i+1), 4)
			whos += fixed(int64(len(who)), 1) + who
		}
	}
	top := fixed(wk, 4) + fixed(10, 1) + scores + whos
	add("radio/tops", "all", top)
	tops := map[int]string{5: top}
	// listeners with the reputation sponsored picks and reports need: 3 picks, the first 8 days ago
	trusted := fixed(3, 4) + fixed(0, 4) + fixed(0, 8) + fixed(0, 8) + fixed(t0-8*24*3600, 6) +
		fixed(t0/(15*24*3600), 4) + fixed(3, 4) + fixed(0, 4) + fixed(0, 4) + fixed(0, 4) + fixed(0, 4) + fixed(0, 8)
	add("radio/curators", reporter.String(), trusted)
	add("radio/curators", testutils.TestAddress("spon").String(), trusted)
	var hs []string
	for id := 1; id <= nTracks; id++ {
		if hs = append(hs, homes[id]); len(hs) == 16 || id == nTracks {
			add("radio/homes", store.Pad((id-1)/16), store.Rec(hs...))
			hs = nil
		}
	}
	for st, r := range rots {
		if st > 20 {
			if r.blk != "" {
				r.ring = append(r.ring, r.blk)
			}
		} else {
			if r.blk != "" {
				add("radio/rot", store.Pad(st)+"/b/"+store.Pad(blocks.Len(r.h)/blocks.Size), r.blk)
			}
			if r.grp != "" {
				add("radio/rot", store.Pad(st)+"/g/"+store.Pad((blocks.Len(r.h)-1)/(blocks.Size*blocks.Size)), r.grp)
			}
		}
		joins := 0
		if st == 21 {
			joins = 300
		} else if st == 22 {
			joins = 200
		}
		f := []string{fixed(t0, 6), fixed(int64(joins), 6), fixed(int64(blocks.Len(r.h)), 4), r.h, "", "", tops[st]}
		if st > 20 {
			ring := r.grp
			for _, blk := range r.ring {
				ring += blk
			}
			f = append(f, ring, r.idx)
		}
		add("radio/stations", store.Pad(st), store.Rec(f...))
	}
	flow := fixed(int64(nTracks), 4) + "0000" + "0" + fixed(wk, 4) + fixed(3, 4) + "0" + "11111111111111111111"
	add("radio/meta", "flow", flow)
	for i := 0; i < 64; i++ {
		add("radio/activity", store.Pad(i), store.Rec("queue", owner(1).String(), fixed(1, 4)+fixed(5, 1)+fixed(t0, 6)+fixed(t0, 6)))
	}
	flush()

	// The rest through radio/v1: Sync (Choice takes the most liked), the
	// moderation robot, picks.
	testing.SetRealm(testing.NewUserRealm(fan))
	for i := 0; i < 3; i++ {
		radio.Sync(cross(cur), 20)
	}
	testing.SetRealm(testing.NewUserRealm(radio.Admin()))
	radio.SetModBot(cross(cur), robotPub)
	// Artist 9 sponsors picks of its tracks.
	testing.IssueCoins(chain.PackageAddress("gno.land/r/gnoradio/catalog/v1"), chain.Coins{{"ugnot", 1_000_000}})
	testing.SetOriginSend(chain.Coins{{"ugnot", 1_000_000}})
	testing.SetRealm(testing.NewUserRealm(owner(9)))
	catalog.FundPromo(cross(cur))
	testing.SetOriginSend(nil)
	testing.SetRealm(testing.NewUserRealm(testutils.TestAddress("w0")))
	radio.Queue(cross(cur), 5, track(5, 0, 1))
	testing.SetRealm(testing.NewUserRealm(testutils.TestAddress("w1")))
	radio.Queue(cross(cur), 5, track(5, 0, 2))
	testing.SetRealm(testing.NewUserRealm(testutils.TestAddress("picker")))
	radio.Queue(cross(cur), 6, track(6, 0, 1))
	testing.SetRealm(testing.NewUserRealm(author))
	radio.QueueWithNote(cross(cur), 7, track(7, 0, 1), "for Marie", t0+600, authorCert)
}

func main(cur realm) {
	testing.SkipHeights(6 * 3600 / 5)
	println(len(radio.ScheduleJSON(0, 7200)) > 0)
	id, _, _ := radio.NowPlaying(0)
	println(id > 0)
}

// Gas:
// 13180939203

// Output:
// true
// true
