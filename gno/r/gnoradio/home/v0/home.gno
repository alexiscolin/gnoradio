// Package home is the GnoRadio website on gnoweb. It owns no data: every
// page is rendered from the catalog, radio and tickets realms.
package home

import (
	"chain/runtime"
	"chain/runtime/unsafe"
	"strconv"
	"strings"
	"time"

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
//	"catalog?p=N" "artists?p=N" "albums?p=N" "playlists?p=N"
//	"concerts" "event/<id>" "ticket/<id>"
//	"listener/<g1…>"         a listener: likes, playlists, tickets, badges
//	"charts" "join" "about" "moderation"
//
// Raw path input is never echoed: ids are parsed, names and addresses looked up.
func Render(path string) string {
	p, query, _ := strings.Cut(path, "?")
	pg := 1
	if v, ok := strings.CutPrefix(query, "p="); ok {
		if n := atoi(v); n > 1 && n < 100000 {
			pg = n
		}
	}
	out := route(p, pg)
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

func route(p string, pg int) string {
	switch p {
	case "":
		return renderHome()
	case "stations":
		return renderStations()
	case "catalog":
		return renderCatalog(pg)
	case "artists":
		return renderArtists(pg)
	case "albums":
		return renderAlbums(pg)
	case "playlists":
		return renderPlaylists(pg)
	case "concerts":
		return renderConcerts()
	case "charts":
		return renderCharts()
	case "join":
		return renderJoin()
	case "about":
		return renderAbout()
	case "moderation":
		return renderModeration(1)
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
			return renderArtist(a)
		}
	case "album":
		if al, ok := catalog.GetAlbum(atoi(arg)); ok && !al.Hidden && catalog.ArtistVisible(al.Artist) {
			return renderAlbum(al)
		}
	case "playlist":
		if pl, ok := catalog.GetPlaylist(atoi(arg)); ok && !pl.Hidden {
			return renderPlaylist(pl)
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
			return renderListener(addr)
		}
	}
	return ""
}

// ---- pages ----

func renderHome() string {
	var b strings.Builder
	b.WriteString("# GnoRadio\n\n" + nav())
	b.WriteString("**Community radio and open music player, 100% on-chain.** Every tip lands in the artist's wallet, in the same transaction. " +
		"[Read the code that guarantees it](" + catalogTx.Call("") + ").\n\n")
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
	b.WriteString("\n\n[Full catalog →](" + page("catalog") + ")\n\n---\n\n" + stats())
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
	}
	return onAirSVG(radio.StationName(st), t.Title, catalog.ArtistName(t.Artist), off, t.Duration) + "\n\n" +
		"**[▶ Listen from " + clock(off) + "](" + listenURL(t, off) + ")** · " + trackLink(t) + " · " + src +
		" · [Go live in the app](" + page("about") + ")\n\n"
}

func renderStations() string {
	var b strings.Builder
	b.WriteString(header("Stations"))
	b.WriteString("Every station plays the same second for everyone. Pick one, or queue a track on it from any track page.\n\n")
	b.WriteString("| Station | Tracks | Loop | Queued | On air |\n|---|---|---|---|---|\n")
	for s := 0; s < radio.StationCount(); s++ {
		tracks, loop, queued := radio.StationInfo(s)
		now := "—"
		if id, _, _ := radio.NowPlaying(s); id != 0 {
			now = md(catalog.TrackTitle(id))
		}
		b.WriteString("| [" + radio.StationName(s) + "](" + page("station/"+itoa(s)) + ") | " + itoa(tracks) + " | " + clock(loop) + " | " + itoa(queued) + " | " + now + " |\n")
	}
	if p := radio.Pending(); p > 0 {
		b.WriteString("\n" + itoa(p) + " new tracks are waiting to join the stations: [sync them](" + radioTx.NewLink("Sync").AddArgs("max", "200").URL() + ") (anyone can).\n")
	}
	return b.String()
}

func renderStation(st int) string {
	var b strings.Builder
	b.WriteString(header(radio.StationName(st)))
	b.WriteString(onAir(st))
	b.WriteString("## Up next\n\n")
	next := radio.UpNext(st)
	if len(next) == 0 {
		b.WriteString("Nothing queued: the rotation plays. Open a track and choose **Queue on this station**.\n")
	}
	for i, s := range next {
		if i == 10 {
			break
		}
		if t, ok := catalog.GetTrack(s.Track); ok {
			b.WriteString("- " + hour(s.Start) + " UTC · " + trackLink(t) + " · queued by " + who(s.By) + "\n")
		}
	}
	tracks, loop, _ := radio.StationInfo(st)
	b.WriteString("\n" + itoa(tracks) + " tracks in rotation · one loop lasts " + clock(loop) + ".\n")
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
	b.WriteString("♥ " + itoa(t.Likes) + " · ◈ " + gnot(t.Tips) + " from " + itoa(t.Supporters) + " supporters\n\n")
	b.WriteString("**[▶ Listen](" + listenURL(t, 0) + ")**")
	if t.Album != 0 {
		if al, ok := catalog.GetAlbum(t.Album); ok {
			b.WriteString(" · from [" + md(al.Title) + "](" + page("album/"+itoa(al.ID)) + ")")
		}
	}
	b.WriteString("\n\n[♥ Like](" + catalogTx.NewLink("Like").AddArgs("trackID", itoa(t.ID)).URL() + ") · " +
		"Queue on [Main](" + queueURL(0, t.ID) + ") or [" + radio.StationName(t.Genre) + "](" + queueURL(t.Genre, t.ID) + ")\n\n")
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
	b.WriteString("\n---\n\n`" + t.Audio + "` · published " + date(t.Created) + " · [Report](" +
		catalogTx.NewLink("Report").AddArgs("kind", "track", "target", itoa(t.ID), "reason", "").URL() + ")\n")
	return b.String()
}

// support explains how this track can be supported, by origin and claim.
func support(t catalog.Track, a catalog.Artist) string {
	if a.Owner != "" {
		to := "100% of the artist share goes to the artist"
		if n := len(t.Splits); n == 1 {
			to = "The artist share is split with 1 collaborator"
		} else if n > 1 {
			to = "The artist share is split with " + itoa(n) + " collaborators"
		}
		return "**◈ Tip:** [1 GNOT](" + tipURL(t.ID, 1) + ") · [5 GNOT](" + tipURL(t.ID, 5) + ") · [20 GNOT](" + tipURL(t.ID, 20) + ")  \n" + to + ", same transaction.\n"
	}
	if t.Origin == catalog.OriginAudius && a.Source != "" {
		return "**[Support on Audius](" + a.Source + ")** · Is this you? [Claim this profile](" + page("join") + ")\n"
	}
	return "Tips open once the artist claims this profile. Is this you? [Claim it](" + page("join") + ")\n"
}

func renderArtist(a catalog.Artist) string {
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
		b.WriteString("◈ **" + gnot(a.Tips) + "** received · " + itoa(a.Followers) + " followers  \nWallet: [" + short(a.Owner) + "](" + page("listener/"+a.Owner.String()) + ")\n\n")
	case a.Kind == catalog.OriginAudius:
		b.WriteString("Streamed from [Audius](" + a.Source + ") · " + itoa(a.Followers) + " followers  \nUnclaimed profile: [is this you?](" + page("join") + ")\n\n")
	default:
		src := ""
		if a.Source != "" {
			src = " · [source](" + a.Source + ")"
		}
		b.WriteString("Curated CC artist" + src + " · " + itoa(a.Followers) + " followers  \nUnclaimed profile: [is this you?](" + page("join") + ")\n\n")
	}
	b.WriteString("[Follow](" + catalogTx.NewLink("Follow").AddArgs("artistID", itoa(a.ID)).URL() + ")\n</gno-columns>\n\n")

	b.WriteString("## Tracks\n\n")
	shown := 0
	var older strings.Builder
	for i := len(a.Tracks) - 1; i >= 0; i-- {
		t, ok := catalog.GetTrack(a.Tracks[i])
		if !ok || !playable(t) {
			continue
		}
		if shown < maxCovers {
			b.WriteString("[" + coverSVG(t.ID, t.Title, 150) + "](" + page("track/"+itoa(t.ID)) + ")")
		} else {
			older.WriteString("- " + trackLink(t) + "\n")
		}
		shown++
		if shown >= maxCovers+40 {
			break
		}
	}
	if shown == 0 {
		b.WriteString("No track yet.")
	}
	b.WriteString("\n\n" + older.String() + "\n")
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
	b.WriteString("### " + artistLink(a) + "\n\n" + itoa(al.Year) + " · " + itoa(len(al.Tracks)) + " tracks · " + clock(total) + " · ◈ " + gnot(tips) + "\n</gno-columns>\n\n")
	b.WriteString("| # | Track | Time | ♥ |\n|---|---|---|---|\n")
	for i, id := range al.Tracks {
		if t, ok := catalog.GetTrack(id); ok && playable(t) {
			b.WriteString("| " + itoa(i+1) + " | [" + md(t.Title) + "](" + page("track/"+itoa(t.ID)) + ") | " + clock(t.Duration) + " | " + itoa(t.Likes) + " |\n")
		}
	}
	return b.String()
}

func renderPlaylist(pl catalog.Playlist) string {
	var b strings.Builder
	b.WriteString(header(md(pl.Title)))
	b.WriteString("Playlist by " + who(pl.Owner) + " · " + itoa(len(pl.Tracks)) + " tracks · updated " + date(pl.Updated) + "\n\n")
	b.WriteString("| # | Track | Artist | Time |\n|---|---|---|---|\n")
	for i, id := range pl.Tracks {
		if t, ok := catalog.GetTrack(id); ok && playable(t) {
			b.WriteString("| " + itoa(i+1) + " | [" + md(t.Title) + "](" + page("track/"+itoa(t.ID)) + ") | " + md(catalog.ArtistName(t.Artist)) + " | " + clock(t.Duration) + " |\n")
		}
	}
	b.WriteString("\n[Report this playlist](" + catalogTx.NewLink("Report").AddArgs("kind", "playlist", "target", itoa(pl.ID), "reason", "").URL() + ")\n")
	return b.String()
}

func renderCatalog(pg int) string {
	var b strings.Builder
	b.WriteString(header("Catalog"))
	b.WriteString("| # | Track | Artist | Genre | Time | License | ♥ |\n|---|---|---|---|---|---|---|\n")
	for _, id := range catalog.TrackPage((pg-1)*pageSize, pageSize, true) {
		if t, ok := catalog.GetTrack(id); ok && playable(t) {
			b.WriteString("| " + itoa(t.ID) + " | [" + md(t.Title) + "](" + page("track/"+itoa(t.ID)) + ") | " + md(catalog.ArtistName(t.Artist)) +
				" | " + catalog.GenreName(t.Genre) + " | " + clock(t.Duration) + " | " + t.License + " | " + itoa(t.Likes) + " |\n")
		}
	}
	b.WriteString("\n" + pager("catalog", pg, catalog.TrackCount()))
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
			b.WriteString("| " + artistLink(a) + " | " + kind + " | " + itoa(len(a.Tracks)) + " | " + itoa(a.Followers) + " | " + gnot(a.Tips) + " |\n")
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
			b.WriteString("- [" + md(al.Title) + "](" + page("album/"+itoa(al.ID)) + ") · " + md(catalog.ArtistName(al.Artist)) + " · " + itoa(al.Year) + "\n")
		}
	}
	b.WriteString("\n" + pager("albums", pg, catalog.AlbumCount()))
	return b.String()
}

func renderPlaylists(pg int) string {
	var b strings.Builder
	b.WriteString(header("Playlists"))
	for _, id := range catalog.PlaylistPage((pg-1)*pageSize, pageSize) {
		if pl, ok := catalog.GetPlaylist(id); ok && !pl.Hidden {
			b.WriteString("- [" + md(pl.Title) + "](" + page("playlist/"+itoa(pl.ID)) + ") · " + itoa(len(pl.Tracks)) + " tracks · by " + who(pl.Owner) + "\n")
		}
	}
	b.WriteString("\n" + pager("playlists", pg, catalog.PlaylistCount()))
	return b.String()
}

func renderConcerts() string {
	var b strings.Builder
	b.WriteString(header("Concerts"))
	up := tickets.Upcoming(20)
	if len(up) == 0 {
		b.WriteString("No concert announced. [Announce yours](" + page("join") + ").\n")
	}
	for _, e := range up {
		b.WriteString("- **" + date(e.Start) + "** · [" + md(e.Title) + "](" + page("event/"+itoa(e.ID)) + ") · " +
			md(catalog.ArtistName(e.ArtistID)) + " · " + md(e.Venue) + "\n")
	}
	return b.String()
}

func renderEvent(e tickets.Event) string {
	var b strings.Builder
	b.WriteString(header(md(e.Title)))
	b.WriteString(tickets.EventSVG(e.ID) + "\n\n")
	a, _ := catalog.GetArtist(e.ArtistID)
	b.WriteString("**" + artistLink(a) + "** · " + md(e.Venue) + " · **" + date(e.Start) + "** · seats **" + itoa(e.Sold) + " / " + itoa(e.Capacity) + "**\n\n")
	if e.Link != "" {
		b.WriteString("Link: [" + e.Link + "](" + e.Link + ") (public)\n\n")
	}
	switch {
	case e.Cancelled:
		b.WriteString("> [!CAUTION] Cancelled\n> Payments went straight to the artist: contact them for a refund.\n")
	case time.Now().Unix() >= e.Start:
		b.WriteString("> [!NOTE] Past concert\n> Tickets stay in their holders' collections.\n")
	case e.Sold >= e.Capacity:
		b.WriteString("> [!WARNING] Sold out\n")
	default:
		link := ticketsTx.NewLink("BuyTicket").AddArgs("eventID", itoa(e.ID))
		label, limit := "Get a free ticket", "one free ticket per wallet"
		if e.Price > 0 {
			link = link.SetSend(strconv.FormatInt(e.Price, 10) + "ugnot")
			label, limit = "Buy for "+gnot(e.Price), "up to 4 per wallet"
		}
		b.WriteString("**[" + label + "](" + link.URL() + ")** · " + limit + "\n\n")
		b.WriteString("Your ticket is an NFT drawn on-chain, in your name. 100% of the price goes to the artist. " +
			"You can gift it; there is no resale market. At the door the artist checks it in and it becomes an \"I was there\" keepsake.\n")
	}
	return b.String()
}

func renderTicket(tk tickets.Ticket) string {
	var b strings.Builder
	e, _ := tickets.EventInfo(tk.Event)
	b.WriteString(header("Ticket #" + itoa(tk.Serial) + " · " + md(e.Title)))
	b.WriteString(tickets.TicketSVG(tk.ID) + "\n\n")
	b.WriteString("Holder: " + who(tickets.TicketOwner(tk.ID)) + " · [concert](" + page("event/"+itoa(e.ID)) + ")\n\n")
	if !tk.Attended {
		b.WriteString("Holder: [gift this ticket](" + ticketsTx.NewLink("TransferTicket").AddArgs("to", "", "ticketID", itoa(tk.ID)).URL() + ") · " +
			"Artist: [check in at the door](" + ticketsTx.NewLink("CheckIn").AddArgs("ticketID", itoa(tk.ID)).URL() + ")\n")
	}
	return b.String()
}

func renderListener(addr address) string {
	var b strings.Builder
	b.WriteString(header("Listener " + short(addr)))
	if id := catalog.ArtistOf(addr); id != 0 {
		if a, ok := catalog.GetArtist(id); ok && !a.Hidden {
			b.WriteString("Also the artist " + artistLink(a) + ".\n\n")
		}
	}
	likes, follows, tipped, lists := catalog.UserStats(addr)
	b.WriteString("♥ " + itoa(likes) + " likes · " + itoa(follows) + " follows · ◈ " + gnot(tipped) + " given · " + itoa(tickets.Attended(addr)) + " concerts attended\n\n")
	if len(lists) > 0 {
		b.WriteString("## Playlists\n\n")
		for _, id := range lists {
			if pl, ok := catalog.GetPlaylist(id); ok && !pl.Hidden {
				b.WriteString("- [" + md(pl.Title) + "](" + page("playlist/"+itoa(pl.ID)) + ") · " + itoa(len(pl.Tracks)) + " tracks\n")
			}
		}
		b.WriteString("\n")
	}
	b.WriteString("## Tickets\n\n")
	ids := tickets.TicketsOf(addr, 0, 20)
	if len(ids) == 0 {
		b.WriteString("No ticket. [See concerts](" + page("concerts") + ").\n")
	}
	for _, id := range ids {
		if tk, ok := tickets.TicketInfo(id); ok {
			e, _ := tickets.EventInfo(tk.Event)
			state := ""
			if tk.Attended {
				state = " · ✓ I was there"
			}
			b.WriteString("- [" + md(e.Title) + " #" + itoa(tk.Serial) + "](" + page("ticket/"+itoa(tk.ID)) + ") · " + date(e.Start) + state + "\n")
		}
	}
	b.WriteString("\n## Recent likes\n\n")
	shown := 0
	for _, id := range catalog.LikedPage(addr, 0, 20) {
		if t, ok := catalog.GetTrack(id); ok && playable(t) {
			for i, e := range t.Early {
				if e == addr && shown < maxCovers {
					b.WriteString("[" + badgeSVG(t.Title, i+1) + "](" + page("track/"+itoa(t.ID)) + ")")
					shown++
				}
			}
		}
	}
	if shown == 0 {
		b.WriteString("No early-listener badge yet: be among the first 10 to like a new track.")
	}
	b.WriteString("\n")
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
		b.WriteString(barsSVG(rows, gnot) + "\n\n")
	}
	b.WriteString("## Most liked tracks\n\n| # | Track | ♥ | Supporters |\n|---|---|---|---|\n")
	n := 0
	for _, r := range catalog.TopLiked() {
		if t, ok := catalog.GetTrack(atoi(r.Key)); ok && playable(t) {
			n++
			b.WriteString("| " + itoa(n) + " | " + trackLink(t) + " | " + itoa(t.Likes) + " | " + itoa(t.Supporters) + " |\n")
		}
	}
	b.WriteString("\n## Top supporters\n\n")
	for i, r := range catalog.TopFans() {
		b.WriteString(itoa(i+1) + ". " + who(address(r.Key)) + " · " + gnot(r.Value) + "\n")
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
		"(Bandcamp, website, Audius bio) and [report the profile](" + page("moderation") + ") with the reason \"claim\" and the link. Once verified, tips and concerts open.\n\n" +
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
		"- **The GnoRadio app:** the synced player, uploads, your library. Listening never needs a transaction.\n" +
		"- **Audio:** IPFS, Arweave, allowed hosts (archive.org) and Audius. Metadata, links and fingerprints live on gno.land.\n\n" +
		"## Rules\n\n- Publish only music you own the rights to. Curated tracks are CC0, CC BY or CC BY-SA with attribution; Audius tracks follow the Audius Open Music License.\n" +
		"- Published files stay public: moderation can hide, not erase. Reports are public on [the moderation page](" + page("moderation") + ").\n\n" +
		"Contracts: [catalog](" + catalogTx.Call("") + ") · [radio](" + radioTx.Call("") + ") · [tickets](" + ticketsTx.Call("") + ")\n"
}

func renderModeration(pg int) string {
	var b strings.Builder
	b.WriteString(header("Moderation"))
	b.WriteString("Moderator: " + who(catalog.Admin()) + ". Reports are public; decisions are visible transactions.\n\n")
	b.WriteString("| # | Date | Kind | Target | Reason | By |\n|---|---|---|---|---|---|\n")
	for _, id := range catalog.ReportPage((pg-1)*30, 30) {
		r, ok := catalog.GetReport(id)
		if !ok {
			continue
		}
		b.WriteString("| " + itoa(r.ID) + " | " + date(r.At) + " | " + r.Kind + " | [" + r.Kind + " " + r.Target + "](" + page(r.Kind+"/"+r.Target) +
			") | " + sanitize.TableCell(r.Reason) + " | " + who(r.By) + " |\n")
	}
	return b.String()
}

// ---- helpers ----

func header(title string) string { return "# " + title + "\n\n" + nav() }

func nav() string {
	return "[Radio](" + page("") + ") · [Stations](" + page("stations") + ") · [Catalog](" + page("catalog") + ") · [Artists](" + page("artists") +
		") · [Albums](" + page("albums") + ") · [Playlists](" + page("playlists") + ") · [Concerts](" + page("concerts") + ") · [Charts](" + page("charts") +
		") · [Join](" + page("join") + ") · [About](" + page("about") + ")\n\n"
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

func pager(route string, pg, total int) string {
	s := ""
	if pg > 1 {
		s += "[← Previous](" + page(route+"?p="+itoa(pg-1)) + ") "
	}
	if pg*pageSize < total {
		s += "[Next →](" + page(route+"?p="+itoa(pg+1)) + ")"
	}
	return s + "\n"
}

func playable(t catalog.Track) bool { return !t.Hidden && catalog.ArtistVisible(t.Artist) }

func trackLink(t catalog.Track) string {
	return "[" + md(t.Title) + "](" + page("track/"+itoa(t.ID)) + ") · " + md(catalog.ArtistName(t.Artist))
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

func licenseLink(l string) string {
	switch {
	case l == "CC0-1.0":
		return "[CC0 1.0](https://creativecommons.org/publicdomain/zero/1.0/)"
	case strings.HasPrefix(l, "CC-"):
		slug := strings.ToLower(strings.TrimSuffix(strings.TrimPrefix(l, "CC-"), "-4.0"))
		return "[" + strings.ReplaceAll(strings.TrimSuffix(l, "-4.0"), "-", " ") + " 4.0](https://creativecommons.org/licenses/" + slug + "/4.0/)"
	case l == "Audius-OML":
		return "[Audius Open Music License](https://audius.org/open-music-license.pdf)"
	}
	return "All rights reserved"
}

func queueURL(st, id int) string {
	return radioTx.NewLink("Queue").AddArgs("stationID", itoa(st), "trackID", itoa(id)).URL()
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

func date(unix int64) string { return time.Unix(unix, 0).UTC().Format("Jan 2, 2006 15:04") + " UTC" }
func hour(unix int64) string { return time.Unix(unix, 0).UTC().Format("15:04") }

func gnot(u int64) string {
	whole := strconv.FormatInt(u/ugnot, 10)
	frac := u % ugnot
	if frac == 0 {
		return whole + " GNOT"
	}
	f := strconv.FormatInt(frac, 10)
	f = strings.TrimRight(strings.Repeat("0", 6-len(f))+f, "0")
	return whole + "." + f + " GNOT"
}
