package home

import (
	"chain"
	"strings"

	"gno.land/r/gnoradio/catalog/v0"
)

const maxAppURL = 100

// appURL is the GnoRadio app (dApp) that gnoweb pages link to; "" hides the links.
var appURL string

// SetAppURL sets the app link shown on every page: an https URL of at most
// 100 characters from [A-Za-z0-9-._~/:%], or "" to remove it. Catalog admin only.
func SetAppURL(cur realm, url string) {
	if !cur.Previous().IsUserCall() || cur.Previous().Address() != catalog.Admin() {
		panic("home: catalog admin only")
	}
	if url != "" && !validAppURL(url) {
		panic("home: app URL must be https://, at most 100 characters of A-Z a-z 0-9 - . _ ~ / : %")
	}
	appURL = url
	chain.Emit("AppURLSet", "url", url)
}

func validAppURL(u string) bool {
	if !strings.HasPrefix(u, "https://") || len(u) <= len("https://") || len(u) > maxAppURL {
		return false
	}
	for _, c := range u {
		switch {
		case c >= 'a' && c <= 'z', c >= 'A' && c <= 'Z', c >= '0' && c <= '9':
		case strings.ContainsRune("-._~/:%", c):
		default:
			return false
		}
	}
	return true
}

// inApp links an app route (e.g. "track/12", "" for the player), or returns
// "" when no app URL is set.
func inApp(route, label string) string {
	if appURL == "" {
		return ""
	}
	return "[" + label + "](" + strings.TrimRight(appURL, "/") + "/" + route + ")"
}
