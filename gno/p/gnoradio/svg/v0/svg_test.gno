package svg

import (
	"testing"

	"gno.land/p/nt/uassert/v0"
)

func TestCanvas(t *testing.T) {
	c := New(10, 10, "")
	c.Rect(0, 0, 10, 10, 2, "#000", "")
	c.Text(1, 2, "R & B", "#fff", 8, ` text-anchor="end"`)
	uassert.Equal(t, `<svg xmlns="http://www.w3.org/2000/svg" width="10" height="10" viewBox="0 0 10 10"><style></style><rect x="0" y="0" width="10" height="10" rx="2" fill="#000"/><text x="1" y="2" fill="#fff" font-size="8" text-anchor="end">R &amp; B</text>`, c.b.String())
	uassert.Equal(t, "ab…", Clip("abcdef", 3))
	uassert.Equal(t, "abc", Clip("abc", 3))
}
