// Package blocks stores an ordered list of slots (an id and a duration) in
// fixed-size blocks plus a slice of per-block sums. It backs a radio
// rotation: appending is O(1), changing a duration rewrites one block and one
// sum, and finding the slot at a position in the loop scans the sums and then
// a single block — O(n/Size + Size) instead of O(n).
//
// Each block is its own heap object, so a write only rewrites the touched
// block and the (small) sums slice, never the whole list.
package blocks

// Size is the number of slots per block.
const Size = 128

type block struct {
	ids  []int
	durs []int64
}

// List is an append-only ordered list of slots. The zero value is ready to use.
type List struct {
	blocks []*block
	sums   []int64 // sums[i] = total duration of blocks[i]
	n      int
	total  int64
}

// New returns an empty list.
func New() *List { return &List{} }

// Len returns the number of slots.
func (l *List) Len() int { return l.n }

// Total returns the sum of all durations.
func (l *List) Total() int64 { return l.total }

// Append adds a slot at the end and returns its index.
func (l *List) Append(id int, dur int64) int {
	if dur < 0 {
		panic("blocks: negative duration")
	}
	nb := len(l.blocks)
	if nb == 0 || len(l.blocks[nb-1].ids) == Size {
		l.blocks = append(l.blocks, &block{})
		l.sums = append(l.sums, 0)
		nb++
	}
	b := l.blocks[nb-1]
	b.ids = append(b.ids, id)
	b.durs = append(b.durs, dur)
	l.sums[nb-1] += dur
	l.total += dur
	l.n++
	return l.n - 1
}

// Slot returns the id and duration of slot i.
func (l *List) Slot(i int) (int, int64) {
	l.check(i)
	b := l.blocks[i/Size]
	return b.ids[i%Size], b.durs[i%Size]
}

// SetDuration changes the duration of slot i (0 removes it from the loop).
func (l *List) SetDuration(i int, dur int64) {
	l.check(i)
	if dur < 0 {
		panic("blocks: negative duration")
	}
	bi := i / Size
	b := l.blocks[bi]
	old := b.durs[i%Size]
	if old == dur {
		return
	}
	b.durs[i%Size] = dur
	l.sums[bi] += dur - old
	l.total += dur - old
}

// PrefixBefore returns the total duration of slots 0..i-1.
func (l *List) PrefixBefore(i int) int64 {
	if i < 0 || i > l.n {
		panic("blocks: index out of range")
	}
	bi := i / Size
	var p int64
	for k := 0; k < bi; k++ {
		p += l.sums[k]
	}
	if bi < len(l.blocks) {
		b := l.blocks[bi]
		for k := 0; k < i%Size; k++ {
			p += b.durs[k]
		}
	}
	return p
}

// Find returns the slot playing at position pos of the loop, 0 <= pos < Total,
// with the offset into that slot. ok is false when pos is out of range.
// Slots of duration 0 are never returned.
func (l *List) Find(pos int64) (slot, id int, offset int64, ok bool) {
	if pos < 0 || pos >= l.total {
		return 0, 0, 0, false
	}
	for bi, s := range l.sums {
		if pos >= s {
			pos -= s
			continue
		}
		b := l.blocks[bi]
		for k, d := range b.durs {
			if pos < d {
				return bi*Size + k, b.ids[k], pos, true
			}
			pos -= d
		}
	}
	return 0, 0, 0, false // unreachable while sums are consistent
}

func (l *List) check(i int) {
	if i < 0 || i >= l.n {
		panic("blocks: index out of range")
	}
}
