package blocks

import (
	"testing"

	"gno.land/p/nt/uassert/v0"
)

// naive reference implementation
func naiveFind(durs []int64, pos int64) (int, int64, bool) {
	for i, d := range durs {
		if pos < d {
			return i, pos, true
		}
		pos -= d
	}
	return 0, 0, false
}

func TestAppendFindPrefix(t *testing.T) {
	l := New()
	var durs []int64
	for i := 0; i < 1000; i++ {
		d := int64(30 + (i*37)%240)
		if i%11 == 0 {
			d = 0
		}
		uassert.Equal(t, i, l.Append(i+1, d))
		durs = append(durs, d)
	}
	var total int64
	for _, d := range durs {
		total += d
	}
	uassert.Equal(t, total, l.Total())
	uassert.Equal(t, 1000, l.Len())

	for _, pos := range []int64{0, 1, 29, 30, 1234, total / 2, total - 1} {
		slot, id, off, ok := l.Find(pos)
		wi, woff, wok := naiveFind(durs, pos)
		uassert.True(t, ok)
		uassert.True(t, wok)
		uassert.Equal(t, wi, slot)
		uassert.Equal(t, wi+1, id)
		uassert.Equal(t, woff, off)
	}
	_, _, _, ok := l.Find(total)
	uassert.False(t, ok)
	_, _, _, ok = l.Find(-1)
	uassert.False(t, ok)

	var p int64
	for i := 0; i <= 1000; i++ {
		uassert.Equal(t, p, l.PrefixBefore(i))
		if i < 1000 {
			p += durs[i]
		}
	}
}

func TestSetDuration(t *testing.T) {
	l := New()
	for i := 0; i < 300; i++ {
		l.Append(i+1, 100)
	}
	uassert.Equal(t, int64(30000), l.Total())
	l.SetDuration(150, 0)
	uassert.Equal(t, int64(29900), l.Total())
	slot, id, off, _ := l.Find(150 * 100)
	uassert.Equal(t, 151, slot) // slot 150 is skipped
	uassert.Equal(t, 152, id)
	uassert.Equal(t, int64(0), off)
	l.SetDuration(150, 250)
	uassert.Equal(t, int64(30150), l.Total())
	_, d := l.Slot(150)
	uassert.Equal(t, int64(250), d)
	uassert.Equal(t, int64(150*100), l.PrefixBefore(150))
	uassert.Equal(t, int64(150*100+250), l.PrefixBefore(151))
}

func TestPanics(cur realm, t *testing.T) {
	l := New()
	uassert.PanicsWithMessage(t, cur, "blocks: duration out of range", func() { l.Append(1, -1) })
	uassert.PanicsWithMessage(t, cur, "blocks: index out of range", func() { l.Slot(0) })
	l.Append(1, 10)
	uassert.PanicsWithMessage(t, cur, "blocks: index out of range", func() { l.SetDuration(1, 5) })
	uassert.PanicsWithMessage(t, cur, "blocks: duration out of range", func() { l.SetDuration(0, -5) })
}

func TestEmpty(t *testing.T) {
	var l List
	uassert.Equal(t, int64(0), l.Total())
	_, _, _, ok := l.Find(0)
	uassert.False(t, ok)
	uassert.Equal(t, int64(0), l.PrefixBefore(0))
}

// Gas stability: each pair builds the same list, one of them then runs 100
// Find + SetDuration + PrefixBefore. GAS(ops) - GAS(build) is the cost of the
// operations; it must grow far slower than the list (n/Size + Size).
func build(n int) *List {
	l := New()
	for i := 0; i < n; i++ {
		l.Append(i+1, 200)
	}
	return l
}

func ops(l *List) {
	for k := 0; k < 100; k++ {
		pos := l.Total() - 1 - int64(k)*7
		_, _, _, ok := l.Find(pos)
		if !ok {
			panic("not found")
		}
		l.SetDuration(l.Len()-1-k, 150)
		_ = l.PrefixBefore(l.Len() - 1 - k)
	}
}

func TestGasBuild1k(t *testing.T)  { build(1000) }
func TestGasOps1k(t *testing.T)    { ops(build(1000)) }
func TestGasBuild20k(t *testing.T) { build(20000) }
func TestGasOps20k(t *testing.T)   { ops(build(20000)) }

func TestHundredK(t *testing.T) {
	l := build(100000)
	uassert.Equal(t, int64(100000*200), l.Total())
	slot, id, off, ok := l.Find(l.Total() - 1)
	uassert.True(t, ok)
	uassert.Equal(t, 99999, slot)
	uassert.Equal(t, 100000, id)
	uassert.Equal(t, int64(199), off)
	l.SetDuration(99999, 0)
	slot, _, _, ok = l.Find(l.Total() - 1)
	uassert.True(t, ok)
	uassert.Equal(t, 99998, slot)
	uassert.Equal(t, int64(99999*200), l.PrefixBefore(99999))
}

func TestPackedRange(t *testing.T) {
	l := New()
	l.Append(MaxID, MaxDur)
	l.Append(0, 0)
	id, d := l.Slot(0)
	uassert.Equal(t, MaxID, id)
	uassert.Equal(t, int64(MaxDur), d)
	uassert.Equal(t, "blocks: id out of range", panicOf(func() { l.Append(MaxID+1, 1) }))
	uassert.Equal(t, "blocks: duration out of range", panicOf(func() { l.Append(1, MaxDur+1) }))
}

func panicOf(f func()) (msg string) {
	defer func() { msg, _ = recover().(string) }()
	f()
	return ""
}
