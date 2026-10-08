// PKGPATH: gno.land/r/gnoradio/datagas
package datagas

import (
	"testing"

	"gno.land/p/gnoradio/store/v0"
	"gno.land/r/gnoradio/data"
)

const writer = "gno.land/r/gnoradio/catalog/v1"

var _ = store.Pad

// init stores a small collection and 5,000 keys (a 5,000-track catalog) in a
// transaction of its own, so main loads what it reads from the store. Gas
// counts init too: compare these filetests by their differences
// (ARCHITECTURE-v1.md, section 6).
func init(cur realm) {
	testing.SetRealm(testing.NewCodeRealm(writer))
	data.Make(cross(cur), "catalog/tracks")
	data.Make(cross(cur), "catalog/meta")
	data.Set(cross(cur), "catalog/meta", "head", "0")
	for i := 0; i < 5000; i += 50 {
		var ops store.Ops
		for j := i; j < i+50; j++ {
			ops = ops.Set("catalog/tracks", store.Pad(j), "track record of about a hundred bytes, like a chunk entry")
		}
		data.Batch(cross(cur), ops)
	}
}

func main(cur realm) {
	testing.SetRealm(testing.NewCodeRealm(writer))
	for i := 0; i < 1; i++ {
		data.Get("catalog/meta", "head")
	}
}

// Gas:
// 1218418851

// Storage:
// gno.land/r/gnoradio/data: 0
// gno.land/r/gnoradio/datagas: 0
