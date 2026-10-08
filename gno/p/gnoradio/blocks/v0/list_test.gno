package blocks

// List is the persisted rotation the realms used before the codec form. It
// stays here only as the oracle TestCodecMatchesList compares the codec with.

type block struct {
	ids  string // 4 digits per slot
	durs string // 2 digits per slot
}

func (b *block) len() int { return len(b.durs) / 2 }

func (b *block) id(k int) int {
	return int(dec[b.ids[4*k]])<<18 | int(dec[b.ids[4*k+1]])<<12 | int(dec[b.ids[4*k+2]])<<6 | int(dec[b.ids[4*k+3]])
}

func (b *block) dur(k int) int64 { return int64(dec[b.durs[2*k]])<<6 | int64(dec[b.durs[2*k+1]]) }

const digits = "0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz-_"

var dec [128]byte

func init() {
	for i := 0; i < len(digits); i++ {
		dec[digits[i]] = byte(i)
	}
}

func encID(id int) string {
	return string([]byte{digits[id>>18&63], digits[id>>12&63], digits[id>>6&63], digits[id&63]})
}

func encDur(d int64) string { return string([]byte{digits[d>>6&63], digits[d&63]}) }

// group holds up to Size blocks and their duration sums.
type group struct {
	blocks []*block
	sums   []int64 // sums[i] = total duration of blocks[i]
}

// List is an append-only ordered list of slots. The zero value is ready to use.
type List struct {
	groups []*group
	totals []int64 // totals[g] = total duration of groups[g]
	n      int
	total  int64
}

// New returns an empty list.
func New() *List { return &List{} }

// Len returns the number of slots.
func (l *List) Len() int { return l.n }

// Total returns the sum of all durations.
func (l *List) Total() int64 { return l.total }

// at locates slot i: its group, its block in the group and its place in the block.
func (l *List) at(i int) (g *group, gi, bi, k int) {
	gi, bi, k = i/groupSlots, i%groupSlots/Size, i%Size
	return l.groups[gi], gi, bi, k
}

// Append adds a slot at the end and returns its index.
func (l *List) Append(id int, dur int64) int {
	checkSlot(id, dur)
	if l.n%groupSlots == 0 {
		l.groups = append(l.groups, &group{})
		l.totals = append(l.totals, 0)
	}
	g := l.groups[len(l.groups)-1]
	if l.n%Size == 0 {
		g.blocks = append(g.blocks, &block{})
		g.sums = append(g.sums, 0)
	}
	bi := len(g.blocks) - 1
	b := g.blocks[bi]
	b.ids += encID(id)
	b.durs += encDur(dur)
	g.sums[bi] += dur
	l.totals[len(l.totals)-1] += dur
	l.total += dur
	l.n++
	return l.n - 1
}

// Slot returns the id and duration of slot i.
func (l *List) Slot(i int) (int, int64) {
	l.check(i)
	g, _, bi, k := l.at(i)
	b := g.blocks[bi]
	return b.id(k), b.dur(k)
}

// Set replaces slot i's id and duration (a fixed-size ring reuses its slots).
func (l *List) Set(i, id int, dur int64) {
	l.check(i)
	checkSlot(id, dur)
	g, gi, bi, k := l.at(i)
	b := g.blocks[bi]
	old := b.dur(k)
	if b.id(k) != id {
		b.ids = b.ids[:4*k] + encID(id) + b.ids[4*k+4:]
	}
	if old == dur {
		return
	}
	b.durs = b.durs[:2*k] + encDur(dur) + b.durs[2*k+2:]
	g.sums[bi] += dur - old
	l.totals[gi] += dur - old
	l.total += dur - old
}

// PrefixBefore returns the total duration of slots 0..i-1.
func (l *List) PrefixBefore(i int) int64 {
	if i < 0 || i > l.n {
		panic("blocks: index out of range")
	}
	gi, bi, k := i/groupSlots, i%groupSlots/Size, i%Size
	var p int64
	for j := 0; j < gi; j++ {
		p += l.totals[j]
	}
	if gi == len(l.groups) {
		return p
	}
	g := l.groups[gi]
	for j := 0; j < bi; j++ {
		p += g.sums[j]
	}
	if bi < len(g.blocks) {
		b := g.blocks[bi]
		for j := 0; j < k; j++ {
			p += b.dur(j)
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
	for gi, t := range l.totals {
		if pos >= t {
			pos -= t
			continue
		}
		g := l.groups[gi]
		for bi, s := range g.sums {
			if pos >= s {
				pos -= s
				continue
			}
			b := g.blocks[bi]
			for k := 0; k < b.len(); k++ {
				d := b.dur(k)
				if pos < d {
					return gi*groupSlots + bi*Size + k, b.id(k), pos, true
				}
				pos -= d
			}
		}
	}
	return 0, 0, 0, false // unreachable while sums are consistent
}

func (l *List) check(i int) {
	if i < 0 || i >= l.n {
		panic("blocks: index out of range")
	}
}
