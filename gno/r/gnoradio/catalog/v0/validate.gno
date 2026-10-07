package catalog

import (
	"strconv"
	"strings"
	"unicode"

	"gno.land/p/gnoradio/safe/v0"
	"gno.land/p/gnoradio/text/v0"
)

func mustText(field, s string, min, max int) {
	if !text.Valid(s, min, max) {
		panic("catalog: " + field + " must be " + itoa(min) + "-" + itoa(max) +
			" characters: letters, digits, spaces and . , ' - ! ? : / & only")
	}
	// A report reason may quote what it reports (/moderation masks it).
	if field != "reason" && safe.Slur(s) {
		panic("catalog: " + field + " holds a slur")
	}
}

// validName restricts artist names to ASCII letters and digits plus the
// Latin-1 accented letters, so look-alike names cannot impersonate an artist.
func validName(s string) bool {
	if strings.TrimSpace(s) != s || strings.Contains(s, "  ") {
		return false
	}
	n, alnum := 0, 0
	for _, r := range s {
		n++
		if (r >= 'a' && r <= 'z') || (r >= 'A' && r <= 'Z') || (r >= '0' && r <= '9') ||
			(r >= 0xC0 && r <= 0xFF && r != 0xD7 && r != 0xF7) {
			alnum++
			continue
		}
		switch r {
		case ' ', '.', '\'', '-', '&':
			continue
		}
		return false
	}
	// At least one letter or digit, so the reserved skeleton is never empty.
	return n >= 2 && n <= 40 && alnum > 0
}

// latin1 folds the Latin-1 letters 0xC0-0xFF (lowercased) to ASCII.
var latin1 = [64]string{
	"a", "a", "a", "a", "a", "a", "ae", "c", "e", "e", "e", "e", "i", "i", "i", "i",
	"d", "n", "o", "o", "o", "o", "o", "", "o", "u", "u", "u", "u", "y", "th", "ss",
	"a", "a", "a", "a", "a", "a", "ae", "c", "e", "e", "e", "e", "i", "i", "i", "i",
	"d", "n", "o", "o", "o", "o", "o", "", "o", "u", "u", "u", "u", "y", "th", "y",
}

// skeleton is the key an artist name is reserved under: lowercase, common
// Latin accents stripped, fullwidth letters and digits mapped to ASCII,
// spaces and punctuation dropped and look-alikes folded (i/l/1 → l, 0 → o,
// rn → m), so "Beyonce", "BEYONCÉ", "Ｂｅｙｏｎｃｅ", "Daft  Punk" and
// "DAFT PUNK" all collide.
func skeleton(s string) string {
	var b strings.Builder
	for _, r := range s {
		switch r {
		case ' ', '.', '\'', '-', '&', 0x3000:
			continue
		}
		switch {
		case r >= 0xFF21 && r <= 0xFF3A:
			r = r - 0xFF21 + 'a'
		case r >= 0xFF41 && r <= 0xFF5A:
			r = r - 0xFF41 + 'a'
		case r >= 0xFF10 && r <= 0xFF19:
			r = r - 0xFF10 + '0'
		}
		r = unicode.ToLower(r)
		if r >= 0xC0 && r <= 0xFF && latin1[r-0xC0] != "" {
			b.WriteString(confusable(latin1[r-0xC0]))
			continue
		}
		b.WriteString(confusable(string(r)))
	}
	return strings.ReplaceAll(b.String(), "rn", "m")
}

// confusable folds characters that look alike in common fonts.
func confusable(s string) string {
	switch s {
	case "i", "1", "|":
		return "l"
	case "0":
		return "o"
	}
	return s
}

func mustName(s string) {
	if !validName(s) {
		panic("catalog: artist name must be 2-40 characters: Latin letters (a-z and Latin-1 accents), digits, spaces and . ' - &")
	}
	if safe.Slur(s) {
		panic("catalog: artist name holds a slur")
	}
}

func alnum(s string, min, max int) bool {
	if len(s) < min || len(s) > max {
		return false
	}
	for _, c := range s {
		if (c < 'a' || c > 'z') && (c < 'A' || c > 'Z') && (c < '0' || c > '9') {
			return false
		}
	}
	return true
}

func validURLChars(s string) bool {
	for _, c := range s {
		switch {
		case c >= 'a' && c <= 'z', c >= 'A' && c <= 'Z', c >= '0' && c <= '9':
		case strings.ContainsRune("-._~:/?#=&%+@", c):
		default:
			return false
		}
	}
	return true
}

// validHTTPS accepts an https link of URL-safe characters (safe in markdown
// link destinations and JSON).
func validHTTPS(s string) bool {
	return strings.HasPrefix(s, "https://") && len(s) > 10 && len(s) <= 300 && validURLChars(s)
}

func validHost(h string) bool {
	if len(h) < 3 || len(h) > 100 || !strings.Contains(h, ".") {
		return false
	}
	for _, c := range h {
		if (c < 'a' || c > 'z') && (c < '0' || c > '9') && c != '.' && c != '-' {
			return false
		}
	}
	return true
}

func hostOf(url string) string {
	rest := strings.TrimPrefix(url, "https://")
	h, _, _ := strings.Cut(rest, "/")
	return strings.ToLower(h)
}

func isSHA256(s string) bool {
	if len(s) != 64 {
		return false
	}
	for _, c := range s {
		if (c < '0' || c > '9') && (c < 'a' || c > 'f') {
			return false
		}
	}
	return true
}

// mustMedia checks an audio or cover reference:
//
//	ipfs://<cid>        content-addressed, sha256 optional
//	ar://<txid>         Arweave, sha256 optional
//	audius:<trackId>    audio only, streamed through the Audius API
//	https://<host>/…    host must be allowed, sha256 required
func mustMedia(field, uri, sha string, audioField bool) {
	if sha != "" && !isSHA256(sha) {
		panic("catalog: " + field + " sha256 must be 64 hex characters")
	}
	switch {
	case strings.HasPrefix(uri, "ipfs://"):
		if !alnum(strings.TrimPrefix(uri, "ipfs://"), 46, 100) {
			panic("catalog: " + field + " ipfs:// needs a valid CID")
		}
	case strings.HasPrefix(uri, "ar://"):
		id := strings.TrimPrefix(uri, "ar://")
		if len(id) != 43 || !validURLChars(id) {
			panic("catalog: " + field + " ar:// needs a 43-character transaction id")
		}
	case strings.HasPrefix(uri, "audius:"):
		if !audioField || !alnum(strings.TrimPrefix(uri, "audius:"), 1, 24) {
			panic("catalog: " + field + " audius:<trackId> is only valid for audio")
		}
	case strings.HasPrefix(uri, "https://"):
		if !validHTTPS(uri) || !hosts.Has(hostOf(uri)) {
			panic("catalog: " + field + " host is not allowed (ask the admin to add it)")
		}
		if sha == "" {
			panic("catalog: " + field + " over https needs the file's sha256")
		}
	default:
		panic("catalog: " + field + " must be ipfs://, ar://, audius: or an allowed https:// link")
	}
}

// normLicense maps loose input ("cc by", "cc-by-4.0", "CC0") to an SPDX id.
func normLicense(s string) string {
	s = strings.ToUpper(strings.TrimSpace(s))
	s = strings.ReplaceAll(s, " ", "-")
	s = strings.ReplaceAll(s, "_", "-")
	if s == "CC0" {
		s = "CC0-1.0"
	}
	if strings.HasPrefix(s, "CC-") && !strings.HasSuffix(s, "-4.0") {
		s += "-4.0"
	}
	for _, l := range licenses {
		if s == l {
			return l
		}
	}
	return ""
}

// parseClock parses "m:ss" (or plain seconds) into seconds.
func parseClock(s string) (int64, bool) {
	s = strings.TrimSpace(s)
	m, sec, hasColon := strings.Cut(s, ":")
	if !hasColon {
		if !text.Digits(s) || len(s) > 5 {
			return 0, false
		}
		v, _ := strconv.ParseInt(s, 10, 64)
		return v, true
	}
	if len(m) > 3 || len(sec) != 2 || !text.Digits(m) || !text.Digits(sec) {
		return 0, false
	}
	mv, _ := strconv.ParseInt(m, 10, 64)
	sv, _ := strconv.ParseInt(sec, 10, 64)
	if sv > 59 {
		return 0, false
	}
	return mv*60 + sv, true
}

// parseIDs parses "12,40,7" into distinct ids, at most max of them.
func parseIDs(s string, max int) []int {
	s = strings.TrimSpace(s)
	if s == "" {
		panic("catalog: list at least one track id")
	}
	parts := strings.Split(s, ",")
	if len(parts) > max {
		panic("catalog: at most " + itoa(max) + " tracks")
	}
	out := make([]int, 0, len(parts))
	seen := map[int]bool{}
	for _, p := range parts {
		p = strings.TrimSpace(p)
		n, err := strconv.Atoi(p)
		if err != nil || n < 1 || !text.Digits(p) {
			panic("catalog: track ids as 12,40,7")
		}
		if seen[n] {
			panic("catalog: duplicate track " + itoa(n))
		}
		seen[n] = true
		out = append(out, n)
	}
	return out
}

// curatedLicense accepts the redistributable licenses curated imports may
// carry, in any version and national port: CC0-1.0, CC-BY-<v>[-XX],
// CC-BY-SA-<v>[-XX] (v = 1.0, 2.0, 2.5, 3.0, 4.0). It returns the normalized
// id, or "" when the license is not allowed.
func curatedLicense(s string) string {
	s = strings.ToUpper(strings.ReplaceAll(strings.TrimSpace(s), " ", "-"))
	if s == "CC0" || s == "CC0-1.0" {
		return "CC0-1.0"
	}
	var rest string
	switch {
	case strings.HasPrefix(s, "CC-BY-SA-"):
		rest = strings.TrimPrefix(s, "CC-BY-SA-")
	case strings.HasPrefix(s, "CC-BY-"):
		rest = strings.TrimPrefix(s, "CC-BY-")
	default:
		return ""
	}
	ver, port, _ := strings.Cut(rest, "-")
	switch ver {
	case "1.0", "2.0", "2.5", "3.0", "4.0":
	default:
		return ""
	}
	if port != "" && (len(port) != 2 || !alnum(port, 2, 2)) {
		return ""
	}
	return s
}
