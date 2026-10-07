// Package store keeps GnoRadio's per-item data compact. On gno.land every
// stored object pays a deposit of 100 ugnot per byte, and an avl node costs
// about 2KB on its own, a struct about 1.8KB. Here an item is a string record
// inside a chunk (about its length + 60 bytes), a map entry inside a hashed
// bucket (about 170 bytes), or 9 bytes inside a packed id list.
//
// Chunks and buckets hang off a sparse tree of fanout 32. Saving an object
// rewrites its parents up to the root, so a write costs one leaf plus one
// small node per level (at most log32 of the key range: 3 levels for 32k
// leaves), never a list of every chunk. Nodes store only what exists, so a
// new bucket costs about 1.5KB of deposit, plus a small inner node when it
// shares a slot. Each node counts the items below it, so pages at any offset
// are reached in the same few steps.
package store

import "strconv"

// ---- tree: int key -> leaf, fanout 32 ----

const (
	fanBits = 5
	fan     = 1 << fanBits
)

// node is an inner node (kids) or a leaf (key, and one of items, m, s), with
// n the number of items below it. Every stored object costs deposit, so the
// tree holds only what exists:
//   - an inner node keeps its children in slot order: idx holds their slots
//     (one byte each) and kids the children (a fixed array of fan pointers
//     would store a typed nil per empty slot, about 5KB per node);
//   - a leaf hangs from the first node where its slot is free, however high,
//     and is pushed down a level only when another leaf needs that slot. In
//     a hashed map a new bucket then costs the bucket alone, not a chain of
//     inner nodes down to it.
type node struct {
	idx   string
	kids  []*node // nil on leaves
	n     int
	key   int               // leaf key
	items []string          // Seq chunk
	m     map[string]string // Map bucket
	s     string            // IDs range (packed sorted list)
}

// tree addresses leaves by key; height grows as keys grow (root covers
// keys < 32^height).
type tree struct {
	root   *node
	height int
}

func slot(k, h int) int { return k >> (fanBits * (h - 1)) & (fan - 1) }

// path returns the nodes from the root to the leaf of key k, creating the
// leaf when create is set; nil if the leaf does not exist.
func (t *tree) path(k int, create bool) []*node {
	if k < 0 {
		panic("store: negative key")
	}
	if t.root == nil {
		if !create {
			return nil
		}
		t.root = &node{key: k}
		for k>>(fanBits*t.height) > 0 {
			t.height++
		}
		return []*node{t.root}
	}
	for k>>(fanBits*t.height) > 0 {
		if !create {
			return nil
		}
		t.root, t.height = &node{n: t.root.n, idx: "\x00", kids: []*node{t.root}}, t.height+1
	}
	p := make([]*node, 0, t.height+1)
	var parent *node
	pj := 0
	nd := t.root
	for h := t.height; ; h-- {
		if nd.kids == nil {
			if nd.key == k {
				return append(p, nd)
			}
			if !create {
				return nil
			}
			// Another leaf holds this slot: an inner node takes its place
			// (h >= 1 here: at height 0 every slot matched, so the key did).
			in := &node{n: nd.n, idx: string([]byte{byte(slot(nd.key, h))}), kids: []*node{nd}}
			if parent == nil {
				t.root = in
			} else {
				parent.kids[pj] = in
			}
			nd = in
		}
		p = append(p, nd)
		i := slot(k, h)
		j, found := nd.find(i)
		if !found {
			if !create {
				return nil
			}
			l := &node{key: k}
			nd.idx = nd.idx[:j] + string([]byte{byte(i)}) + nd.idx[j:]
			nd.kids = append(nd.kids, nil)
			copy(nd.kids[j+1:], nd.kids[j:])
			nd.kids[j] = l
			return append(p, l)
		}
		parent, pj, nd = nd, j, nd.kids[j]
	}
}

// find returns the position of slot i in nd's children, or where it goes.
func (nd *node) find(i int) (int, bool) {
	c := rune(i)
	for j, r := range nd.idx {
		if r >= c {
			return j, r == c
		}
	}
	return len(nd.idx), false
}

// leaf returns the leaf of key k (nil if absent and !create).
func (t *tree) leaf(k int, create bool) *node {
	p := t.path(k, create)
	if p == nil {
		return nil
	}
	return p[len(p)-1]
}

// add adds d to the item counts along a path.
func add(p []*node, d int) {
	for _, nd := range p {
		nd.n += d
	}
}

func last(p []*node) *node { return p[len(p)-1] }

func (t *tree) len() int {
	if t.root == nil {
		return 0
	}
	return t.root.n
}

// walk calls fn on leaves in key order (reverse when desc), skipping the
// first offset items by their counts; fn gets the leaf and how many of its
// items to skip, and returns false to stop.
func (t *tree) walk(offset int, desc bool, fn func(l *node, skip int) bool) {
	if t.root != nil && offset < t.root.n {
		walk(t.root, offset, desc, fn)
	}
}

func walk(nd *node, offset int, desc bool, fn func(l *node, skip int) bool) bool {
	if nd.kids == nil {
		return fn(nd, offset)
	}
	for j := range nd.kids {
		i := j
		if desc {
			i = len(nd.kids) - 1 - j
		}
		c := nd.kids[i]
		if c.n == 0 {
			continue
		}
		if offset >= c.n {
			offset -= c.n
			continue
		}
		if !walk(c, offset, desc, fn) {
			return false
		}
		offset = 0
	}
	return true
}

// ---- Seq: index-addressed records ----

// Seq is an append-only list of string records, index 0..Len()-1, in chunks
// of size records.
type Seq struct {
	size int
	t    tree
}

// NewSeq returns a Seq whose chunks hold size records.
func NewSeq(size int) *Seq {
	if size < 1 {
		panic("store: chunk size must be positive")
	}
	return &Seq{size: size}
}

func (s *Seq) Len() int { return s.t.len() }

// Append adds a record and returns its index.
func (s *Seq) Append(v string) int {
	i := s.t.len()
	p := s.t.path(i/s.size, true)
	l := last(p)
	l.items = append(l.items, v)
	add(p, 1)
	return i
}

// Get returns record i ("" and false when out of range).
func (s *Seq) Get(i int) (string, bool) {
	if i < 0 || i >= s.t.len() {
		return "", false
	}
	return s.t.leaf(i/s.size, false).items[i%s.size], true
}

// Set replaces record i.
func (s *Seq) Set(i int, v string) {
	if i < 0 || i >= s.t.len() {
		panic("store: index out of range")
	}
	s.t.leaf(i/s.size, false).items[i%s.size] = v
}

// ---- Map: string -> string in hashed buckets ----

// Map maps strings to strings. Keys hash into buckets created on first use,
// so a write rewrites one small bucket and its path.
type Map struct {
	nb int
	t  tree
}

// NewMap returns a Map with nb buckets. Buckets are sparse: pick nb for the
// largest expected size (about 16 entries per bucket), unused ones cost nothing.
func NewMap(nb int) *Map {
	if nb < 1 {
		panic("store: bucket count must be positive")
	}
	return &Map{nb: nb}
}

func (m *Map) Len() int { return m.t.len() }

func (m *Map) at(k string) int { return int(fnv(k) % uint32(m.nb)) }

func (m *Map) Get(k string) (string, bool) {
	b := m.t.leaf(m.at(k), false)
	if b == nil {
		return "", false
	}
	v, ok := b.m[k]
	return v, ok
}

func (m *Map) Has(k string) bool {
	_, ok := m.Get(k)
	return ok
}

func (m *Map) Set(k, v string) {
	p := m.t.path(m.at(k), true)
	b := last(p)
	if b.m == nil {
		b.m = map[string]string{}
	}
	_, had := b.m[k]
	b.m[k] = v
	if !had {
		add(p, 1)
	}
}

// Remove deletes k and reports whether it was there.
func (m *Map) Remove(k string) bool {
	p := m.t.path(m.at(k), false)
	if p == nil {
		return false
	}
	b := last(p)
	if _, ok := b.m[k]; !ok {
		return false
	}
	delete(b.m, k)
	add(p, -1)
	return true
}

// Keys lists up to limit keys from offset, in bucket order (stable, not
// sorted). Bucket counts make the offset free: only returned keys are read.
func (m *Map) Keys(offset, limit int) []string {
	var out []string
	m.t.walk(offset, false, func(b *node, skip int) bool {
		for k := range b.m {
			if skip > 0 {
				skip--
				continue
			}
			if len(out) == limit {
				return false
			}
			out = append(out, k)
		}
		return len(out) < limit
	})
	return out
}

func fnv(s string) uint32 {
	h := uint32(2166136261)
	for i := 0; i < len(s); i++ {
		h ^= uint32(s[i])
		h *= 16777619
	}
	return h
}

// ---- Records: fields behind a length header, sliced without scanning ----

// In the VM every byte a loop touches costs gas (strings.Split of a 200-byte
// record is about 2M gas). A record starts with the field count and each
// field's length (base-64 digits), so reading a field is a few slices.

const digits = "0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz-_"

var dec [128]int

func init() {
	for i := 0; i < len(digits); i++ {
		dec[digits[i]] = i
	}
}

// MaxField is the longest field a record holds (3 base-64 digits).
const MaxField = 1<<18 - 1

// Rec packs fields into a record (at most 63 fields).
func Rec(fs ...string) string {
	if len(fs) > 63 {
		panic("store: too many fields")
	}
	h := make([]byte, 1, 1+3*len(fs))
	h[0] = digits[len(fs)]
	body := make([]byte, 0, 64)
	for _, f := range fs {
		n := len(f)
		if n > MaxField {
			panic("store: field too long")
		}
		h = append(h, digits[n>>12&63], digits[n>>6&63], digits[n&63])
		body = append(body, f...)
	}
	return string(h) + string(body)
}

func fieldLen(rec string, i int) int {
	return dec[rec[1+3*i]]<<12 | dec[rec[2+3*i]]<<6 | dec[rec[3+3*i]]
}

// Fields unpacks a record.
func Fields(rec string) []string {
	n := dec[rec[0]]
	out := make([]string, n)
	p := 1 + 3*n
	for i := 0; i < n; i++ {
		l := fieldLen(rec, i)
		out[i] = rec[p : p+l]
		p += l
	}
	return out
}

// Field returns field i of a record ("" past the last field).
func Field(rec string, i int) string {
	n := dec[rec[0]]
	if i >= n {
		return ""
	}
	p := 1 + 3*n
	for k := 0; k < i; k++ {
		p += fieldLen(rec, k)
	}
	return rec[p : p+fieldLen(rec, i)]
}

// With returns rec with field i replaced by v, without decoding the record.
func With(rec string, i int, v string) string {
	n := dec[rec[0]]
	if i < 0 || i >= n || len(v) > MaxField {
		panic("store: bad field")
	}
	p := 1 + 3*n
	for k := 0; k < i; k++ {
		p += fieldLen(rec, k)
	}
	l := len(v)
	h := string([]byte{digits[l>>12&63], digits[l>>6&63], digits[l&63]})
	return rec[:1+3*i] + h + rec[4+3*i:p] + v + rec[p+fieldLen(rec, i):]
}

// ---- Id lists: W bytes per id ("     123,"), sortable and JSON-ready ----

// W is the width of one id in a list (ids up to 99,999,999). The padding is
// spaces and the separator a comma, so "[" + list without its last comma +
// "]" is already a JSON array: exporting a list costs no per-id work.
const W = 9

// Enc writes one id of a list.
func Enc(id int) string {
	if id < 0 || id > 99999999 {
		panic("store: id out of range")
	}
	s := strconv.Itoa(id)
	return "        "[len(s):] + s + ","
}

// At returns the i-th id of a list.
func At(list string, i int) int {
	n := 0
	for k := i * W; k < i*W+W-1; k++ {
		if c := list[k]; c != ' ' {
			n = n*10 + int(c-'0')
		}
	}
	return n
}

// Count is the number of ids in a list.
func Count(list string) int { return len(list) / W }

// JSON returns a list as a JSON array.
func JSON(list string) string {
	if list == "" {
		return "[]"
	}
	return "[" + list[:len(list)-1] + "]"
}

// Ints decodes a list.
func Ints(list string) []int {
	out := make([]int, 0, Count(list))
	for i := 0; i < Count(list); i++ {
		out = append(out, At(list, i))
	}
	return out
}

// Pack encodes ids in their order.
func Pack(ids []int) string {
	b := make([]byte, 0, W*len(ids))
	for _, id := range ids {
		b = append(b, Enc(id)...)
	}
	return string(b)
}

// Page returns up to limit ids from offset, from the end when desc.
func Page(list string, offset, limit int, desc bool) []int {
	n := Count(list)
	var out []int
	for k := offset; k >= 0 && k < n && len(out) < limit; k++ {
		i := k
		if desc {
			i = n - 1 - k
		}
		out = append(out, At(list, i))
	}
	return out
}

// find returns the position of id in a sorted list, or where it goes.
func find(list string, id int) (int, bool) {
	lo, hi := 0, Count(list)
	for lo < hi {
		mid := (lo + hi) / 2
		if At(list, mid) < id {
			lo = mid + 1
		} else {
			hi = mid
		}
	}
	return lo, lo < Count(list) && At(list, lo) == id
}

// Has reports whether a sorted list holds id (binary search).
func Has(sorted string, id int) bool {
	_, ok := find(sorted, id)
	return ok
}

// Add inserts id into a sorted list; false if already there.
func Add(sorted string, id int) (string, bool) {
	i, ok := find(sorted, id)
	if ok {
		return sorted, false
	}
	return sorted[:i*W] + Enc(id) + sorted[i*W:], true
}

// Remove deletes id from a sorted list; false if absent.
func Remove(sorted string, id int) (string, bool) {
	i, ok := find(sorted, id)
	if !ok {
		return sorted, false
	}
	return sorted[:i*W] + sorted[i*W+W:], true
}

// ---- IDs: a large sorted id set ----

// IDs is a sorted set of ids for collections that grow without bound (a
// genre's tracks). Ids live in ranges of 512 consecutive ids, one packed list
// per range: add, remove and page are a few node reads whatever the size.
type IDs struct{ t tree }

const idsRange = 9 // ids per range: 1 << 9 = 512

func (x *IDs) Len() int { return x.t.len() }

// Add inserts id; false if already there.
func (x *IDs) Add(id int) bool {
	p := x.t.path(id>>idsRange, true)
	l := last(p)
	s, ok := Add(l.s, id)
	if !ok {
		return false
	}
	l.s = s
	add(p, 1)
	return true
}

// Remove deletes id; false if absent.
func (x *IDs) Remove(id int) bool {
	p := x.t.path(id>>idsRange, false)
	if p == nil {
		return false
	}
	l := last(p)
	s, ok := Remove(l.s, id)
	if !ok {
		return false
	}
	l.s = s
	add(p, -1)
	return true
}

// Page returns up to limit ids from offset, highest first when desc.
func (x *IDs) Page(offset, limit int, desc bool) []int {
	var out []int
	if offset < 0 {
		offset = 0
	}
	x.t.walk(offset, desc, func(l *node, skip int) bool {
		out = append(out, Page(l.s, skip, limit-len(out), desc)...)
		return len(out) < limit
	})
	return out
}
