package store

import (
	"strings"
	"testing"

	"gno.land/p/nt/uassert/v0"
)

func TestPad(cur realm, t *testing.T) {
	uassert.Equal(t, "00000000", Pad(0))
	uassert.Equal(t, "00000042", Pad(42))
	uassert.Equal(t, "99999999", Pad(99999999))
	uassert.True(t, Pad(9) < Pad(10))
	uassert.PanicsWithMessage(t, cur, "store: key number out of range", func() { Pad(-1) })
	uassert.PanicsWithMessage(t, cur, "store: key number out of range", func() { Pad(100000000) })
}

// Fuzz-style: random keys and values, digits and colons included, survive a
// round trip through Row and Rows.
func TestRowsRoundTrip(t *testing.T) {
	const alphabet = "0123456789:ab/\x00é"
	seed := uint32(7)
	rnd := func(n int) int {
		seed = seed*1664525 + 1013904223
		return int(seed>>8) % n
	}
	str := func(max int) string {
		var sb strings.Builder
		for i := rnd(max + 1); i > 0; i-- {
			sb.WriteByte(alphabet[rnd(len(alphabet))])
		}
		return sb.String()
	}
	for round := 0; round < 40; round++ {
		var keys, vals []string
		page := ""
		for i := rnd(8); i > 0; i-- {
			k, v := str(12), str(40)
			keys, vals = append(keys, k), append(vals, v)
			page += Row(k, v)
		}
		gk, gv := Rows(page)
		uassert.Equal(t, len(keys), len(gk))
		for i := range keys {
			uassert.Equal(t, keys[i], gk[i])
			uassert.Equal(t, vals[i], gv[i])
		}
	}
	big := strings.Repeat("x", 16<<10)
	_, gv := Rows(Row("k", big))
	uassert.Equal(t, big, gv[0])
}

func TestRowsRefuseBadInput(cur realm, t *testing.T) {
	for _, bad := range []string{"x", "1", "1:", "3:ab", "2:ab", "2:ab9:x", ":a0:", "1234567:a"} {
		uassert.PanicsWithMessage(t, cur, "store: bad row", func() { Rows(bad) })
	}
	k, v := Rows("0:0:")
	uassert.Equal(t, 1, len(k))
	uassert.Equal(t, "", k[0]+v[0])
}

func TestOps(t *testing.T) {
	var ops Ops
	ops = ops.Set("catalog/meta", "n", "1").Del("catalog/likes", "k")
	uassert.Equal(t, `set|catalog/meta|n|1|del|catalog/likes|k|`, strings.Join(ops, "|"))
}

func TestAppend(cur realm, t *testing.T) {
	r := ""
	for _, v := range []string{"a", "", "ccc", strings.Repeat("x", 5000)} {
		r = Append(r, v)
	}
	uassert.Equal(t, Rec("a", "", "ccc", strings.Repeat("x", 5000)), r)
	full := Rec(make([]string, 63)...)
	uassert.PanicsWithMessage(t, cur, "store: bad field", func() { Append(full, "x") })
}

// Malformed or oversized values panic instead of decoding into garbage.
func TestCodecMalformed(cur realm, t *testing.T) {
	long := strings.Repeat("x", MaxField+1)
	many := make([]string, 64)
	rec := Rec("a", "bc")
	for _, c := range []struct {
		msg string
		f   func()
	}{
		{"store: too many fields", func() { Rec(many...) }},
		{"store: field too long", func() { Rec(long) }},
		{"store: bad field", func() { With(rec, 2, "x") }},
		{"store: bad field", func() { With(rec, -1, "x") }},
		{"store: bad field", func() { With(rec, 0, long) }},
		{"store: bad field", func() { Append(rec, long) }},
		{"store: id out of range", func() { Enc(-1) }},
		{"store: id out of range", func() { Enc(100000000) }},
		{"store: number out of range", func() { Fixed(-1, 2) }},
		{"store: number out of range", func() { Fixed(1<<12, 2) }},
		{"store: bad row", func() { Rows("3:ab") }},
		{"store: bad row", func() { Rows("1234567:x") }},
	} {
		uassert.PanicsWithMessage(t, cur, c.msg, c.f)
	}
	// A truncated record is out of range, never a wrong field.
	for _, bad := range []string{rec[:len(rec)-1], rec[:3], "z"} {
		uassert.PanicsContains(t, cur, "out of range", func() { Fields(bad) }, bad)
	}
}
