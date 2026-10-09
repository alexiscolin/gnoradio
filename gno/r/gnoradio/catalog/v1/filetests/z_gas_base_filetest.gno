// PKGPATH: gno.land/r/gnoradio/gas
package gas

// The fixed cost of a call to catalog/v1 on an empty deployment: loading the
// catalog and data packages and reading one count. The other z_gas filetests
// count their seeding init too; their main costs main minus z_gas_noop's, and
// this base plus that difference compares with catalog v0's whole-main gas
// (docs/ARCHITECTURE-v1.md, section 6).

import (
	"testing"

	"gno.land/p/nt/testutils/v0"
	catalog "gno.land/r/gnoradio/catalog/v1"
)

func main(cur realm) {
	testing.SetRealm(testing.NewUserRealm(testutils.TestAddress("fan")))
	_ = catalog.TrackCount()
}

// Gas:
// 3291406
