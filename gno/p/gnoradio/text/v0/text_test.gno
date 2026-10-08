package text

import (
	"testing"

	"gno.land/p/nt/uassert/v0"
)

func TestText(t *testing.T) {
	uassert.True(t, Valid("Rock & Roll!", 1, 20))
	uassert.False(t, Valid(`a"b`, 0, 10))
	uassert.False(t, Valid("toolong", 0, 3))
	for _, s := range []string{"ｆｕｃｋ", "𝐟𝐮𝐜𝐤", "a\u3164b", "\u115F"} {
		uassert.False(t, Valid(s, 0, 10), s)
	}
	uassert.True(t, Valid("Łukasz, Ελένη, 東京", 1, 30))
	uassert.True(t, Digits("042"))
	uassert.False(t, Digits(""))
	uassert.False(t, Digits("4a"))
	uassert.Equal(t, "2.5 GNOT", GNOT(2_500_000))
	uassert.Equal(t, "0.000001 GNOT", GNOT(1))
	uassert.Equal(t, "3 GNOT", GNOT(3_000_000))
}

func TestNumbers(t *testing.T) {
	uassert.Equal(t, "0", Itoa(0))
	uassert.Equal(t, "-12", Itoa(-12))
	uassert.Equal(t, "0", Itoa64(0))
	uassert.Equal(t, "1234567890123", Itoa64(1234567890123))
	uassert.Equal(t, 42, Atoi("42"))
	uassert.Equal(t, 0, Atoi("4a"))
	uassert.Equal(t, 0, Atoi(""))
	uassert.Equal(t, int64(-7), Atoi64("-7"))
	uassert.Equal(t, int64(0), Atoi64("x"))
	uassert.Equal(t, 42, MustAtoi("42"))
	uassert.Equal(t, int64(-7), MustAtoi64("-7"))
	for in, f := range map[string]func(){"4a": func() { MustAtoi("4a") }, "": func() { MustAtoi64("") }} {
		func() {
			defer func() { uassert.Equal(t, "text: not a number: "+in, recover()) }()
			f()
		}()
	}
	uassert.Equal(t, "1", Flag(true))
	uassert.Equal(t, "", Flag(false))
}

func TestURL(t *testing.T) {
	uassert.True(t, URLChars("a-Z_0.~:/?#=&%+@"))
	for _, s := range []string{"a b", "a\"b", "<x>", "a)b", "[x]", "é"} {
		uassert.False(t, URLChars(s), s)
	}
	uassert.True(t, HTTPS("https://a.example/x?y=1#z", 300))
	uassert.False(t, HTTPS("http://a.example/x", 300))
	uassert.False(t, HTTPS("https://ab", 300)) // 10 bytes
	uassert.True(t, HTTPS("https://abc", 11))
	uassert.False(t, HTTPS("https://abcd", 11))
	uassert.False(t, HTTPS("https://a.example/a b", 300))
}
