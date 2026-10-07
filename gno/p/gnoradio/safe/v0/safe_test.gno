package safe

import (
	"testing"

	"gno.land/p/nt/uassert/v0"
)

func TestNoteRules(t *testing.T) {
	for _, ok := range []string{"for Marie, happy birthday!", "Joyeux anniversaire Léa", "classic grass", "pop or no", "connaissance", "Room 101", "con amor", "love you xx", "Feliz cumpleaños",
		"Je t’aime Léa", "Łukasz i Ayşe", "Œuvre", "P.S. love you", "D.C. trip", "N.W.A for Dre", "happy 25.12.2024",
		"my pen is blue", "so do my best", "jogging", "setup for Lana", "Rapping all night", "Be yourself", "spices", "rock'n'roll"} {
		uassert.Equal(t, "", Note(ok, 40), ok)
	}
	bad := map[string]string{
		"visit x.com":     "no links",
		"bit.ly":          "no links",
		"06 12 34 56 78":  "no phone numbers",
		"call 0612345678": "no phone numbers",
		"hi <b>":          "letters, digits and . , ! ? ' - only",
		"hey @you":        "letters, digits and . , ! ? ' - only",
		" padded":         "no leading, trailing or double spaces",
		"a  b":            "no leading, trailing or double spaces",
		"this is a much too long dedication for air": "too long",
	}
	for s, why := range bad {
		uassert.Equal(t, why, Note(s, 40), s)
	}
}

func TestBlockedEvasions(t *testing.T) {
	for _, s := range []string{
		"fuck", "FUCK you", "fuuuuck", "f u c k", "fuckyou",
		"sh1t", "salope", "Salope!", "enculé", "connard", "fils de pute", "ta mère",
		"hurensohn", "puta madre", "vaffanculo", "filho da puta", "n1gger", "f4ggot",
		"kys", "kill yourself", "sieg heil", "free crypto airdrop scam",
		"fu-ck you", "s-h-i-t", "k y s", "con'nard", "shits", "kcuf", "reggin", "b!tch", "ßitch", "encu1e", "fıck",
		"paedophiles", "1488", "kill urself", "je vais te tuer", "send me your seed phrase", "kurwa",
	} {
		uassert.True(t, Blocked(s), s)
	}
}

func TestSlur(t *testing.T) {
	for _, s := range []string{"Nigger Kills", "Heil Hitler", "faggots", "nіgger"} { // і is Cyrillic
		uassert.True(t, Slur(s), s)
	}
	for _, s := range []string{"Sex Pistols", "Bitches Brew", "Fuck tha Police", "jogging"} {
		uassert.False(t, Slur(s), s)
	}
}

func TestScamLures(t *testing.T) {
	for _, s := range []string{"claim now!", "Free airdrop, claim yours", "giveaway 100x", "send USDT", "metamask support team", "recover your wallet", "free mint live", "link in bio", "join my telegram", "dm me on telegram"} {
		uassert.True(t, Blocked(s), s)
	}
	for _, s := range []string{"Fly me to the moon", "Telegram Sam on repeat", "bonus track for you", "for my king, mon roi", "happy birthday Claire"} {
		uassert.False(t, Blocked(s), s)
	}
}
