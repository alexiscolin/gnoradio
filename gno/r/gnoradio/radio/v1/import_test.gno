package radio

import (
	"chain"
	"strings"
	"testing"

	"gno.land/p/gnoradio/text/v0"
	"gno.land/p/nt/uassert/v0"
	"gno.land/r/gnoradio/catalog/v1"
	"gno.land/r/gnoradio/data"
)

// batchLine is one ImportTracks line: ImportTrack's 12 arguments, tab-separated.
func batchLine(artist int, title string, genre int) string {
	return strings.Join([]string{text.Itoa(artist), title, text.Itoa(genre), "2:00", "CC0-1.0", "", "ipfs://" + cid, "", "", "", "https://archive.org/details/batch", "Batch by the band"}, "\t")
}

// A batch imports every line, each joining its genre station, never New.
func TestImportTracks(cur realm, t *testing.T) {
	reset(cur)
	testing.SetRealm(testing.NewUserRealm(boss))
	aid := catalog.CreateArtist(cross(cur), catalog.OriginCurated, "Batch Band", "", "")
	first := catalog.TrackCount() + 1
	var lines []string
	for i := 0; i < 3; i++ {
		lines = append(lines, batchLine(aid, "Batch "+text.Itoa(i), 4+i))
	}
	last := ImportTracks(cross(cur), strings.Join(lines, "\n"))
	uassert.Equal(t, first+2, last)
	uassert.Equal(t, catalog.TrackCount(), synced())
	for i := 0; i < 3; i++ {
		id := first + i
		_, inGenre := sta(4 + i).slot(id)
		uassert.True(t, inGenre, text.Itoa(id))
		_, inNew := sta(NewStation).slot(id)
		uassert.False(t, inNew, text.Itoa(id))
	}
	// A single import skips New too; a publication still joins it.
	one := ImportTrack(cross(cur), aid, "Single", 4, "1:00", "CC0-1.0", "", "ipfs://"+cid, "", "", "", "https://archive.org/details/single", "Single by the band")
	_, inNew := sta(NewStation).slot(one)
	uassert.False(t, inNew)
	testing.SetRealm(testing.NewUserRealm(dave))
	catalog.RegisterArtist(cross(cur), "Fresh Artist", "")
	fresh := publish(cur, "Fresh", 4, "1:00")
	_, inNew = sta(NewStation).slot(fresh)
	uassert.True(t, inNew)
	// Sync and Refresh never put an import in New later.
	Sync(cross(cur), 50)
	Refresh(cross(cur), one)
	_, inNew = sta(NewStation).slot(one)
	uassert.False(t, inNew)
}

// All or nothing: a bad line rejects the batch and names it; caps, admin, pause.
func TestImportTracksGuards(cur realm, t *testing.T) {
	reset(cur)
	testing.SetRealm(testing.NewUserRealm(boss))
	aid := catalog.CreateArtist(cross(cur), catalog.OriginCurated, "Guard Band", "", "")
	n := catalog.TrackCount()
	uassert.AbortsContains(t, cur, "batch line 2", func() { ImportTracks(cross(cur), batchLine(aid, "Good", 4)+"\nshort\tline") })
	uassert.Equal(t, n, catalog.TrackCount()) // a malformed batch writes nothing
	uassert.Equal(t, n, synced())
	// A track the catalog refuses aborts the transaction (on chain nothing of
	// the batch is kept; gno test keeps what ran before the panic).
	uassert.AbortsContains(t, cur, "title", func() { ImportTracks(cross(cur), batchLine(aid, "Bad <b>", 4)) })
	var many []string
	for i := 0; i <= maxImportBatch; i++ {
		many = append(many, batchLine(aid, "Many "+text.Itoa(i), 4))
	}
	uassert.AbortsContains(t, cur, "a batch holds", func() { ImportTracks(cross(cur), strings.Join(many, "\n")) })
	uassert.AbortsContains(t, cur, "a batch holds", func() { ImportTracks(cross(cur), "") })
	testing.SetRealm(testing.NewUserRealm(carol))
	uassert.AbortsContains(t, cur, "admin only", func() { ImportTracks(cross(cur), batchLine(aid, "Not Admin", 4)) })
	testing.SetRealm(testing.NewUserRealm(chain.PackageAddress("gno.land/r/gnoradio/data/dev")))
	data.Pause(cross(cur), "radio", true)
	testing.SetRealm(testing.NewUserRealm(boss))
	uassert.AbortsContains(t, cur, "paused", func() { ImportTracks(cross(cur), batchLine(aid, "Paused", 4)) })
	testing.SetRealm(testing.NewUserRealm(chain.PackageAddress("gno.land/r/gnoradio/data/dev")))
	data.Pause(cross(cur), "radio", false)
}
