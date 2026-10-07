package store

import (
	"testing"

	"gno.land/p/nt/uassert/v0"
)

func TestSeq(t *testing.T) {
	s := NewSeq(3)
	for i := 0; i < 7; i++ {
		uassert.Equal(t, i, s.Append(Enc(i)))
	}
	uassert.Equal(t, 7, s.Len())
	s.Set(4, "x")
	v, ok := s.Get(4)
	uassert.True(t, ok)
	uassert.Equal(t, "x", v)
	v, _ = s.Get(6)
	uassert.Equal(t, Enc(6), v)
	_, ok = s.Get(7)
	uassert.False(t, ok)
}

func TestMap(t *testing.T) {
	m := NewMap(4)
	m.Set("a", "1")
	m.Set("b", "2")
	m.Set("a", "3")
	uassert.Equal(t, 2, m.Len())
	v, ok := m.Get("a")
	uassert.True(t, ok)
	uassert.Equal(t, "3", v)
	uassert.True(t, m.Remove("a"))
	uassert.False(t, m.Remove("a"))
	uassert.False(t, m.Has("a"))
	uassert.Equal(t, 1, m.Len())
	uassert.Equal(t, 1, len(m.Keys(0, 10)))
	uassert.Equal(t, 0, len(m.Keys(1, 10)))
}

func TestPacked(t *testing.T) {
	s := ""
	for _, id := range []int{5, 1, 9, 3} {
		s, _ = Add(s, id)
	}
	_, dup := Add(s, 3)
	uassert.False(t, dup)
	uassert.Equal(t, 4, Count(s))
	uassert.Equal(t, "[1 3 5 9]", sprint(Ints(s)))
	uassert.True(t, Has(s, 9))
	uassert.False(t, Has(s, 4))
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

func TestIDs(t *testing.T) {
	var x IDs
	for id := 1; id <= 1200; id++ {
		uassert.True(t, x.Add(id*2))
	}
	uassert.Equal(t, 1200, x.Len())
	uassert.False(t, x.Add(4))
	uassert.True(t, x.Add(5)) // into the middle
	uassert.True(t, x.Remove(2400))
	uassert.False(t, x.Remove(2400))
	uassert.False(t, x.Remove(7))
	uassert.Equal(t, "[2398 2396]", sprint(x.Page(0, 2, true)))
	uassert.Equal(t, "[2 4 5 6]", sprint(x.Page(0, 4, false)))
	uassert.Equal(t, "[1022 1024]", sprint(x.Page(511, 2, false))) // across a range boundary
	uassert.Equal(t, "[1026 1024]", sprint(x.Page(686, 2, true)))
	uassert.Equal(t, 1200, x.Len())
	uassert.Equal(t, 0, len(x.Page(1200, 5, false)))
}

// Sparse and emptied ranges: pages skip them, counts stay exact.
func TestIDsSparse(t *testing.T) {
	var x IDs
	for _, id := range []int{99999999, 3, 70000, 513, 512} {
		uassert.True(t, x.Add(id))
	}
	uassert.Equal(t, "[3 512 513 70000 99999999]", sprint(x.Page(0, 9, false)))
	uassert.True(t, x.Remove(70000))
	uassert.Equal(t, "[99999999 513]", sprint(x.Page(0, 2, true)))
	uassert.Equal(t, "[513 99999999]", sprint(x.Page(2, 9, false)))
	uassert.Equal(t, 4, x.Len())
}

// Writes stay on one short path: 5,000 records in chunks of 16 are 313
// leaves under a tree of height 2.
func TestTreeHeight(t *testing.T) {
	s := NewSeq(16)
	for i := 0; i < 5000; i++ {
		s.Append(Enc(i))
	}
	uassert.Equal(t, 2, s.t.height)
	for _, i := range []int{0, 15, 16, 511, 512, 4999} {
		v, ok := s.Get(i)
		uassert.True(t, ok)
		uassert.Equal(t, Enc(i), v)
	}
	s.Set(4999, "z")
	v, _ := s.Get(4999)
	uassert.Equal(t, "z", v)
	_, ok := s.Get(5000)
	uassert.False(t, ok)
}

// Keys pages through every key exactly once, whatever the offset.
func TestMapKeysPaging(t *testing.T) {
	m := NewMap(64)
	for i := 0; i < 300; i++ {
		m.Set("k"+itoa(i), "")
	}
	seen := map[string]bool{}
	for off := 0; off < 300; off += 7 {
		for _, k := range m.Keys(off, 7) {
			uassert.False(t, seen[k], k)
			seen[k] = true
		}
	}
	uassert.Equal(t, 300, len(seen))
	uassert.Equal(t, 0, len(m.Keys(300, 5)))
	m.Remove("k1")
	uassert.Equal(t, 299, m.Len())
	uassert.Equal(t, 299, len(m.Keys(0, 1000)))
}

// Leaves hang as high as their slot allows and move down only when another
// leaf needs the slot: lookups, counts and walk order stay those of the full
// tree whatever the insertion order.
func TestSparseTree(t *testing.T) {
	var tr tree
	keys := []int{70000, 3, 1 << 20, 4, 35, 3 + 32*32*32, 0, 99, 1<<20 + 1}
	for i, k := range keys {
		l := tr.leaf(k, true)
		uassert.Equal(t, "", l.s)
		l.s = itoa(k)
		add(tr.path(k, false), 1)
		if i == 0 {
			uassert.Equal(t, 1, len(tr.path(k, false))) // a lone leaf is the root
		}
	}
	uassert.Equal(t, len(keys), tr.len())
	uassert.Equal(t, 5, tr.height)
	uassert.True(t, len(tr.path(99, false)) < tr.height+1) // hung above level 0
	for _, k := range []int{1, 5, 36, 3 + 32*32, 70001, 1<<20 + 2, 1 << 25} {
		uassert.True(t, tr.leaf(k, false) == nil, itoa(k))
	}
	for _, k := range keys {
		uassert.Equal(t, itoa(k), tr.leaf(k, false).s)
	}
	all := func(off int, desc bool) string {
		out := ""
		tr.walk(off, desc, func(l *node, skip int) bool {
			out += l.s + " "
			return true
		})
		return out
	}
	uassert.Equal(t, "0 3 4 35 99 32771 70000 1048576 1048577 ", all(0, false))
	uassert.Equal(t, "1048577 1048576 70000 32771 99 35 4 3 0 ", all(0, true))
	uassert.Equal(t, "35 99 32771 70000 1048576 1048577 ", all(3, false))
	add(tr.path(35, false), -1) // an emptied leaf is skipped
	add(tr.path(70000, false), -1)
	uassert.Equal(t, "0 3 4 99 32771 1048576 1048577 ", all(0, false))
	uassert.Equal(t, "32771 1048576 1048577 ", all(4, false))
	uassert.Equal(t, "3 0 ", all(5, true))
	uassert.Equal(t, len(keys)-2, tr.len())
}

// A sparse map (buckets far apart) keeps every operation and page exact.
func TestSparseMapPaging(t *testing.T) {
	m := NewMap(65536)
	for i := 0; i < 500; i++ {
		m.Set("g1user"+itoa(i)+"/0", itoa(i))
	}
	m.Set("g1user7/0", "seven")
	uassert.Equal(t, 500, m.Len())
	v, ok := m.Get("g1user7/0")
	uassert.True(t, ok)
	uassert.Equal(t, "seven", v)
	uassert.True(t, m.Remove("g1user8/0"))
	uassert.False(t, m.Remove("g1user8/0"))
	uassert.False(t, m.Has("g1user8/0"))
	whole := m.Keys(0, 1000)
	uassert.Equal(t, 499, len(whole))
	var paged []string
	for off := 0; off < 499; off += 13 {
		paged = append(paged, m.Keys(off, 13)...)
	}
	uassert.Equal(t, len(whole), len(paged))
	for i := range whole {
		uassert.Equal(t, whole[i], paged[i])
	}
}

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
