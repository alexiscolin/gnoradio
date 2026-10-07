// Package home is the GnoRadio website on gnoweb. It owns no data: every
// page is rendered from the catalog, radio and tickets realms.
package home

import (
	"chain/runtime"
	"chain/runtime/unsafe"
	"strconv"
	"strings"
	"time"

	"gno.land/p/gnoradio/safe/v0"
	"gno.land/p/gnoradio/text/v0"

	"gno.land/p/moul/txlink/v0"
	"gno.land/p/nt/markdown/sanitize/v0"

	"gno.land/r/gnoradio/catalog/v0"
	"gno.land/r/gnoradio/radio/v0"
	"gno.land/r/gnoradio/tickets/v0"
)

const (
	catalogPath = "gno.land/r/gnoradio/catalog/v0"
	radioPath   = "gno.land/r/gnoradio/radio/v0"
	ticketsPath = "gno.land/r/gnoradio/tickets/v0"
	maxCovers   = 8
	pageSize    = 20
	ugnot       = 1_000_000
)

var (
	catalogTx = txlink.Realm(catalogPath)
	radioTx   = txlink.Realm(radioPath)
	ticketsTx = txlink.Realm(ticketsPath)
)

// Render serves:
//
//	""                       home: main station on air, stations, new releases, top, concerts
//	"stations" "station/<n>" radio stations and their schedule
//	"track/<id>"             a track
//	"artist/<id|name>"       an artist
//	"album/<id>" "playlist/<id>"
//	"catalog?p=N&g=G" "artists?p=N" "albums?p=N" "playlists?p=N"
//	"concerts?p=N" "event/<id>" "ticket/<id>"
//	"listener/<g1…>"         a listener: likes, playlists, tickets, badges
//	"charts" "join" "about" "moderation?p=N"
//
// Bare entity segments ("track", "artist"…, linked by gnoweb's breadcrumb)
// open the matching list. Entity pages with long lists take ?p=N too.
//
// Raw path input is never echoed: ids are parsed, names and addresses looked up.
func Render(path string) string {
	p, query, _ := strings.Cut(path, "?")
	pg, genre := 1, 0
	for _, kv := range strings.Split(query, "&") {
		k, v, _ := strings.Cut(kv, "=")
		switch n := atoi(v); k {
		case "p":
			if n > 1 && n < 100000 {
				pg = n
			}
		case "g":
			if n >= 1 && n <= catalog.NumGenres {
				genre = n
			}
		}
	}
	out := route(p, pg, genre)
	if out == "" {
		out = header("Not found") + "This page does not exist. [← Back to the radio](" + page("") + ")\n"
	}
	if s := catalog.Successor(); s != "" {
		out = "> [!WARNING] GnoRadio has moved\n> The new version lives at [" + s + "](" +
			strings.TrimPrefix(s, runtime.ChainDomain()) + ").\n\n" + out
	} else if catalog.Frozen() {
		out = "> [!CAUTION] GnoRadio is paused\n> An upgrade is in progress. Tickets keep working.\n\n" + out
	}
	return out
}

func route(p string, pg, genre int) string {
	switch p {
	case "":
		return renderHome()
	case "stations", "station":
		return renderStations()
	case "catalog", "track":
		return renderCatalog(pg, genre)
	case "artists", "artist":
		return renderArtists(pg)
	case "albums", "album":
		return renderAlbums(pg)
	case "playlists", "playlist":
		return renderPlaylists(pg)
	case "concerts", "event", "ticket":
		return renderConcerts(pg)
	case "listener":
		return renderCharts()
	case "charts":
		return renderCharts()
	case "join":
		return renderJoin()
	case "about":
		return renderAbout()
	case "moderation":
		return renderModeration(pg)
	}
	kind, arg, ok := strings.Cut(p, "/")
	if !ok {
		return ""
	}
	switch kind {
	case "station":
		if n, err := strconv.Atoi(arg); err == nil && n >= 0 && n < radio.StationCount() {
			return renderStation(n)
		}
	case "track":
		if t, ok := catalog.GetTrack(atoi(arg)); ok {
			return renderTrack(t)
		}
	case "artist":
		id := atoi(arg)
		if id == 0 {
			id = catalog.ArtistByName(arg)
		}
		if a, ok := catalog.GetArtist(id); ok && !a.Hidden {
			return renderArtist(a, pg)
		}
	case "album":
		if al, ok := catalog.GetAlbum(atoi(arg)); ok && !al.Hidden && catalog.ArtistVisible(al.Artist) {
			return renderAlbum(al)
		}
	case "playlist":
		if pl, ok := catalog.GetPlaylist(atoi(arg)); ok && !pl.Hidden {
			return renderPlaylist(pl, pg)
		}
	case "event":
		if e, ok := tickets.EventInfo(atoi(arg)); ok && !e.Hidden && catalog.ArtistVisible(e.ArtistID) {
			return renderEvent(e)
		}
	case "ticket":
		if tk, ok := tickets.TicketInfo(atoi(arg)); ok {
			return renderTicket(tk)
		}
	case "listener":
		if addr := address(arg); addr.IsValid() {
			return renderListener(addr, pg)
		}
	}
	return ""
}

// ---- pages ----

func renderHome() string {
	var b strings.Builder
	b.WriteString("# GnoRadio\n\n" + nav())
	b.WriteString("**Community radio and open music player, 100% on-chain.** Every tip lands in the artist's wallet, in the same transaction. " +
		"[Read the code that guarantees it](" + sourceURL(catalogPath, "social.gno") + ").\n\n")
	if l := inApp("", "▶ Open the GnoRadio app"); l != "" {
		b.WriteString("**" + l + "**: the synced player, free to listen.\n\n")
	}
	b.WriteString(onAir(0))

	b.WriteString("<gno-columns>\n## Stations\n\n")
	n := radio.StationCount()
	for s := 0; s < n && s < 7; s++ {
		tracks, _, _ := radio.StationInfo(s)
		b.WriteString("- [" + radio.StationName(s) + "](" + page("station/"+itoa(s)) + ") · " + itoa(tracks) + "\n")
	}
	b.WriteString("\n[All stations →](" + page("stations") + ")\n")
	b.WriteString("<gno-columns-sep />\n## Most liked\n\n")
	shown := 0
	for _, r := range catalog.TopLiked() {
		if t, ok := catalog.GetTrack(atoi(r.Key)); ok && playable(t) && shown < 6 {
			shown++
			b.WriteString(itoa(shown) + ". " + trackLink(t) + " · ♥ " + itoa(t.Likes) + "\n")
		}
	}
	if shown == 0 {
		b.WriteString("No likes yet.\n")
	}
	b.WriteString("<gno-columns-sep />\n## Concerts\n\n")
	up := tickets.Upcoming(4)
	if len(up) == 0 {
		b.WriteString("No concert announced. [Announce yours](" + page("join") + ").\n")
	}
	for _, e := range up {
		b.WriteString("- [" + md(e.Title) + "](" + page("event/"+itoa(e.ID)) + ") · " + date(e.Start) + "\n")
	}
	b.WriteString("</gno-columns>\n\n## New releases\n\n")
	shown = 0
	for _, id := range catalog.TrackPage(0, 40, true) {
		if t, ok := catalog.GetTrack(id); ok && playable(t) {
			b.WriteString("[" + coverSVG(t.ID, t.Title, 150) + "](" + page("track/"+itoa(t.ID)) + ")")
			shown++
			if shown == maxCovers {
				break
			}
		}
	}
	if shown == 0 {
		b.WriteString("> [!INFO] The catalog is empty\n> [Publish the first track](" + page("join") + ").\n")
	}
	b.WriteString("\n\n[Full catalog →](" + page("catalog") + ")\n\n")
	b.WriteString("<gno-columns>\n" + supportBlock() + "<gno-columns-sep />\n## Recent activity\n\n" + activityFeed(8) + "</gno-columns>\n\n---\n\n" + stats())
	return b.String()
}

// supportBlock shows GnoRadio's own funding: treasury, monthly goal, links.
func supportBlock() string {
	to, total, supporters, monthTotal, goal := catalog.SupportInfo()
	var b strings.Builder
	b.WriteString("## Keep GnoRadio on air\n\n")
	if goal > 0 {
		b.WriteString("This month: **" + text.GNOT(monthTotal) + "** of " + text.GNOT(goal) + "  \n")
	} else {
		b.WriteString("This month: **" + text.GNOT(monthTotal) + "**  \n")
	}
	b.WriteString(text.GNOT(total) + " from " + itoa(supporters) + " supporters since launch")
	if to.IsValid() {
		b.WriteString(", to the treasury " + who(to))
	}
	b.WriteString(".\n\n**◈ Support:** [1 GNOT](" + supportURL(1) + ") · [5 GNOT](" + supportURL(5) + ") · [20 GNOT](" + supportURL(20) + ")  \n" +
		"Pays hosting and the indexer. Artists' tips never fund it. [Read the code](" + sourceURL(catalogPath, "support.gno") + ").\n")
	return b.String()
}

// activityFeed lists the latest public actions, newest first.
func activityFeed(n int) string {
	var b strings.Builder
	for _, a := range catalog.Activities(n) {
		line := ""
		switch a.Kind {
		case "publish":
			line = "published " + trackRef(a.Track)
		case "like":
			line = "liked " + trackRef(a.Track)
		case "tip":
			line = "tipped " + text.GNOT(a.Amount) + " on " + trackRef(a.Track)
		case "support":
			line = "supported GnoRadio with " + text.GNOT(a.Amount)
		case "follow":
			line = "followed " + artistRef(a.Artist)
		case "playlist":
			line = "published [a playlist](" + page("playlist/"+itoa(a.Track)) + ")"
		case "album":
			line = "released [an album](" + page("album/"+itoa(a.Track)) + ")"
		default:
			line = md(a.Kind)
		}
		b.WriteString("- " + who(a.By) + " " + line + " · " + date(a.At) + "\n")
	}
	if b.Len() == 0 {
		return "Nothing yet: like, tip or publish to start the feed.\n"
	}
	return b.String()
}

func onAir(st int) string {
	id, off, queued := radio.NowPlaying(st)
	t, ok := catalog.GetTrack(id)
	if id == 0 || !ok || !playable(t) {
		return onAirSVG(radio.StationName(st), "", "", 0, 0) + "\n\n"
	}
	src := "rotation"
	if queued {
		src = "queued by a listener"
		if n := radio.OnAirNote(st); n != "" {
			src += " · ♥ *" + md(n) + "*"
		}
	}
	live := ""
	if l := inApp("stations", "Go live in the app"); l != "" {
		live = " · " + l
	}
	return onAirSVG(radio.StationName(st), t.Title, catalog.ArtistName(t.Artist), off, t.Duration) + "\n\n" +
		"**[▶ Listen from " + clock(off) + "](" + listenURL(t, off) + ")** · " + trackLink(t) + " · " + src + live + "\n\n"
}

func renderStations() string {
	var b strings.Builder
	b.WriteString(header("Stations"))
	b.WriteString("Every station plays the same second for everyone. Pick one, or queue a track on it from any track page.")
	if l := inApp("stations", "Listen in the app"); l != "" {
		b.WriteString(" " + l + ".")
	}
	b.WriteString("\n\n")
	b.WriteString("| Station | Tracks | Loop | Queued | On air |\n|---|---|---|---|---|\n")
	for s := 0; s < radio.StationCount(); s++ {
		tracks, loop, queued := radio.StationInfo(s)
		now := "—"
		if id, _, _ := radio.NowPlaying(s); id != 0 {
			now = md(catalog.TrackTitle(id))
		}
		b.WriteString("| [" + radio.StationName(s) + "](" + page("station/"+itoa(s)) + ") | " + itoa(tracks) + " | " + span(loop) + " | " + itoa(queued) + " | " + now + " |\n")
	}
	if p := radio.Pending(); p > 0 {
		b.WriteString("\n" + itoa(p) + " new tracks are waiting to join the stations: [sync them](" + radioTx.NewLink("Sync").AddArgs("max", "200").URL() + ") (anyone can).\n")
	}
	return b.String()
}

func renderStation(st int) string {
	var b strings.Builder
	b.WriteString(header(radio.StationName(st)))
	tracks, loop, _ := radio.StationInfo(st)
	if tracks == 0 {
		b.WriteString("> [!INFO] This station is empty for now\n> " + genreBrowse(st) + "\n\n")
		return b.String()
	}
	b.WriteString(onAir(st))
	b.WriteString("## Up next\n\n")
	next := radio.UpNext(st)
	if len(next) == 0 {
		b.WriteString("Nothing queued: the rotation plays. " + genreBrowse(st) + "\n")
	}
	for i, s := range next {
		if i == 10 {
			break
		}
		if t, ok := catalog.GetTrack(s.Track); ok {
			line := "- " + hour(s.Start) + " UTC · " + trackLink(t) + " · queued by " + who(s.By)
			if s.Note != "" {
				line += " · ♥ *" + md(s.Note) + "*"
			}
			b.WriteString(line + "\n")
		}
	}
	b.WriteString("\n" + itoa(tracks) + " tracks in rotation · one loop lasts " + span(loop) + ".\n")
	return b.String()
}

func renderTrack(t catalog.Track) string {
	if !playable(t) {
		return header("Track removed") + "> [!WARNING] Removed by moderation\n> This track is no longer available.\n"
	}
	a, _ := catalog.GetArtist(t.Artist)
	var b strings.Builder
	b.WriteString(header(md(t.Title)))
	b.WriteString("<gno-columns>\n" + coverSVG(t.ID, t.Title, 300) + "\n<gno-columns-sep />\n")
	b.WriteString("### by " + artistLink(a) + "\n\n")
	b.WriteString(catalog.GenreName(t.Genre) + " · " + clock(t.Duration) + " · " + licenseLink(t.License))
	if t.CMO == "sacem-nc" {
		b.WriteString(" · declared to SACEM")
	}
	b.WriteString("  \n")
	if t.Credits != "" {
		b.WriteString("Credits: " + md(t.Credits) + "  \n")
	}
	b.WriteString("♥ " + itoa(t.Likes) + " · ◈ " + text.GNOT(t.Tips) + " from " + itoa(t.Supporters) + " supporters\n\n")
	b.WriteString("**[▶ Listen](" + listenURL(t, 0) + ")**")
	if t.Album != 0 {
		if al, ok := catalog.GetAlbum(t.Album); ok {
			b.WriteString(" · from [" + md(al.Title) + "](" + page("album/"+itoa(al.ID)) + ")")
		}
	}
	b.WriteString("\n\n[♥ Like](" + catalogTx.NewLink("Like").AddArgs("trackID", itoa(t.ID)).URL() + ") · " +
		"[Unlike](" + catalogTx.NewLink("Unlike").AddArgs("trackID", itoa(t.ID)).URL() + ") · " +
		"Queue on [Main](" + queueURL(0, t.ID) + ") or [" + radio.StationName(t.Genre) + "](" + queueURL(t.Genre, t.ID) + ")")
	if l := inApp("track/"+itoa(t.ID), "Open in the app"); l != "" {
		b.WriteString(" · " + l)
	}
	b.WriteString("\n\n")
	b.WriteString(support(t, a))
	b.WriteString("</gno-columns>\n\n")

	switch t.Origin {
	case catalog.OriginCurated:
		b.WriteString("> [!NOTE] Curated · " + t.License + "\n> " + md(t.Attribution) + ". [Source](" + t.SourceURL + ").\n\n")
	case catalog.OriginAudius:
		b.WriteString("> [!NOTE] Streamed from Audius\n> " + md(t.Attribution) + ". © the artist. Licensed to GnoRadio under the Audius Open Music License. [Listen on Audius](" + t.SourceURL + ").\n\n")
	}

	if len(t.Splits) > 0 {
		b.WriteString("## Where your tip goes\n\n| Recipient | Share |\n|---|---|\n")
		rest := int64(100)
		for _, s := range t.Splits {
			b.WriteString("| " + who(s.To) + " | " + itoa64(s.Pct) + "% |\n")
			rest -= s.Pct
		}
		b.WriteString("| " + artistLink(a) + " (artist) | " + itoa64(rest) + "% |\n\n")
	}
	b.WriteString("## Early listeners\n\n")
	for i, addr := range t.Early {
		b.WriteString(itoa(i+1) + ". " + who(addr) + "\n")
	}
	if len(t.Early) < 10 {
		b.WriteString("\n**" + itoa(10-len(t.Early)) + "** early-listener badges left: [like it now](" + catalogTx.NewLink("Like").AddArgs("trackID", itoa(t.ID)).URL() + ").\n")
	}
	b.WriteString("\n---\n\n**Fingerprints.** Audio `" + t.Audio + "`")
	if t.AudioSHA != "" {
		b.WriteString(" · sha256 `" + t.AudioSHA + "`")
	}
	if t.Cover != "" {
		b.WriteString("  \nCover `" + t.Cover + "`")
		if t.CoverSHA != "" {
			b.WriteString(" · sha256 `" + t.CoverSHA + "`")
		}
	}
	b.WriteString("  \nPublished " + date(t.Created) + " · [Report](" +
		catalogTx.NewLink("Report").AddArgs("kind", "track", "target", itoa(t.ID), "reason", "").URL() + ")\n")
	return b.String()
}

// support explains how this track can be supported, by origin and claim.
func support(t catalog.Track, a catalog.Artist) string {
	if tippable(a) {
		to := "100% of the artist share goes to the artist"
		if n := len(t.Splits); n == 1 {
			to = "The artist share is split with 1 collaborator"
		} else if n > 1 {
			to = "The artist share is split with " + itoa(n) + " collaborators"
		}
		return "**◈ Tip:** [1 GNOT](" + tipURL(t.ID, 1) + ") · [5 GNOT](" + tipURL(t.ID, 5) + ") · [20 GNOT](" + tipURL(t.ID, 20) + ")  \n" +
			"Or [5 GNOT + 10% to keep GnoRadio on air](" + tipSupportURL(t.ID, 5, 10) + ").  \n" + to + ", same transaction.\n"
	}
	if t.Origin == catalog.OriginAudius && a.Source != "" {
		return "**[Support on Audius](" + a.Source + ")** · Is this you? " + verifyLink(a.ID) + "\n"
	}
	return "Tips open once the artist verifies this profile. Is this you? " + verifyLink(a.ID) + "\n"
}

func renderArtist(a catalog.Artist, pg int) string {
	var b strings.Builder
	title := md(a.Name)
	if a.Verified {
		title += " ✓"
	}
	b.WriteString(header(title))
	b.WriteString("<gno-columns>\n" + avatarSVG(itoa(a.ID)+a.Name, 160) + "\n<gno-columns-sep />\n")
	if a.Bio != "" {
		b.WriteString(md(a.Bio) + "\n\n")
	}
	switch {
	case a.Owner != "":
		b.WriteString("◈ **" + text.GNOT(a.Tips) + "** received · " + itoa(a.Followers) + " followers  \nWallet: [" + short(a.Owner) + "](" + page("listener/"+a.Owner.String()) + ")\n\n")
	case a.Kind == catalog.OriginAudius:
		b.WriteString("Streamed from [Audius](" + a.Source + ") · " + itoa(a.Followers) + " followers  \nNot verified yet: is this you? " + verifyLink(a.ID) + "\n\n")
	default:
		src := ""
		if a.Source != "" {
			src = " · [source](" + a.Source + ")"
		}
		b.WriteString("Curated CC artist" + src + " · " + itoa(a.Followers) + " followers  \nNot verified yet: is this you? " + verifyLink(a.ID) + "\n\n")
	}
	b.WriteString("[Follow](" + catalogTx.NewLink("Follow").AddArgs("artistID", itoa(a.ID)).URL() + ") · " +
		"[Unfollow](" + catalogTx.NewLink("Unfollow").AddArgs("artistID", itoa(a.ID)).URL() + ")")
	if l := inApp("artist/"+itoa(a.ID), "Open in the app"); l != "" {
		b.WriteString(" · " + l)
	}
	b.WriteString("\n</gno-columns>\n\n")

	// Tracks, newest first, pageSize per page; page 1 shows the first covers.
	b.WriteString("## Tracks\n\n")
	shown := 0
	var rows strings.Builder
	hi := len(a.Tracks) - (pg-1)*pageSize
	for i := hi - 1; i >= 0 && i >= hi-pageSize; i-- {
		t, ok := catalog.GetTrack(a.Tracks[i])
		if !ok || !playable(t) {
			continue
		}
		if pg == 1 && shown < maxCovers {
			b.WriteString("[" + coverSVG(t.ID, t.Title, 150) + "](" + page("track/"+itoa(t.ID)) + ")")
		} else {
			rows.WriteString("- " + trackLink(t) + "\n")
		}
		shown++
	}
	if shown == 0 {
		b.WriteString("No track yet.")
	}
	b.WriteString("\n\n" + rows.String() + "\n" + pager("artist/"+itoa(a.ID), pg, len(a.Tracks)) + "\n")
	if len(a.Albums) > 0 {
		b.WriteString("## Albums\n\n")
		for _, id := range a.Albums {
			if al, ok := catalog.GetAlbum(id); ok && !al.Hidden {
				b.WriteString("- [" + md(al.Title) + "](" + page("album/"+itoa(al.ID)) + ") · " + itoa(al.Year) + "\n")
			}
		}
		b.WriteString("\n")
	}
	if evs := tickets.ArtistEvents(a.ID, 10); len(evs) > 0 {
		b.WriteString("## Concerts\n\n")
		for _, id := range evs {
			if e, ok := tickets.EventInfo(id); ok && !e.Hidden {
				b.WriteString("- [" + md(e.Title) + "](" + page("event/"+itoa(e.ID)) + ") · " + md(e.Venue) + " · " + date(e.Start) + "\n")
			}
		}
	}
	b.WriteString("\n[Report this profile](" + catalogTx.NewLink("Report").AddArgs("kind", "artist", "target", itoa(a.ID), "reason", "").URL() + ")\n")
	return b.String()
}

func renderAlbum(al catalog.Album) string {
	var b strings.Builder
	a, _ := catalog.GetArtist(al.Artist)
	b.WriteString(header(md(al.Title)))
	b.WriteString("<gno-columns>\n" + coverSVG(al.ID*7919, al.Title, 260) + "\n<gno-columns-sep />\n")
	var total int64
	var tips int64
	for _, id := range al.Tracks {
		if t, ok := catalog.GetTrack(id); ok {
			total += t.Duration
			tips += t.Tips
		}
	}
	b.WriteString("### " + artistLink(a) + "\n\n" + itoa(al.Year) + " · " + itoa(len(al.Tracks)) + " tracks · " + clock(total) + " · ◈ " + text.GNOT(tips) + "\n</gno-columns>\n\n")
	b.WriteString("| # | Track | Time | ♥ |\n|---|---|---|---|\n")
	for i, id := range al.Tracks {
		if t, ok := catalog.GetTrack(id); ok && playable(t) {
			b.WriteString("| " + itoa(i+1) + " | [" + md(t.Title) + "](" + page("track/"+itoa(t.ID)) + ") | " + clock(t.Duration) + " | " + itoa(t.Likes) + " |\n")
		}
	}
	b.WriteString("\n")
	if l := inApp("album/"+itoa(al.ID), "Play it in the app"); l != "" {
		b.WriteString(l + " · ")
	}
	b.WriteString("[Report this album](" + catalogTx.NewLink("Report").AddArgs("kind", "album", "target", itoa(al.ID), "reason", "").URL() + ")\n")
	return b.String()
}

func renderPlaylist(pl catalog.Playlist, pg int) string {
	var b strings.Builder
	b.WriteString(header(md(pl.Title)))
	b.WriteString("Playlist by " + who(pl.Owner) + " · " + itoa(len(pl.Tracks)) + " tracks · updated " + date(pl.Updated))
	if l := inApp("playlist/"+itoa(pl.ID), "Play it in the app"); l != "" {
		b.WriteString(" · " + l)
	}
	b.WriteString("\n\n| # | Track | Artist | Time |\n|---|---|---|---|\n")
	for i := (pg - 1) * pageSize; i < len(pl.Tracks) && i < pg*pageSize; i++ {
		if t, ok := catalog.GetTrack(pl.Tracks[i]); ok && playable(t) {
			b.WriteString("| " + itoa(i+1) + " | [" + md(t.Title) + "](" + page("track/"+itoa(t.ID)) + ") | " + artistRef(t.Artist) + " | " + clock(t.Duration) + " |\n")
		}
	}
	b.WriteString("\n" + pager("playlist/"+itoa(pl.ID), pg, len(pl.Tracks)))
	b.WriteString("\n[Report this playlist](" + catalogTx.NewLink("Report").AddArgs("kind", "playlist", "target", itoa(pl.ID), "reason", "").URL() + ")\n")
	return b.String()
}

func renderCatalog(pg, genre int) string {
	var b strings.Builder
	route, total := "catalog", catalog.TrackCount()
	ids := catalog.TrackPage((pg-1)*pageSize, pageSize, true)
	if genre > 0 {
		route, total = "catalog?g="+itoa(genre), catalog.GenreCount(genre)
		ids = catalog.GenrePage(genre, (pg-1)*pageSize, pageSize)
		b.WriteString(header("Catalog · " + catalog.GenreName(genre)))
	} else {
		b.WriteString(header("Catalog"))
	}
	b.WriteString("Browse: [all](" + page("catalog") + ")")
	for g := 1; g <= catalog.NumGenres; g++ {
		b.WriteString(" · [" + catalog.GenreName(g) + "](" + page("catalog?g="+itoa(g)) + ")")
	}
	b.WriteString(" · [Artists](" + page("artists") + ") · [Albums](" + page("albums") + ") · [Playlists](" + page("playlists") + ")\n\n")
	if len(ids) == 0 {
		b.WriteString("> [!INFO] No track here yet\n> [Publish one](" + page("join") + ").\n")
		return b.String()
	}
	b.WriteString("| # | Track | Artist | Genre | Time | License | ♥ |\n|---|---|---|---|---|---|---|\n")
	for _, id := range ids {
		if t, ok := catalog.GetTrack(id); ok && playable(t) {
			b.WriteString("| " + itoa(t.ID) + " | [" + md(t.Title) + "](" + page("track/"+itoa(t.ID)) + ") | " + artistRef(t.Artist) +
				" | " + catalog.GenreName(t.Genre) + " | " + clock(t.Duration) + " | " + t.License + " | " + itoa(t.Likes) + " |\n")
		}
	}
	b.WriteString("\n" + pager(route, pg, total))
	return b.String()
}

func renderArtists(pg int) string {
	var b strings.Builder
	b.WriteString(header("Artists"))
	b.WriteString("| Artist | Kind | Tracks | Followers | Tips |\n|---|---|---|---|---|\n")
	for _, id := range catalog.ArtistPage((pg-1)*pageSize, pageSize) {
		if a, ok := catalog.GetArtist(id); ok && !a.Hidden {
			kind := "artist"
			if a.Owner == "" {
				kind = a.Kind + " · unclaimed"
			}
			b.WriteString("| " + artistLink(a) + " | " + kind + " | " + itoa(len(a.Tracks)) + " | " + itoa(a.Followers) + " | " + text.GNOT(a.Tips) + " |\n")
		}
	}
	b.WriteString("\n" + pager("artists", pg, catalog.ArtistCount()))
	return b.String()
}

func renderAlbums(pg int) string {
	var b strings.Builder
	b.WriteString(header("Albums"))
	for _, id := range catalog.AlbumPage((pg-1)*pageSize, pageSize) {
		if al, ok := catalog.GetAlbum(id); ok && !al.Hidden && catalog.ArtistVisible(al.Artist) {
			b.WriteString("- [" + md(al.Title) + "](" + page("album/"+itoa(al.ID)) + ") · " + artistRef(al.Artist) + " · " + itoa(al.Year) + "\n")
		}
	}
	b.WriteString("\n" + pager("albums", pg, catalog.AlbumCount()))
	return b.String()
}

func renderPlaylists(pg int) string {
	var b strings.Builder
	b.WriteString(header("Playlists"))
	for _, id := range catalog.PlaylistPage((pg-1)*pageSize, pageSize) {
		if owner, title, n, hidden, ok := catalog.PlaylistBrief(id); ok && !hidden {
			b.WriteString("- [" + md(title) + "](" + page("playlist/"+itoa(id)) + ") · " + itoa(n) + " tracks · by " + who(owner) + "\n")
		}
	}
	b.WriteString("\n" + pager("playlists", pg, catalog.PlaylistCount()))
	return b.String()
}

// maxPastScan bounds how many concert ids one past-concerts page reads.
const maxPastScan = 300

func renderConcerts(pg int) string {
	var b strings.Builder
	b.WriteString(header("Concerts"))
	if pg == 1 {
		b.WriteString("## Upcoming\n\n")
		up := tickets.Upcoming(20)
		if len(up) == 0 {
			b.WriteString("No concert announced. [Announce yours](" + page("join") + ").\n")
		}
		for _, e := range up {
			b.WriteString("- **" + date(e.Start) + "** · [" + md(e.Title) + "](" + page("event/"+itoa(e.ID)) + ") · " +
				artistRef(e.ArtistID) + " · " + md(e.Venue) + "\n")
		}
		if l := inApp("concerts", "Get tickets in the app"); l != "" {
			b.WriteString("\n" + l + "\n")
		}
	}
	// Past concerts, newest first: ids are scanned downwards, skipping
	// future and hidden ones.
	b.WriteString("\n## Past concerts\n\n")
	now := time.Now().Unix()
	skip, shown, more := (pg-1)*pageSize, 0, false
	// The scan budget grows with the page so older pages stay reachable.
	budget := skip + maxPastScan
	for id, scanned := tickets.EventCount(), 0; id >= 1 && scanned < budget; id, scanned = id-1, scanned+1 {
		e, ok := tickets.EventInfo(id)
		if !ok || e.Start > now {
			continue
		}
		if skip > 0 {
			skip--
			continue
		}
		if shown == pageSize {
			more = true
			break
		}
		state := ""
		if e.Cancelled {
			state = " · cancelled"
		}
		b.WriteString("- " + date(e.Start) + " · [" + md(e.Title) + "](" + page("event/"+itoa(e.ID)) + ") · " + artistRef(e.ArtistID) + state + "\n")
		shown++
	}
	if shown == 0 {
		b.WriteString("No past concert yet.\n")
	}
	b.WriteString("\n" + pagerMore("concerts", pg, more))
	return b.String()
}

func renderEvent(e tickets.Event) string {
	var b strings.Builder
	b.WriteString(header(md(e.Title)))
	b.WriteString(tickets.EventSVG(e.ID) + "\n\n")
	a, _ := catalog.GetArtist(e.ArtistID)
	b.WriteString("**" + artistLink(a) + "** · " + md(e.Venue) + " · **" + date(e.Start) + "** · seats **" + itoa(e.Sold) + " / " + itoa(e.Capacity) + "**\n\n")
	if e.Link != "" && a.Verified { // an unverified profile's link may be phishing
		b.WriteString("Link: [" + e.Link + "](" + e.Link + ") (public)\n\n")
	}
	switch {
	case e.Cancelled:
		b.WriteString("> [!CAUTION] Cancelled\n> Payments went straight to the artist: contact them for a refund.\n")
	case time.Now().Unix() >= e.Start:
		b.WriteString("> [!NOTE] Past concert\n> Tickets stay in their holders' collections.\n")
	case e.Sold >= e.Capacity:
		b.WriteString("> [!WARNING] Sold out\n")
	case e.Price > 0 && !tippable(a):
		b.WriteString("> [!NOTE] Tickets open once the artist verifies this profile\n> Is this you? " + verifyLink(a.ID) + "\n")
	default:
		link := ticketsTx.NewLink("BuyTicket").AddArgs("eventID", itoa(e.ID))
		label, limit := "Get a free ticket", "one free ticket per wallet"
		if e.Price > 0 {
			fee := tickets.ServiceFee()
			link = link.SetSend(strconv.FormatInt(e.Price+fee, 10) + "ugnot")
			label, limit = "Buy for "+text.GNOT(e.Price+fee), "up to 4 per wallet"
			if fee > 0 {
				limit = text.GNOT(e.Price) + " to the artist + " + text.GNOT(fee) + " GnoRadio service fee · " + limit
			}
		}
		b.WriteString("**[" + label + "](" + link.URL() + ")** · " + limit + "\n\n")
		b.WriteString("Your ticket is an NFT drawn on-chain, in your name. 100% of the ticket price goes to the artist. " +
			"You can gift it; there is no resale market. At the door the artist checks it in and it becomes an \"I was there\" keepsake.\n")
	}
	b.WriteString("\n[← All concerts](" + page("concerts") + ")\n")
	return b.String()
}

func renderTicket(tk tickets.Ticket) string {
	var b strings.Builder
	e, ok := tickets.EventInfo(tk.Event)
	if !ok {
		b.WriteString(header("Ticket #" + itoa(tk.Serial)))
		b.WriteString(tickets.TicketSVG(tk.ID) + "\n\n")
		b.WriteString("> [!NOTE] Removed by moderation\n> This concert is no longer listed. The ticket stays in its holder's collection.\n\n")
		b.WriteString("Holder: " + who(tickets.TicketOwner(tk.ID)) + "\n")
		return b.String()
	}
	b.WriteString(header("Ticket #" + itoa(tk.Serial) + " · " + md(e.Title)))
	b.WriteString(tickets.TicketSVG(tk.ID) + "\n\n")
	b.WriteString("Holder: " + who(tickets.TicketOwner(tk.ID)) + " · [concert](" + page("event/"+itoa(e.ID)) + ")\n\n")
	if !tk.Attended && !e.Cancelled {
		b.WriteString("Holder: [gift this ticket](" + ticketsTx.NewLink("TransferTicket").AddArgs("to", "", "ticketID", itoa(tk.ID)).URL() + ") · " +
			"Artist: [check in at the door](" + ticketsTx.NewLink("CheckIn").AddArgs("ticketID", itoa(tk.ID)).URL() + ")\n")
	}
	return b.String()
}

func renderListener(addr address, pg int) string {
	var b strings.Builder
	b.WriteString(header("Listener " + short(addr)))
	if id := catalog.ArtistOf(addr); id != 0 {
		if a, ok := catalog.GetArtist(id); ok && !a.Hidden {
			b.WriteString("Also the artist " + artistLink(a) + ".\n\n")
		}
	}
	likes, follows, tipped, lists := catalog.UserStats(addr)
	b.WriteString("♥ " + itoa(likes) + " likes · " + itoa(follows) + " follows · ◈ " + text.GNOT(tipped) + " given · " + itoa(tickets.Attended(addr)) + " concerts attended\n\n")
	if len(lists) > 0 {
		b.WriteString("## Playlists\n\n")
		for _, id := range lists {
			if _, title, n, hidden, ok := catalog.PlaylistBrief(id); ok && !hidden {
				b.WriteString("- [" + md(title) + "](" + page("playlist/"+itoa(id)) + ") · " + itoa(n) + " tracks\n")
			}
		}
		b.WriteString("\n")
	}
	route := "listener/" + addr.String()
	b.WriteString("## Tickets\n\n")
	ids := tickets.TicketsOf(addr, (pg-1)*pageSize, pageSize)
	if len(ids) == 0 {
		b.WriteString("No ticket. [See concerts](" + page("concerts") + ").\n")
	}
	for _, id := range ids {
		if tk, ok := tickets.TicketInfo(id); ok {
			e, ok := tickets.EventInfo(tk.Event)
			if !ok {
				b.WriteString("- [Removed by moderation #" + itoa(tk.Serial) + "](" + page("ticket/"+itoa(tk.ID)) + ")\n")
				continue
			}
			state := ""
			if tk.Attended {
				state = " · ✓ I was there"
			}
			b.WriteString("- [" + md(e.Title) + " #" + itoa(tk.Serial) + "](" + page("ticket/"+itoa(tk.ID)) + ") · " + date(e.Start) + state + "\n")
		}
	}
	liked := catalog.LikedPage(addr, (pg-1)*pageSize, pageSize)
	b.WriteString("\n## Likes\n\n")
	var badges strings.Builder
	shown := 0
	for _, id := range liked {
		if t, ok := catalog.GetTrack(id); ok && playable(t) {
			b.WriteString("- " + trackLink(t) + "\n")
			for i, e := range t.Early {
				if e == addr && shown < maxCovers {
					badges.WriteString("[" + badgeSVG(t.Title, i+1) + "](" + page("track/"+itoa(t.ID)) + ")")
					shown++
				}
			}
		}
	}
	if len(liked) == 0 {
		b.WriteString("No like yet.\n")
	}
	b.WriteString("\n## Follows\n\n")
	followed := catalog.FollowsPage(addr, (pg-1)*pageSize, pageSize)
	for _, id := range followed {
		if a, ok := catalog.GetArtist(id); ok && !a.Hidden {
			b.WriteString("- " + artistLink(a) + "\n")
		}
	}
	if len(followed) == 0 {
		b.WriteString("Follows no artist yet.\n")
	}
	b.WriteString("\n## Early-listener badges\n\n")
	if shown == 0 {
		b.WriteString("No early-listener badge on this page: be among the first 10 to like a new track.")
	}
	b.WriteString(badges.String() + "\n\n")
	more := len(ids) == pageSize || len(liked) == pageSize || len(followed) == pageSize
	b.WriteString(pagerMore(route, pg, more))
	return b.String()
}

func renderCharts() string {
	var b strings.Builder
	b.WriteString(header("Charts"))
	b.WriteString("## Most supported artists\n\n")
	var rows []bar
	for _, r := range catalog.TopArtists() {
		if a, ok := catalog.GetArtist(atoi(r.Key)); ok && !a.Hidden {
			rows = append(rows, bar{a.Name, r.Value})
		}
	}
	if len(rows) == 0 {
		b.WriteString("> [!INFO] No tips yet\n> Open a track by a claimed artist and support them.\n\n")
	} else {
		b.WriteString(barsSVG(rows, text.GNOT) + "\n\n")
	}
	b.WriteString("## Most liked tracks\n\n| # | Track | ♥ | Supporters |\n|---|---|---|---|\n")
	n := 0
	for _, r := range catalog.TopLiked() {
		if t, ok := catalog.GetTrack(atoi(r.Key)); ok && playable(t) {
			n++
			b.WriteString("| " + itoa(n) + " | " + trackLink(t) + " | " + itoa(t.Likes) + " | " + itoa(t.Supporters) + " |\n")
		}
	}
	if n == 0 {
		b.WriteString("| | No likes yet | | |\n")
	}
	b.WriteString("\n## Top supporters\n\n")
	fans := catalog.TopFans()
	if len(fans) == 0 {
		b.WriteString("> [!INFO] No supporter yet\n> Tips to artists put you on this board.\n")
	}
	for i, r := range fans {
		b.WriteString(itoa(i+1) + ". " + who(address(r.Key)) + " · " + text.GNOT(r.Value) + "\n")
	}
	return b.String()
}

func renderJoin() string {
	return header("Join GnoRadio") +
		"**0. Your wallet is your identity.** Install [Adena](https://adena.app). Each step below opens a transaction you sign in your wallet.\n\n" +
		"## Artists\n\n" +
		"1. [Create your artist profile](" + catalogTx.NewLink("RegisterArtist").AddArgs("name", "", "bio", "").URL() + ") (Latin letters, 2-40 characters).\n" +
		"2. Export **MP3 320 kbps** or **Opus 160 kbps** around **-14 LUFS**, upload it to IPFS (or an allowed host) and note its sha256.\n" +
		"3. [Publish a track](" + catalogTx.NewLink("PublishTrack").URL() + "): genre 1-12, duration as 3:45, license (CC0, CC BY, CC BY-SA, CC BY-NC… or ALL-RIGHTS-RESERVED), " +
		"collaborators as `g1…:30` in percent, and answer `yes` to: *\"" + catalog.RightsTerms() + "\"*\n" +
		"4. [Group tracks into an album](" + catalogTx.NewLink("CreateAlbum").URL() + ") and [announce a concert](" + ticketsTx.NewLink("CreateEvent").URL() + ").\n\n" +
		"> [!CAUTION] SACEM members\n> Only works declared under a non-commercial CC license: use `sacem-nc` and a CC BY-NC license.\n\n" +
		"## Your music is already here?\n\n" +
		"Curated CC tracks and Audius tracks start on **unclaimed** profiles. To claim yours, publish your g1 address on a page you control " +
		"(Bandcamp, website, Audius bio), open your profile from [the artists list](" + page("artists") + ") and follow its **Claim it** link: " +
		"it files a public claim with the reason `claim: <your link>`. Once the moderator verifies it, tips and concerts open.\n\n" +
		"## Listeners\n\n[Publish a public playlist](" + catalogTx.NewLink("PublishPlaylist").URL() + ") with track ids like `12,40,7`. Private playlists and saves live in the app, for free.\n\n" +
		"Genres: " + genreList() + "\n"
}

func renderAbout() string {
	return header("How it works") +
		"<gno-columns>\n" +
		"### Library and Live\n\nPlay any album or playlist in any order, or tune into a station where everyone hears the same second. The schedule lives on-chain; there is no streaming server to switch off.\n" +
		"<gno-columns-sep />\n" +
		"### 0% fee, provably\n\nTips and tickets never stay in the contracts: they reach the artist and their collaborators in the same transaction. Don't trust us, read the code.\n" +
		"<gno-columns-sep />\n" +
		"### Tickets that remember\n\nEach ticket is an NFT drawn by the contract, in your name. Gift it, get it checked in at the door, keep it after the show.\n" +
		"</gno-columns>\n\n" +
		"## Who does what\n\n" +
		"- **Here (gnoweb):** catalog, profiles, support, tickets and the on-chain proof. Every page is rendered by a contract.\n" +
		"- **The GnoRadio app:** the synced player, uploads, your library. Listening never needs a transaction." + appLine() + "\n" +
		"- **Audio:** IPFS, Arweave, allowed hosts (archive.org) and Audius. Metadata, links and fingerprints live on gno.land.\n\n" +
		"## Rules\n\n- Publish only music you own the rights to. Curated tracks are CC0, CC BY or CC BY-SA with attribution; Audius tracks follow the Audius Open Music License.\n" +
		"- Published files stay public: moderation can hide, not erase. Reports are public on [the moderation page](" + page("moderation") + ").\n\n" +
		"## Verify it yourself\n\n" +
		"- Tips and splits: [social.gno](" + sourceURL(catalogPath, "social.gno") + ") · GnoRadio funding: [support.gno](" + sourceURL(catalogPath, "support.gno") + ")\n" +
		"- Stations and queue: [radio.gno](" + sourceURL(radioPath, "radio.gno") + ") · Tickets and fees: [tickets.gno](" + sourceURL(ticketsPath, "tickets.gno") + ")\n" +
		"- Moderation powers: [moderation.gno](" + sourceURL(catalogPath, "moderation.gno") + "). Current moderator: " + who(catalog.Admin()) + ".\n"
}

func renderModeration(pg int) string {
	var b strings.Builder
	b.WriteString(header("Moderation"))
	b.WriteString("Moderator: " + who(catalog.Admin()) + ". Reports are public; decisions are visible transactions.\n\n")
	if catalog.ReportCount() == 0 {
		b.WriteString("> [!SUCCESS] No open report\n> Use the Report link on any track, artist, album or playlist.\n")
		return b.String()
	}
	b.WriteString("| # | Date | Kind | Target | Reason | By |\n|---|---|---|---|---|---|\n")
	for _, id := range catalog.ReportPage((pg-1)*pageSize, pageSize) {
		r, ok := catalog.GetReport(id)
		if !ok {
			continue
		}
		reason := sanitize.TableCell(r.Reason)
		if safe.Blocked(r.Reason) { // it may quote what it reports
			reason = "*(hidden: quotes a blocked word)*"
		}
		b.WriteString("| " + itoa(r.ID) + " | " + date(r.At) + " | " + r.Kind + " | [" + r.Kind + " " + r.Target + "](" + page(r.Kind+"/"+r.Target) +
			") | " + reason + " | " + who(r.By) + " |\n")
	}
	b.WriteString("\n" + itoa(catalog.ReportCount()) + " open reports. " + pager("moderation", pg, catalog.ReportCount()))
	return b.String()
}

// ---- helpers ----

func header(title string) string { return "# " + title + "\n\n" + nav() }

func nav() string {
	return "[Radio](" + page("") + ") · [Stations](" + page("stations") + ") · [Catalog](" + page("catalog") +
		") · [Concerts](" + page("concerts") + ") · [Charts](" + page("charts") + ") · [About](" + page("about") + ")\n\n"
}

func stats() string {
	return "**" + itoa(catalog.ArtistCount()) + "** artists · **" + itoa(catalog.TrackCount()) + "** tracks · **" + itoa(catalog.AlbumCount()) +
		"** albums · **" + itoa(tickets.TicketCount()) + "** tickets · v" + catalog.Version() + "\n"
}

func page(p string) string {
	base := strings.TrimPrefix(unsafe.CurrentRealm().PkgPath(), runtime.ChainDomain())
	if p == "" {
		return base
	}
	return base + ":" + p
}

func pager(route string, pg, total int) string { return pagerMore(route, pg, pg*pageSize < total) }

// pagerMore links the previous page and, when more is true, the next one.
func pagerMore(route string, pg int, more bool) string {
	sep := "?p="
	if strings.Contains(route, "?") {
		sep = "&p="
	}
	s := ""
	if pg > 1 {
		s += "[← Previous](" + page(route+sep+itoa(pg-1)) + ") "
	}
	if more {
		s += "[Next →](" + page(route+sep+itoa(pg+1)) + ")"
	}
	return s + "\n"
}

func playable(t catalog.Track) bool { return !t.Hidden && catalog.ArtistVisible(t.Artist) }

func trackLink(t catalog.Track) string {
	return "[" + md(t.Title) + "](" + page("track/"+itoa(t.ID)) + ") · " + artistRef(t.Artist)
}

// artistRef links an artist by id, or prints nothing for a hidden one.
func artistRef(id int) string {
	if !catalog.ArtistVisible(id) {
		return ""
	}
	return "[" + md(catalog.ArtistName(id)) + "](" + page("artist/"+itoa(id)) + ")"
}

// trackRef links a track by id ("a track" when hidden or unknown).
func trackRef(id int) string {
	if t, ok := catalog.GetTrack(id); ok && playable(t) {
		return "[" + md(t.Title) + "](" + page("track/"+itoa(t.ID)) + ")"
	}
	return "a track"
}

// tippable mirrors catalog: tips and paid tickets need a claimed, verified
// artist. A variable so tests can stand in for the catalog admin.
var tippable = func(a catalog.Artist) bool { return a.Owner != "" && a.Verified }

// verifyLink sends an artist to the app's verification steps (catalog/verify.gno).
func verifyLink(artistID int) string {
	if l := inApp("artist/"+itoa(artistID), "Verify it in the app"); l != "" {
		return l
	}
	return "verify it in the GnoRadio app"
}

// genreBrowse points an empty or idle station to tracks it could play.
func genreBrowse(st int) string {
	if st == 0 {
		return "[Browse the catalog](" + page("catalog") + "), open a track and choose **Queue on Main**."
	}
	return "[Browse " + catalog.GenreName(st) + " tracks](" + page("catalog?g="+itoa(st)) + "), open one and choose **Queue**."
}

// sourceURL links a contract file on gnoweb.
func sourceURL(pkgPath, file string) string {
	return strings.TrimPrefix(pkgPath, runtime.ChainDomain()) + "$source&file=" + file
}

func appLine() string {
	if l := inApp("", "Open it"); l != "" {
		return " " + l + "."
	}
	return ""
}

func artistLink(a catalog.Artist) string {
	s := "[" + md(a.Name) + "](" + page("artist/"+itoa(a.ID)) + ")"
	if a.Verified {
		s += " ✓"
	}
	return s
}

func who(addr address) string {
	if id := catalog.ArtistOf(addr); id != 0 {
		if a, ok := catalog.GetArtist(id); ok && !a.Hidden {
			return artistLink(a)
		}
	}
	return "[" + short(addr) + "](" + page("listener/"+addr.String()) + ")"
}

func listenURL(t catalog.Track, offset int64) string {
	frag := ""
	if offset > 0 {
		frag = "#t=" + itoa64(offset)
	}
	switch {
	case strings.HasPrefix(t.Audio, "ipfs://"):
		return "https://ipfs.io/ipfs/" + strings.TrimPrefix(t.Audio, "ipfs://") + frag
	case strings.HasPrefix(t.Audio, "ar://"):
		return "https://arweave.net/" + strings.TrimPrefix(t.Audio, "ar://") + frag
	case strings.HasPrefix(t.Audio, "audius:"):
		return t.SourceURL
	}
	return t.Audio + frag
}

// licenseLink links a license id to its deed. Creative Commons ids read
// CC-<terms>-<version>[-<port>], e.g. CC-BY-SA-3.0-DE →
// creativecommons.org/licenses/by-sa/3.0/de/.
func licenseLink(l string) string {
	switch {
	case l == "CC0-1.0":
		return "[CC0 1.0](https://creativecommons.org/publicdomain/zero/1.0/)"
	case l == catalog.AudiusLicense:
		return "[Audius Open Music License](https://audius.org/open-music-license.pdf)"
	case strings.HasPrefix(l, "CC-"):
		var terms []string
		ver, port := "", ""
		for _, part := range strings.Split(strings.TrimPrefix(l, "CC-"), "-") {
			switch {
			case ver == "" && strings.Contains(part, "."):
				ver = part
			case ver == "":
				terms = append(terms, part)
			case port == "":
				port = part
			default:
				return md(l)
			}
		}
		if ver == "" || len(terms) == 0 {
			return md(l)
		}
		url := "https://creativecommons.org/licenses/" + strings.ToLower(strings.Join(terms, "-")) + "/" + ver + "/"
		label := "CC " + strings.Join(terms, "-") + " " + ver
		if port != "" {
			url += strings.ToLower(port) + "/"
			label += " " + port
		}
		return "[" + label + "](" + url + ")"
	}
	return "All rights reserved"
}

func queueURL(st, id int) string {
	return radioTx.NewLink("Queue").AddArgs("stationID", itoa(st), "trackID", itoa(id)).URL()
}

func supportURL(gnots int64) string {
	return catalogTx.NewLink("SupportGnoRadio").SetSend(strconv.FormatInt(gnots*ugnot, 10) + "ugnot").URL()
}

// tipSupportURL tips gnots to the artist side plus pct% on top for GnoRadio.
func tipSupportURL(id int, gnots, pct int64) string {
	total := gnots * ugnot * (100 + pct) / 100
	return catalogTx.NewLink("TipWithSupport").AddArgs("trackID", itoa(id), "supportPct", itoa64(pct)).SetSend(strconv.FormatInt(total, 10) + "ugnot").URL()
}

func tipURL(id int, gnots int64) string {
	return catalogTx.NewLink("Tip").AddArgs("trackID", itoa(id)).SetSend(strconv.FormatInt(gnots*ugnot, 10) + "ugnot").URL()
}

func genreList() string {
	var parts []string
	for g := 1; g <= catalog.NumGenres; g++ {
		parts = append(parts, itoa(g)+" "+catalog.GenreName(g))
	}
	return strings.Join(parts, " · ")
}

func md(s string) string    { return sanitize.InlineText(s) }
func itoa(n int) string     { return strconv.Itoa(n) }
func itoa64(n int64) string { return strconv.FormatInt(n, 10) }

func atoi(s string) int {
	n, err := strconv.Atoi(s)
	if err != nil || n < 0 {
		return 0
	}
	return n
}

func short(a address) string {
	s := a.String()
	if len(s) < 12 {
		return s
	}
	return s[:7] + "…" + s[len(s)-4:]
}

func clock(sec int64) string {
	s := strconv.FormatInt(sec%60, 10)
	if len(s) == 1 {
		s = "0" + s
	}
	return strconv.FormatInt(sec/60, 10) + ":" + s
}

// span is a duration as m:ss under an hour, else as "12 h 05".
func span(sec int64) string {
	if sec < 3600 {
		return clock(sec)
	}
	m := strconv.FormatInt(sec/60%60, 10)
	if len(m) == 1 {
		m = "0" + m
	}
	return strconv.FormatInt(sec/3600, 10) + " h " + m
}

func date(unix int64) string { return time.Unix(unix, 0).UTC().Format("Jan 2, 2006 15:04") + " UTC" }
func hour(unix int64) string { return time.Unix(unix, 0).UTC().Format("15:04") }
