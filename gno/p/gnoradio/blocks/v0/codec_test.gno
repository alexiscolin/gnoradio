package blocks

import (
	"strconv"
	"testing"

	"gno.land/p/nt/uassert/v0"
)

// rot keeps the codec's strings the way a realm would, under its own keys.
type rot map[string]string

func (r rot) parts(i int) (string, string) {
	g, b := Where(i)
	return r["g"+strconv.Itoa(g)], r["b"+strconv.Itoa(b)]
}

func (r rot) put(i int, h, grp, blk string) {
	g, b := Where(i)
	r["h"], r["g"+strconv.Itoa(g)], r["b"+strconv.Itoa(b)] = h, grp, blk
}

func (r rot) find(pos int64) (int, int, int64, bool) {
	g, rest, ok := FindGroup(r["h"], pos)
	if !ok {
		return 0, 0, 0, false
	}
	b, rest := FindBlock(r["g"+strconv.Itoa(g)], g, rest)
	slot, id, off := FindSlot(r["b"+strconv.Itoa(b)], b, rest)
	return slot, id, off, true
}

// The codec gives the same results as List over random operations, across
// two groups.
func TestCodecMatchesList(t *testing.T) {
	seed := uint32(1)
	rnd := func(n int) int {
		seed = seed*1664525 + 1013904223
		return int(seed>>8) % n
	}
	l, r := New(), rot{}
	appendBoth := func() {
		id, d := rnd(MaxID+1), int64(rnd(MaxDur+1))
		if rnd(10) == 0 {
			d = 0
		}
		n := Len(r["h"])
		grp, blk := r.parts(n)
		h, grp, blk, i := Append(r["h"], grp, blk, id, d)
		r.put(i, h, grp, blk)
		uassert.Equal(t, l.Append(id, d), i)
	}
	for i := 0; i < groupSlots+300; i++ {
		appendBoth()
	}
	check := func() {
		h := r["h"]
		uassert.Equal(t, l.Len(), Len(h))
		uassert.Equal(t, l.Total(), Total(h))
		for k := 0; k < 20; k++ {
			i := rnd(l.Len())
			grp, blk := r.parts(i)
			wid, wd := l.Slot(i)
			id, d := Slot(blk, i)
			uassert.Equal(t, wid, id)
			uassert.Equal(t, wd, d)
			j := rnd(l.Len() + 1)
			grp, blk = r.parts(j)
			uassert.Equal(t, l.PrefixBefore(j), PrefixBefore(h, grp, blk, j))
			pos := int64(rnd(int(l.Total())+2)) - 1
			ws, wid2, woff, wok := l.Find(pos)
			s, id2, off, ok := r.find(pos)
			uassert.Equal(t, wok, ok)
			uassert.Equal(t, ws, s)
			uassert.Equal(t, wid2, id2)
			uassert.Equal(t, woff, off)
		}
	}
	check()
	for round := 0; round < 300; round++ {
		i := rnd(l.Len())
		grp, blk := r.parts(i)
		switch rnd(2) {
		case 0:
			appendBoth()
		case 1:
			id, d := rnd(MaxID+1), int64(rnd(MaxDur+1))
			h, grp, blk := Set(r["h"], grp, blk, i, id, d)
			r.put(i, h, grp, blk)
			l.Set(i, id, d)
		}
		if round%30 == 0 {
			check()
		}
	}
	check()
}

func TestCodecEmptyAndLimits(cur realm, t *testing.T) {
	uassert.Equal(t, 0, Len(""))
	uassert.Equal(t, int64(0), Total(""))
	uassert.Equal(t, int64(0), PrefixBefore("", "", "", 0))
	_, _, ok := FindGroup("", 0)
	uassert.False(t, ok)
	h, grp, blk, i := Append("", "", "", 7, 30)
	uassert.Equal(t, 0, i)
	_, _, ok = FindGroup(h, 30)
	uassert.False(t, ok)
	// A block of 768 bytes for a full one, as the doc budgets.
	for i = 1; i < Size; i++ {
		h, grp, blk, _ = Append(h, grp, blk, MaxID, MaxDur)
	}
	uassert.Equal(t, 768, len(blk))
	uassert.PanicsWithMessage(t, cur, "blocks: wrong group or block for this slot", func() { Append(h, grp, blk, 1, 1) })
	uassert.PanicsWithMessage(t, cur, "blocks: wrong group or block for this slot", func() { Set(h, "", blk, 3, 1, 1) })
	uassert.PanicsWithMessage(t, cur, "blocks: index out of range", func() { Set(h, grp, blk, Size, 1, 1) })
	uassert.PanicsWithMessage(t, cur, "blocks: id out of range", func() { Set(h, grp, blk, 0, MaxID+1, 1) })
	uassert.PanicsWithMessage(t, cur, "blocks: duration out of range", func() { Set(h, grp, blk, 0, 1, MaxDur+1) })
}

// Strings that do not add up (a header without its groups, a group or a
// block shorter than the position) panic instead of finding a wrong slot.
func TestCodecMalformed(cur realm, t *testing.T) {
	h, grp, blk, _ := Append("", "", "", 7, 30)
	uassert.PanicsWithMessage(t, cur, "blocks: bad header", func() { FindGroup(h[:nW+totW], 10) })
	uassert.PanicsWithMessage(t, cur, "blocks: bad group", func() { FindBlock(grp, 0, 30) })
	uassert.PanicsWithMessage(t, cur, "blocks: bad group", func() { FindBlock("", 0, 0) })
	uassert.PanicsWithMessage(t, cur, "blocks: bad block", func() { FindSlot(blk, 0, 30) })
	uassert.PanicsWithMessage(t, cur, "blocks: bad block", func() { FindSlot("", 0, 0) })
	uassert.PanicsWithMessage(t, cur, "blocks: index out of range", func() { Slot(blk, 1) })
	uassert.PanicsWithMessage(t, cur, "blocks: index out of range", func() { PrefixBefore(h, grp, blk, 2) })
}
