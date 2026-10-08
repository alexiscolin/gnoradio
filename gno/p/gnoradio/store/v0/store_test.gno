package store

import (
	"testing"

	"gno.land/p/nt/uassert/v0"
)

func TestPacked(t *testing.T) {
	s := ""
	for _, id := range []int{5, 1, 9, 3} {
		s, _ = Add(s, id)
	}
	_, dup := Add(s, 3)
	uassert.False(t, dup)
	uassert.Equal(t, 4, Count(s))
	uassert.Equal(t, "[1 3 5 9]", sprint(Ints(s)))
	s, ok := Remove(s, 5)
	uassert.True(t, ok)
	uassert.Equal(t, "[9 3]", sprint(Page(s, 0, 2, true)))
	uassert.Equal(t, "[3 9]", sprint(Page(s, 1, 5, false)))
	uassert.Equal(t, "[7 2 7]", sprint(Ints(Pack([]int{7, 2, 7}))))
}

func TestRec(t *testing.T) {
	r := Rec("a", "", "hello world", "7")
	f := Fields(r)
	uassert.Equal(t, 4, len(f))
	uassert.Equal(t, "hello world", f[2])
	uassert.Equal(t, "", f[1])
	uassert.Equal(t, "7", Field(r, 3))
	uassert.Equal(t, "", Field(r, 9))
	long := ""
	for len(long) < 5000 {
		long += "0123456789"
	}
	uassert.Equal(t, long, Field(Rec("x", long, "y"), 1))
	w := With(r, 2, "bye")
	uassert.Equal(t, Rec("a", "", "bye", "7"), w)
	uassert.Equal(t, Rec("a", "", "bye", ""), With(w, 3, ""))
	uassert.Equal(t, Rec("long", "", "bye", "7"), With(w, 0, "long"))
	uassert.Equal(t, "y", Field(Rec("x", long, "y"), 2))
}

func TestJSONList(t *testing.T) {
	l := Pack([]int{3, 12345678, 40})
	uassert.Equal(t, "[       3,12345678,      40]", JSON(l))
	uassert.Equal(t, "[]", JSON(""))
	uassert.Equal(t, 12345678, At(l, 1))
}

// Sparse and emptied ranges: pages skip them, counts stay exact.
// Writes stay on one short path: 5,000 records in chunks of 16 are 313
// leaves under a tree of height 2.
// Keys pages through every key exactly once, whatever the offset.
// Leaves hang as high as their slot allows and move down only when another
// leaf needs the slot: lookups, counts and walk order stay those of the full
// tree whatever the insertion order.
// A sparse map (buckets far apart) keeps every operation and page exact.
func sprint(xs []int) string {
	s := "["
	for i, x := range xs {
		if i > 0 {
			s += " "
		}
		s += itoa(x)
	}
	return s + "]"
}

func itoa(n int) string {
	if n == 0 {
		return "0"
	}
	s := ""
	for n > 0 {
		s = string(rune('0'+n%10)) + s
		n /= 10
	}
	return s
}

func TestKeys(t *testing.T) {
	uassert.Equal(t, "001234567890", TimeKey(1234567890))
	uassert.Equal(t, "000000000000", TimeKey(0))
	k, i := Slot(1, 8)
	uassert.Equal(t, Pad(0), k)
	uassert.Equal(t, 0, i)
	k, i = Slot(17, 8)
	uassert.Equal(t, Pad(2), k)
	uassert.Equal(t, 0, i)
	k, i = Slot(16, 16)
	uassert.Equal(t, Pad(0), k)
	uassert.Equal(t, 15, i)
	uassert.Equal(t, 100, Limit(0, 100))
	uassert.Equal(t, 100, Limit(101, 100))
	uassert.Equal(t, 50, Limit(-3, 50))
	uassert.Equal(t, 7, Limit(7, 50))
}
