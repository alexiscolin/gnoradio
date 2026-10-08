// PKGPATH: gno.land/r/gnoradio/gas
package gas

// The fixed cost of a call on an empty deployment, with the radio, catalog
// and data packages loaded. The other z_gas filetests count their seeding
// init too: their action costs their gas minus z_gas_noop's, and this base
// plus that difference compares with radio v0's whole gas for the same main
// (docs/ARCHITECTURE-v1.md, section 6).

import (
	"testing"

	"gno.land/p/nt/testutils/v0"
	_ "gno.land/r/gnoradio/radio/v1"
)

func main(cur realm) {
	testing.SetRealm(testing.NewUserRealm(testutils.TestAddress("fan")))
}

// Gas:
// 2496421

// Storage:
// gno.land/r/gnoradio/gas: 0
