package gnoradio

import (
	"chain/runtime"
	"chain/runtime/unsafe"
	"strconv"
	"strings"
	"time"

	"gno.land/p/moul/txlink/v0"
	"gno.land/p/nt/markdown/sanitize/v0"
)

// maxCovers bounds the SVG images drawn on one page (vm/qrender gas budget).
const (
	maxCovers = 8
	pageSize  = 20
)

// Render serves the gnoweb front:
//
//	""                        home: on air, up next, top, concerts, new releases
//	"track/<id>"              a track: cover, like, tip, program on the radio
//	"artist/<g1...|name>"     an artist profile
//	"artists?p=N"             artist directory
//	"catalog?p=N"             all tracks
//	"concerts"                upcoming and past concerts
//	"event/<id>"              a concert and its ticket sale
//	"ticket/<id>"             one NFT ticket
//	"listener/<g1...>"        a listener profile: badges and tickets
//	"charts"                  leaderboards
//	"join"                    forms to become an artist, publish, announce a concert
//	"about"                   how it works
//	"moderation"              reports queue
//
// Raw path input is never echoed: ids are parsed, addresses and names looked up.
func Render(path string) string {
	p, query, _ := strings.Cut(path, "?")
	pg := 1
	if v, ok := strings.CutPrefix(query, "p="); ok {
		if n := atoi(v); n > 1 && n < 100000 {
			pg = n
		}
	}
	var out string
	switch {
	case p == "":
		out = renderHome()
	case p == "charts":
		out = renderCharts()
	case p == "join":
		out = renderJoin()
	case p == "about":
		out = renderAbout()
	case p == "catalog":
		out = renderCatalog(pg)
	case p == "artists":
		out = renderArtists(pg)
	case p == "concerts":
		out = renderConcerts()
	case p == "moderation":
		out = renderModeration()
	}
	if s, ok := strings.CutPrefix(p, "track/"); ok {
		if t := getTrack(atoi(s)); t != nil {
			if !playable(t) {
				return header("Morceau retiré") + "> [!WARNING] Retiré par la modération\n> Ce morceau n'est plus disponible.\n"
			}
			out = renderTrack(t)
		}
	}
	if s, ok := strings.CutPrefix(p, "artist/"); ok {
		a := getArtist(address(s))
		if a == nil {
			a = artistByName(s)
		}
		if a != nil && !a.Hidden {
			out = renderArtist(a)
		}
	}
	if s, ok := strings.CutPrefix(p, "listener/"); ok {
		if addr := address(s); addr.IsValid() {
			out = renderListener(addr)
		}
	}
	if s, ok := strings.CutPrefix(p, "event/"); ok {
		if e := getEvent(atoi(s)); visibleEvent(e) {
			out = renderEvent(e)
		}
	}
	if s, ok := strings.CutPrefix(p, "ticket/"); ok {
		if tk := getTicket(atoi(s)); tk != nil {
			out = renderTicket(tk)
		}
	}
	if out == "" {
		return header("Introuvable") + "Cette page n'existe pas. [← Retour à la radio](" + page("") + ")\n"
	}
	if successor != "" {
		out = "> [!WARNING] GnoRadio a déménagé\n> La nouvelle version est sur [" + successor + "](" +
			strings.TrimPrefix(successor, runtime.ChainDomain()) + ").\n\n" + out
	} else if frozen {
		out = "> [!CAUTION] GnoRadio est en pause\n> Une mise à jour est en cours ; les billets restent utilisables.\n\n" + out
	}
	return out
}

func header(title string) string {
	return "# " + title + "\n\n" + nav()
}

func renderHome() string {
	var b strings.Builder
	ts := now()
	id, offset, queued := onAir(ts)
	t := getTrack(id)

	b.WriteString("# GnoRadio\n\n" + nav())
	b.WriteString("**La radio communautaire 100 % on-chain.** Chaque tip arrive directement chez l'artiste, dans la même transaction. " +
		"[Lis le code qui le garantit](" + page("") + "$source&file=gnoradio.gno).\n\n")
	b.WriteString(bannerSVG(t, offset, queued) + "\n\n")
	if t != nil {
		b.WriteString("Position au dernier bloc : **" + clock(offset) + " / " + clock(t.Duration) + "** · recharge la page pour suivre.\n\n")
		b.WriteString("**[▶ Écouter à partir de " + clock(offset) + "](" + audioURL(t) + "#t=" + itoa64(offset) + ")** · " +
			"[J'aime](" + likeURL(t) + ") · [◈ Soutenir 1 GNOT](" + tipURL(t, 1) + ") · " +
			"[Fiche du morceau](" + trackPage(t) + ")\n\n")
		b.WriteString("> [!INFO] Écoute synchronisée\n> Ici tu ouvres le fichier audio. La radio en direct, où tout le monde entend la même chose à la seconde près, arrive dans l'app GnoRadio.\n\n")
	}

	b.WriteString("<gno-columns>\n## ⏭ À suivre\n\n")
	next := UpNext()
	if len(next) == 0 {
		b.WriteString("Rien de programmé : la rotation tourne. Ouvre un morceau et clique **📡 Programmer**.\n")
	}
	for i, s := range next {
		if i == 6 {
			break
		}
		b.WriteString("- " + hour(s.Start) + " " + trackLink(getTrack(s.Track)) + "\n")
	}
	b.WriteString("<gno-columns-sep />\n## 🔥 Les plus aimés\n\n")
	n := 0
	for _, r := range topLiked {
		if t := getTrack(atoi(r.key)); playable(t) && n < 5 {
			n++
			b.WriteString(itoa(n) + ". " + trackLink(t) + " · ♥ " + itoa(t.Likes) + "\n")
		}
	}
	if n == 0 {
		b.WriteString("Pas encore de likes.\n")
	}
	b.WriteString("<gno-columns-sep />\n## 🎤 Concerts\n\n")
	up := upcomingEvents(ts, 4)
	if len(up) == 0 {
		b.WriteString("Aucun concert annoncé. [Annonce le tien](" + page("join") + ").\n")
	}
	for _, e := range up {
		b.WriteString("- [" + md(e.Title) + "](" + page("event/"+itoa(e.ID)) + ") · " + date(e.Start) + "\n")
	}
	b.WriteString("</gno-columns>\n\n")

	b.WriteString("## ✨ Nouveautés\n\n")
	shown := 0
	tracks.ReverseIterate("", "", func(_ string, v any) bool {
		t := v.(*Track)
		if playable(t) {
			b.WriteString("[" + coverSVG(t, 160, true) + "](" + trackPage(t) + ")")
			shown++
		}
		return shown >= maxCovers
	})
	if shown == 0 {
		b.WriteString("> [!INFO] Le catalogue est vide\n> [Publie le premier morceau](" + page("join") + ").\n")
	}
	b.WriteString("\n\n[Tout le catalogue →](" + page("catalog") + ")\n\n---\n\n")
	b.WriteString(stats())
	return b.String()
}

func renderTrack(t *Track) string {
	var b strings.Builder
	a := getArtist(t.Artist)
	b.WriteString(header(md(t.Title)))
	b.WriteString("<gno-columns>\n")
	b.WriteString(coverSVG(t, 300, false) + "\n")
	b.WriteString("<gno-columns-sep />\n")
	b.WriteString("### par " + artistLink(a) + "\n\n")
	if t.Genre != "" {
		b.WriteString("Genre : " + md(t.Genre) + "  \n")
	}
	b.WriteString("Durée : " + clock(t.Duration) + "  \n")
	b.WriteString("Licence : **[" + t.License + "](" + licenseURL(t.License) + ")**")
	if t.CMO == cmoSacemNC {
		b.WriteString(" · déclarée à la SACEM")
	}
	b.WriteString("  \n")
	if t.Credits != "" {
		b.WriteString("Crédits : " + md(t.Credits) + "  \n")
	}
	b.WriteString("♥ " + itoa(t.Likes) + " · ◈ " + gnot(t.Tips) + " de " + itoa(t.Supporters) + " soutien(s)\n\n")
	b.WriteString("**[▶ Écouter](" + audioURL(t) + ")** · [autre passerelle](https://dweb.link/ipfs/" + t.CID + ")\n\n")
	b.WriteString("[J'aime](" + likeURL(t) + ") · [📡 Programmer à la radio](" +
		txlink.NewLink("Queue").AddArgs("trackID", itoa(t.ID)).URL() + ")\n\n")
	b.WriteString("**◈ Soutenir :** [1 GNOT](" + tipURL(t, 1) + ") · [5 GNOT](" + tipURL(t, 5) + ") · [20 GNOT](" + tipURL(t, 20) + ")\n")
	b.WriteString("</gno-columns>\n\n")

	b.WriteString("## ◈ Où va ton soutien\n\n")
	parts := []int64{}
	colors := []string{}
	p := paletteOf(trackSeed(t))
	b.WriteString("| Destinataire | Part |\n|---|---|\n")
	rest := int64(100)
	for i, s := range t.Splits {
		b.WriteString("| " + who(s.To) + " | " + itoa64(s.Pct) + " % |\n")
		rest -= s.Pct
		parts = append(parts, s.Pct)
		colors = append(colors, []string{p.b, p.c, "#8a8a99", "#55556a"}[i%4])
	}
	b.WriteString("| " + artistLink(a) + " (artiste) | " + itoa64(rest) + " % |\n\n")
	parts = append(parts, rest)
	colors = append(colors, p.a)
	b.WriteString(gaugeSVG(parts, colors, "répartition des tips") + "\n\n")
	b.WriteString("> [!TIP] Vérifiable\n> La fonction `Tip` envoie chaque part dans la même transaction, sans commission. " +
		"[Lis le code](" + page("") + "$source&file=gnoradio.gno).\n\n")

	b.WriteString("## 🏅 Premiers auditeurs\n\n")
	for i, addr := range t.early {
		b.WriteString(itoa(i+1) + ". " + who(addr) + "\n")
	}
	if len(t.early) < earlyBadges {
		b.WriteString("\nEncore **" + itoa(earlyBadges-len(t.early)) + "** badges à gagner : [aime ce morceau](" + likeURL(t) + ").\n")
	}
	b.WriteString("\n---\n\nIPFS `" + t.CID + "` · publié le " + date(t.Created) +
		" · [Signaler](" + txlink.NewLink("Report").AddArgs("kind", "track", "target", itoa(t.ID), "reason", "").URL() + ")\n")
	return b.String()
}

func renderArtist(a *Artist) string {
	var b strings.Builder
	title := md(a.Name)
	if a.Verified {
		title += " ✓"
	}
	b.WriteString(header(title))
	b.WriteString("<gno-columns>\n")
	b.WriteString(avatarSVG(a.Addr, 160) + "\n")
	b.WriteString("<gno-columns-sep />\n")
	if a.Bio != "" {
		b.WriteString(md(a.Bio) + "\n\n")
	}
	if a.Verified {
		b.WriteString("✓ **Artiste vérifié**  \n")
	}
	b.WriteString("◈ **" + gnot(a.Tips) + "** reçus en soutien  \n")
	b.WriteString(itoa(len(a.Tracks)) + " morceau(x) · membre depuis le " + date(a.Joined) + "  \n")
	b.WriteString("Wallet : [" + short(a.Addr) + "](" + page("listener/"+a.Addr.String()) + ")\n")
	b.WriteString("</gno-columns>\n\n")

	// Newest first; covers for the latest tracks keep the page within the
	// vm/qrender gas budget, older tracks are listed as links.
	b.WriteString("## Morceaux\n\n")
	shown := 0
	var older strings.Builder
	for i := len(a.Tracks) - 1; i >= 0; i-- {
		t := getTrack(a.Tracks[i])
		if !playable(t) {
			continue
		}
		if shown < maxCovers {
			b.WriteString("[" + coverSVG(t, 160, true) + "](" + trackPage(t) + ")")
		} else if shown < maxCovers+50 {
			older.WriteString("- " + trackLink(t) + "\n")
		}
		shown++
	}
	if shown == 0 {
		b.WriteString("Pas encore de morceau.")
	}
	b.WriteString("\n\n" + older.String() + "\n")
	if len(a.Events) > 0 {
		b.WriteString("## Concerts\n\n")
		for i := len(a.Events) - 1; i >= 0 && i >= len(a.Events)-10; i-- {
			e := getEvent(a.Events[i])
			if visibleEvent(e) {
				b.WriteString("- [" + md(e.Title) + "](" + page("event/"+itoa(e.ID)) + ") · " + md(e.Venue) + " · " + date(e.Start) + "\n")
			}
		}
	}
	b.WriteString("\n[Signaler ce profil](" + txlink.NewLink("Report").AddArgs("kind", "artist", "target", a.Addr.String(), "reason", "").URL() + ")\n")
	return b.String()
}

func renderArtists(pg int) string {
	var b strings.Builder
	b.WriteString(header("Artistes"))
	b.WriteString("| Artiste | Morceaux | Soutien reçu |\n|---|---|---|\n")
	artists.IterateByOffset((pg-1)*pageSize, pageSize, func(_ string, v any) bool {
		a := v.(*Artist)
		if !a.Hidden {
			b.WriteString("| " + artistLink(a) + " | " + itoa(len(a.Tracks)) + " | " + gnot(a.Tips) + " |\n")
		}
		return false
	})
	b.WriteString("\n" + pager("artists", pg, artists.Size()))
	return b.String()
}

func renderCatalog(pg int) string {
	var b strings.Builder
	b.WriteString(header("Catalogue"))
	b.WriteString("| # | Morceau | Genre | Durée | Licence | ♥ |\n|---|---|---|---|---|---|\n")
	tracks.ReverseIterateByOffset((pg-1)*pageSize, pageSize, func(_ string, v any) bool {
		t := v.(*Track)
		if playable(t) {
			b.WriteString("| " + itoa(t.ID) + " | " + trackLink(t) + " | " + md(t.Genre) + " | " + clock(t.Duration) +
				" | " + t.License + " | " + itoa(t.Likes) + " |\n")
		}
		return false
	})
	b.WriteString("\n" + pager("catalog", pg, tracks.Size()))
	return b.String()
}

func renderConcerts() string {
	var b strings.Builder
	b.WriteString(header("Concerts"))
	ts := now()
	b.WriteString("## À venir\n\n")
	up := upcomingEvents(ts, 20)
	if len(up) == 0 {
		b.WriteString("Aucun concert annoncé. [Annonce le tien](" + page("join") + ").\n")
	}
	for _, e := range up {
		b.WriteString("- **" + date(e.Start) + "** · [" + md(e.Title) + "](" + page("event/"+itoa(e.ID)) + ") · " +
			artistLink(getArtist(e.Artist)) + " · " + md(e.Venue) + "\n")
	}
	b.WriteString("\n## Passés\n\n")
	n := 0
	events.ReverseIterate("", "", func(_ string, v any) bool {
		e := v.(*Event)
		if visibleEvent(e) && e.Start <= ts {
			b.WriteString("- " + date(e.Start) + " · [" + md(e.Title) + "](" + page("event/"+itoa(e.ID)) + ")\n")
			n++
		}
		return n >= 20
	})
	return b.String()
}

func renderListener(addr address) string {
	var b strings.Builder
	b.WriteString(header("Auditeur " + short(addr)))
	if a := getArtist(addr); a != nil && !a.Hidden {
		b.WriteString("C'est aussi l'artiste " + artistLink(a) + ".\n\n")
	}
	l := &Listener{}
	if v, ok := listeners.Get(addr.String()).(*Listener); ok {
		l = v
	}
	b.WriteString("♥ " + itoa(l.Likes) + " morceaux aimés · ◈ " + gnot(l.Tipped) + " offerts aux artistes · 📡 " +
		itoa(l.Queued) + " programmés · 🎤 " + itoa(l.Attended) + " concerts\n\n")

	b.WriteString("## 🎟 Billets\n\n")
	ids := ownedBy(addr)
	if len(ids) == 0 {
		b.WriteString("Aucun billet. [Voir les concerts](" + page("concerts") + ").\n")
	}
	for i := len(ids) - 1; i >= 0 && i >= len(ids)-20; i-- {
		tk := getTicket(ids[i])
		e := getEvent(tk.Event)
		state := ""
		if tk.Attended {
			state = " · ✓ j'y étais"
		}
		b.WriteString("- [" + md(e.Title) + " #" + itoa(tk.Serial) + "](" + page("ticket/"+itoa(tk.ID)) + ") · " + date(e.Start) + state + "\n")
	}

	// Scans tracks newest first, bounded.
	b.WriteString("\n## 🏅 Badges premiers auditeurs\n\n")
	found, scanned := 0, 0
	tracks.ReverseIterate("", "", func(_ string, v any) bool {
		t := v.(*Track)
		scanned++
		if playable(t) {
			for i, e := range t.early {
				if e == addr {
					b.WriteString("[" + badgeSVG(t, i+1) + "](" + trackPage(t) + ")")
					found++
				}
			}
		}
		return found >= maxCovers || scanned >= 500
	})
	if found == 0 {
		b.WriteString("> [!INFO] Aucun badge pour l'instant\n> Sois parmi les 10 premiers à aimer un nouveau morceau : [nouveautés](" + page("catalog") + ").\n")
	}
	return b.String()
}

func renderEvent(e *Event) string {
	var b strings.Builder
	a := getArtist(e.Artist)
	b.WriteString(header("🎤 " + md(e.Title)))
	b.WriteString(ticketSVG(e, 0, false) + "\n\n")
	b.WriteString("**" + artistLink(a) + "** · " + md(e.Venue) + " · **" + date(e.Start) + "**\n\n")
	if e.Link != "" {
		b.WriteString("Lien : [" + e.Link + "](" + e.Link + ") (public)\n\n")
	}
	b.WriteString("Places : **" + itoa(e.Sold) + " / " + itoa(e.Capacity) + "**\n\n")
	p := paletteOf("event" + itoa(e.ID) + e.Title)
	b.WriteString(gaugeSVG([]int64{int64(e.Sold), int64(e.Capacity - e.Sold)}, []string{p.a, "#0000"}, "places vendues") + "\n\n")
	switch {
	case e.Cancelled:
		b.WriteString("> [!CAUTION] Concert annulé\n> Les paiements sont allés directement à l'artiste : contacte-le pour un remboursement.\n")
	case now() >= e.Start:
		b.WriteString("> [!NOTE] Concert passé\n> Les billets restent dans les collections de leurs détenteurs.\n")
	case e.Sold >= e.Capacity:
		b.WriteString("> [!WARNING] Complet\n")
	default:
		link := txlink.NewLink("BuyTicket").AddArgs("eventID", itoa(e.ID))
		label := "Réserver gratuitement"
		limit := "1 billet gratuit par wallet"
		if e.Price > 0 {
			link = link.SetSend(strconv.FormatInt(e.Price, 10) + denom)
			label = "Acheter pour " + gnot(e.Price)
			limit = "4 billets max par wallet"
		}
		b.WriteString("**[🎟 " + label + "](" + link.URL() + ")** · " + limit + "\n\n")
		b.WriteString("Le billet est un NFT (GRC721) à ton nom, et **100 % du prix va à l'artiste**. Tu peux l'offrir ; " +
			"il n'y a pas de marketplace de revente. À l'entrée, l'artiste le valide et il devient un souvenir « J'y étais ».\n")
	}
	b.WriteString("\n[Signaler ce concert](" + txlink.NewLink("Report").AddArgs("kind", "event", "target", itoa(e.ID), "reason", "").URL() + ")\n")
	return b.String()
}

func renderTicket(tk *Ticket) string {
	var b strings.Builder
	e := getEvent(tk.Event)
	b.WriteString(header("Billet #" + itoa(tk.Serial) + " · " + md(e.Title)))
	b.WriteString(ticketSVG(e, tk.Serial, tk.Attended) + "\n\n")
	if owner, err := ticketTok.OwnerOf(tokenID(tk.ID)); err == nil {
		b.WriteString("Détenteur : " + who(owner) + "\n\n")
	}
	b.WriteString("[Voir le concert](" + page("event/"+itoa(e.ID)) + ")")
	if !tk.Attended {
		b.WriteString(" · Détenteur : [🎁 offrir ce billet](" + txlink.NewLink("TransferTicket").AddArgs("to", "", "ticketID", itoa(tk.ID)).URL() + ")" +
			" · Artiste : [✓ valider à l'entrée](" + txlink.NewLink("CheckIn").AddArgs("ticketID", itoa(tk.ID)).URL() + ")")
	}
	b.WriteString("\n")
	return b.String()
}

func renderCharts() string {
	var b strings.Builder
	b.WriteString(header("📊 Classements"))

	b.WriteString("## Artistes les plus soutenus\n\n")
	var rows []bar
	for _, r := range topArtists {
		if a := getArtist(address(r.key)); a != nil && !a.Hidden {
			rows = append(rows, bar{a.Name, r.value})
		}
	}
	if len(rows) == 0 {
		b.WriteString("> [!INFO] Pas encore de soutien\n> Ouvre un morceau et soutiens son artiste.\n\n")
	} else {
		b.WriteString(barsSVG(rows, gnot) + "\n\n")
		for i, r := range topArtists {
			if a := getArtist(address(r.key)); a != nil && !a.Hidden {
				b.WriteString(itoa(i+1) + ". " + artistLink(a) + " · " + gnot(r.value) + "\n")
			}
		}
		b.WriteString("\n")
	}

	b.WriteString("## Morceaux les plus aimés\n\n")
	if len(topLiked) > 0 {
		b.WriteString("| # | Morceau | ♥ | ◈ | Soutiens |\n|---|---|---|---|---|\n")
		n := 0
		for _, r := range topLiked {
			if t := getTrack(atoi(r.key)); playable(t) {
				n++
				b.WriteString("| " + itoa(n) + " | " + trackLink(t) + " | " + itoa(t.Likes) + " | " + gnot(t.Tips) + " | " + itoa(t.Supporters) + " |\n")
			}
		}
		b.WriteString("\n")
	}

	b.WriteString("## Meilleurs soutiens\n\n")
	if len(topFans) > 0 {
		b.WriteString("| # | Auditeur | Offert |\n|---|---|---|\n")
		for i, r := range topFans {
			b.WriteString("| " + itoa(i+1) + " | " + who(address(r.key)) + " | " + gnot(r.value) + " |\n")
		}
	}
	return b.String()
}

func renderJoin() string {
	var b strings.Builder
	b.WriteString(header("🎤 Rejoindre GnoRadio"))
	b.WriteString("**0. Ton wallet est ton identité.** Installe [Adena](https://adena.app) et récupère des GNOT de test sur le faucet. " +
		"Chaque formulaire envoie une transaction que tu signes dans ton wallet. " +
		"Après signature, ta page sera `" + page("artist/") + "<ton nom>`.\n\n")

	b.WriteString("## 1. Crée ton profil d'artiste\n\n")
	b.WriteString(`<gno-form exec="Register">
<gno-input name="name" placeholder="Nom d'artiste (lettres latines, 2-32 caractères)" required="true" />
<gno-textarea name="bio" placeholder="Bio (280 caractères max)" rows="3" />
</gno-form>

`)
	b.WriteString("## 2. Publie un morceau\n\n")
	b.WriteString("1. Exporte en **MP3 320 kbps** ou **Opus 160 kbps**, autour de **-14 LUFS**.\n" +
		"2. Uploade le fichier sur IPFS (Pinata, Filebase, web3.storage) et vérifie qu'il se lit sur `https://ipfs.io/ipfs/<CID>`.\n" +
		"3. Remplis le formulaire. **Publie uniquement ta propre musique.** En publiant, tu déclares : *« " + rightsTerms + " »*\n\n" +
		"> [!CAUTION] Membres SACEM\n> Tu ne peux publier que des œuvres déclarées en licence CC non commerciale (option CC de la SACEM) : mets `sacem-nc` et une licence `CC-BY-NC`.\n\n")
	b.WriteString(`<gno-form exec="Publish">
<gno-input name="title" placeholder="Titre" required="true" />
<gno-input name="genre" placeholder="Genre (optionnel)" />
<gno-input name="credits" placeholder="Crédits : compo, texte, prod (optionnel)" />
<gno-input name="cid" placeholder="CID IPFS du fichier audio" required="true" />
<gno-input name="license" placeholder="Licence : CC0, CC-BY, CC-BY-SA, CC-BY-NC... ou ALL-RIGHTS-RESERVED" required="true" />
<gno-input name="cmo" placeholder="Société de gestion : none ou sacem-nc" value="none" />
<gno-input name="duration" placeholder="Durée, ex. 3:45" required="true" />
<gno-input name="splits" placeholder="Collaborateurs (optionnel) : g1...:30,g1...:15 en %" />
<gno-input name="rights" placeholder="Je détiens les droits et j'autorise la diffusion : oui" required="true" />
</gno-form>

`)
	b.WriteString("## 3. Annonce un concert\n\n")
	b.WriteString(`<gno-form exec="CreateEvent">
<gno-input name="title" placeholder="Nom du concert" required="true" />
<gno-input name="venue" placeholder="Lieu" required="true" />
<gno-input name="link" placeholder="Lien https (live ou salle, optionnel, public)" />
<gno-input name="start" placeholder="Date et heure UTC : 2026-11-20 21:00" required="true" />
<gno-input name="price" placeholder="Prix en GNOT (0 = gratuit)" required="true" />
<gno-input name="capacity" type="number" placeholder="Nombre de places" required="true" />
</gno-form>
`)
	return b.String()
}

func renderAbout() string {
	return header("Comment ça marche") +
		"<gno-columns>\n" +
		"### 📡 Une radio sans serveur\n\nLa grille est stockée sur la blockchain. Tout le monde entend le même morceau à la même seconde, sans serveur de streaming qu'on pourrait couper.\n" +
		"<gno-columns-sep />\n" +
		"### ◈ 0 % de commission, vérifiable\n\nLes tips et les billets ne restent jamais dans le contrat : ils partent chez l'artiste et ses collaborateurs dans la même transaction. Ne nous crois pas sur parole : lis le code.\n" +
		"<gno-columns-sep />\n" +
		"### 🎟 Des billets qui se souviennent\n\nChaque billet est un NFT dessiné par le contrat, à ton nom. Il s'offre, il se valide à l'entrée, et il reste dans ta collection après le concert.\n" +
		"</gno-columns>\n\n" +
		"## Qui fait quoi\n\n" +
		"- **Ici (gnoweb)** : le catalogue, les profils, le soutien, les billets et la preuve on-chain. Chaque page est générée par le contrat.\n" +
		"- **L'app GnoRadio (bientôt)** : le lecteur synchronisé en direct, l'upload IPFS, ton profil.\n" +
		"- **IPFS** : les fichiers audio. Tout le reste vit sur gno.land.\n\n" +
		"## Règles\n\n" +
		"- On ne publie que sa propre musique, avec une licence claire. Un fichier publié sur IPFS et sur la blockchain reste public : la modération peut le **masquer**, pas l'effacer.\n" +
		"- Signale un abus depuis la page concernée ; les signalements sont publics sur [la page modération](" + page("moderation") + ").\n\n" +
		"[Lire le code source](" + page("") + "$source) · [🎤 Rejoindre](" + page("join") + ")\n"
}

func renderModeration() string {
	var b strings.Builder
	b.WriteString(header("Modération"))
	b.WriteString("Modérateur actuel : " + who(admin) + ". Les signalements sont publics ; les décisions sont des transactions visibles on-chain.\n\n")
	b.WriteString("| # | Date | Type | Cible | Motif | Par |\n|---|---|---|---|---|---|\n")
	n := 0
	reports.ReverseIterate("", "", func(_ string, v any) bool {
		r := v.(*report)
		target := r.Target
		switch r.Kind {
		case "track":
			target = "[morceau " + r.Target + "](" + page("track/"+r.Target) + ")"
		case "event":
			target = "[concert " + r.Target + "](" + page("event/"+r.Target) + ")"
		case "artist":
			target = who(address(r.Target))
		}
		b.WriteString("| " + itoa(r.ID) + " | " + date(r.At) + " | " + r.Kind + " | " + target + " | " + sanitize.TableCell(r.Reason) + " | " + who(r.By) + " |\n")
		n++
		return n >= 30
	})
	return b.String()
}

// ---- formatting ----

func nav() string {
	return "[Radio](" + page("") + ") · [Catalogue](" + page("catalog") + ") · [Artistes](" + page("artists") +
		") · [Concerts](" + page("concerts") + ") · [Classements](" + page("charts") + ") · [Rejoindre](" + page("join") +
		") · [Comment ça marche](" + page("about") + ")\n\n"
}

func stats() string {
	return "**" + itoa(artists.Size()) + "** artistes · **" + itoa(nTracks) + "** morceaux · **" +
		itoa(nTickets) + "** billets · **" + itoa(listeners.Size()) + "** auditeurs · v" + version + "\n"
}

// page links to one of this realm's Render pages, wherever it is deployed.
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
		s += "[← Précédent](" + page(route+"?p="+itoa(pg-1)) + ") "
	}
	if pg*pageSize < total {
		s += "[Suivant →](" + page(route+"?p="+itoa(pg+1)) + ")"
	}
	return s + "\n"
}

func upcomingEvents(ts int64, n int) []*Event {
	var out []*Event
	scanned := 0
	events.ReverseIterate("", "", func(_ string, v any) bool {
		e := v.(*Event)
		scanned++
		if visibleEvent(e) && !e.Cancelled && e.Start > ts {
			i := len(out)
			for i > 0 && out[i-1].Start > e.Start {
				i--
			}
			out = append(out, nil)
			copy(out[i+1:], out[i:])
			out[i] = e
		}
		return scanned >= 200
	})
	if len(out) > n {
		out = out[:n]
	}
	return out
}

func trackPage(t *Track) string { return page("track/" + itoa(t.ID)) }

func trackLink(t *Track) string {
	if t == nil {
		return ""
	}
	return "[" + md(t.Title) + "](" + trackPage(t) + ") · " + artistLink(getArtist(t.Artist))
}

func artistLink(a *Artist) string {
	if a == nil {
		return ""
	}
	s := "[" + md(a.Name) + "](" + page("artist/"+a.Addr.String()) + ")"
	if a.Verified {
		s += " ✓"
	}
	return s
}

// who names an address: the artist when there is one, else a short link.
func who(addr address) string {
	if a := getArtist(addr); a != nil && !a.Hidden {
		return artistLink(a)
	}
	return "[" + short(addr) + "](" + page("listener/"+addr.String()) + ")"
}

func likeURL(t *Track) string { return txlink.NewLink("Like").AddArgs("trackID", itoa(t.ID)).URL() }

func tipURL(t *Track, gnots int64) string {
	return txlink.NewLink("Tip").AddArgs("trackID", itoa(t.ID)).SetSend(strconv.FormatInt(gnots*ugnot, 10) + denom).URL()
}

func audioURL(t *Track) string { return "https://ipfs.io/ipfs/" + t.CID }

func licenseURL(l string) string {
	switch l {
	case "CC0-1.0":
		return "https://creativecommons.org/publicdomain/zero/1.0/"
	case "ALL-RIGHTS-RESERVED":
		return page("about")
	}
	slug := strings.ToLower(strings.TrimSuffix(strings.TrimPrefix(l, "CC-"), "-4.0"))
	return "https://creativecommons.org/licenses/" + slug + "/4.0/"
}

// md escapes user text (already restricted by validText) for inline markdown.
func md(s string) string { return sanitize.InlineText(s) }

func itoa(n int) string     { return strconv.Itoa(n) }
func itoa64(n int64) string { return strconv.FormatInt(n, 10) }

func atoi(s string) int {
	n, err := strconv.Atoi(s)
	if err != nil {
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

func date(unix int64) string { return time.Unix(unix, 0).UTC().Format("2006-01-02 15:04") + " UTC" }

func hour(unix int64) string { return time.Unix(unix, 0).UTC().Format("15:04") }

// gnot formats ugnot as GNOT with up to 6 decimals.
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
