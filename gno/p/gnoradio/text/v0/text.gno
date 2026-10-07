// Package text holds the small string helpers shared by the GnoRadio realms.
package text

import (
	"strconv"
	"strings"
	"unicode"
)

// Key zero-pads an id so avl keys sort in number order.
func Key(id int) string {
	s := strconv.Itoa(id)
	return strings.Repeat("0", 10-len(s)) + s
}

// Str quotes a value as a JSON string without escaping. Use it only for values
// whose validator already refuses `"`, `\` and control characters (Valid text,
// validated URLs, hashes, addresses, constants): escaping costs about 1M gas
// per field in the VM.
func Str(s string) string { return `"` + s + `"` }

// Valid accepts min..max runes of letters (any script), digits, spaces and
// . , ' - ! ? : / &. Markdown, HTML and JSON specials are refused, so the text
// is safe in markdown and JSON as is (SVG still escapes '&'). Fullwidth and
// mathematical letters (which dodge word filters) and the blank Hangul fillers
// are refused too.
func Valid(s string, min, max int) bool {
	n := 0
	for _, r := range s {
		n++
		if r >= 0xFF01 && r <= 0xFF5E || r >= 0x1D400 && r <= 0x1D7FF || r == 0x115F || r == 0x1160 || r == 0x3164 || r == 0xFFA0 {
			return false
		}
		if unicode.IsLetter(r) || unicode.IsDigit(r) {
			continue
		}
		switch r {
		case ' ', '.', ',', '\'', '-', '!', '?', ':', '/', '&':
			continue
		}
		return false
	}
	return n >= min && n <= max
}

// Digits reports whether s is a non-empty run of ASCII digits.
func Digits(s string) bool {
	if s == "" {
		return false
	}
	for _, c := range s {
		if c < '0' || c > '9' {
			return false
		}
	}
	return true
}

// GNOT formats ugnot as GNOT with up to 6 decimals.
func GNOT(u int64) string {
	const ugnot = 1_000_000
	whole := strconv.FormatInt(u/ugnot, 10)
	frac := u % ugnot
	if frac == 0 {
		return whole + " GNOT"
	}
	f := strconv.FormatInt(frac, 10)
	f = strings.TrimRight(strings.Repeat("0", 6-len(f))+f, "0")
	return whole + "." + f + " GNOT"
}
