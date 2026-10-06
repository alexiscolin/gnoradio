package gnoradio

import (
	"strings"
	"unicode"
)

// validText accepts letters (any script), digits, spaces and a little
// punctuation. Everything else, notably markdown, HTML and XML specials,
// is refused, so user text is safe in markdown, SVG and JSON alike.
func validText(s string, min, max int) bool {
	n := 0
	for _, r := range s {
		n++
		if unicode.IsLetter(r) || unicode.IsDigit(r) {
			continue
		}
		switch r {
		case ' ', '.', ',', '\'', '-', '!', '?', ':', '/':
			continue
		}
		return false
	}
	return n >= min && n <= max
}

func mustText(field, s string, min, max int) {
	if !validText(s, min, max) {
		panic("gnoradio: " + field + " doit faire " + itoa(min) + " à " + itoa(max) +
			" caractères (lettres, chiffres, espaces et . , ' - ! ? : /)")
	}
}

// validName restricts artist names to Latin letters so that look-alike
// names in other scripts cannot impersonate an artist.
func validName(s string) bool {
	n := 0
	for _, r := range s {
		n++
		if unicode.Is(unicode.Latin, r) || (r >= '0' && r <= '9') {
			continue
		}
		switch r {
		case ' ', '.', '\'', '-':
			continue
		}
		return false
	}
	return n >= 2 && n <= 32
}

func validCID(s string) bool {
	if len(s) < 46 || len(s) > 100 {
		return false
	}
	for _, c := range s {
		if (c < 'a' || c > 'z') && (c < 'A' || c > 'Z') && (c < '0' || c > '9') {
			return false
		}
	}
	return true
}

// validURL accepts https links made of URL-safe characters only, so the
// value is safe as a markdown link destination and in JSON.
func validURL(s string) bool {
	return strings.HasPrefix(s, "https://") && len(s) > 10 && len(s) <= 200 && validURLChars(s)
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
