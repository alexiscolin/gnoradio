package catalog

import (
	"testing"

	"gno.land/p/nt/uassert/v0"
	"gno.land/r/gnoradio/tickets/nft"
)

// The permanent tickets/nft realm reads artist heads straight from the data
// realm: this release must keep the layout it froze (every catalog release
// carries this test).
func TestArtistLayoutForNFT(t *testing.T) {
	uassert.Equal(t, nft.CArtists, cArtists)
	uassert.Equal(t, nft.ArtistChunk, chunkSize)
	uassert.Equal(t, nft.AHidden, aHidden)
	uassert.Equal(t, nft.AName, aName)
}
