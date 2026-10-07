package text

import (
	"testing"

	"gno.land/p/nt/uassert/v0"
)

func TestText(t *testing.T) {
	uassert.Equal(t, "0000000042", Key(42))
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
