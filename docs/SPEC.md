# GnoRadio — spécification v0.3

> Lecteur de musique **et** radio communautaire, on-chain sur gno.land.
> Interface en **anglais**. Admin = l'adresse personnelle du porteur du projet.
> Rien n'est déployé sur un réseau public avant recette sur devnet local.

## 1. Produit

Deux façons d'écouter, dans le même lecteur :

- **Library** (à la demande) : albums, playlists, morceaux, dans l'ordre qu'on veut. Lecture 100 % côté app, aucune transaction.
- **Live** (radio) : des **stations** (une principale + une par genre). Tout le monde entend la même chose à la même seconde, d'après une grille on-chain.

Trois origines de morceaux, mélangées dans les mêmes genres, albums, playlists et stations :

| | Morceau d'artiste | Morceau curé CC | Morceau Audius |
|---|---|---|---|
| Publié par | l'artiste (son wallet) | l'admin (import curé) | l'admin (sélection) |
| Base juridique | déclaration de l'artiste | CC0 / CC BY / CC BY-SA | Audius Open Music License §1.2 (streaming et diffusion publique accordés aux lecteurs) |
| Audio | `ipfs://`, `ar://`, `https://` + sha256 | lien source + sha256, copie autorisée | `audius:<trackId>`, lu via l'API, **cache de session seulement** |
| Attribution | artiste | artiste, licence, source | artiste, © , mention OML, lien Audius (§1.5) |
| Tips | oui, 100 % artiste + collaborateurs | non, « Claim this profile » | non, « Support on Audius » + « Claim this profile » |
| Concerts, billets | oui | après réclamation | après réclamation |

Un artiste curé ou Audius qui **réclame** son profil (code sur une page qu'il contrôle, vérifié par un robot qui signe un certificat ; 72 h d'attente publique) récupère ses morceaux : tips et concerts activés.

## 2. Fonctionnalités, par module et par phase

Statut : **0.3** = ce chantier · **dApp** = côté app · **0.4+** = plus tard · **✕** = abandonné.

### Catalogue (`r/gnoradio/catalog`)
| Fonctionnalité | Phase |
|---|---|
| Profils d'artistes (nom latin anti-usurpation, bio courte, vérifié) | 0.3 |
| Artistes curés non réclamés + réclamation (`AssignArtist`) | 0.3 |
| Morceaux : titre, genre (liste fixe), durée, licence SPDX, crédits, `audio` + `cover` (URI + sha256), source + attribution | 0.3 |
| Hébergeurs autorisés (`https`), gérés par l'admin ; `ipfs://`, `ar://`, `audius:` | 0.3 |
| Correction d'un morceau (`EditTrack`), signalement « broken link » | 0.3 |
| Albums / EP | 0.3 |
| Playlists publiques (publiées en une signature) | 0.3 |
| Likes, Follow (stockés par utilisateur), badges premiers auditeurs | 0.3 |
| Tips partagés (0 % de commission), top 10 incrémentaux | 0.3 |
| Signalements, masquage (morceau, album, artiste), gel, successeur | 0.3 |
| Exports JSON paginés | 0.3 |
| Modifier les parts avec l'accord des collaborateurs | 0.4+ |
| Paroles (fichier lié) | 0.4+ |
| Commentaires | 0.4+ |
| Licences commerciales façon Jamendo | ✕ |

### Radio (`r/gnoradio/radio`)
| Fonctionnalité | Phase |
|---|---|
| Stations : principale + une par genre | 0.3 |
| Rotation par station, structure scalable (§4.2), stable aux ajouts et retraits | 0.3 |
| Programmation par les auditeurs : démarre à la fin du titre en cours ; quotas | 0.3 |
| Pick à heure choisie (`QueueAt`, 15 min à 24 h, 4 par heure, voir v0.8) | 0.8 |
| Synchronisation permissionless du catalogue vers les stations (`Sync`, `Refresh`, `RefreshArtist`) | 0.3 |
| `ScheduleJSON(station)` pour la dApp | 0.3 |
| Flow de Main comme une vraie radio : sets de 3 à 5 morceaux d'un genre, transition vers un genre voisin sur une ligne d'énergie, horloge du jour (calme la nuit, énergie le soir), jamais deux fois le même artiste ; `Sync` écrit l'heure suivante, appelé toutes les 30 min par le robot (`app/netlify/functions/sync.mts`) | 0.5 |
| Stations éditoriales basées sur une playlist, émissions à heure fixe, jingles | 0.4+ |
| Stations « New this week » (`NumGenres+1`, les 300 derniers morceaux intégrés) et « Listeners' choice » (`NumGenres+2`, les 500 derniers morceaux distincts choisis par les auditeurs via `Queue`/`QueueWithNote`, plus le top des likes à chaque `Sync`) : anneau de taille fixe, une fois plein le créneau le plus ancien est réutilisé sur place (son morceau quitte `homes`), la rotation ne grandit plus, coût constant ; programmables comme toute station, sans contrôle de genre | 0.5 |
| Enchères de créneaux | ✕ (radio commerciale) |

### Concerts et billets (`r/gnoradio/tickets`)
| Fonctionnalité | Phase |
|---|---|
| Concerts, billets GRC721 dessinés on-chain, 100 % du prix à l'artiste | 0.3 (repris de 0.2) |
| Check-in « I was there », annulation, don de billet | 0.3 |
| `TokenURI`, billets par détenteur | 0.3 |
| Royalties sur revente | ✕ |

### Site gnoweb (`r/gnoradio/home`)
| Fonctionnalité | Phase |
|---|---|
| Toutes les pages en anglais, lecture des 3 autres realms | 0.3 |
| Pochettes SVG générées (si pas de `cover`) | 0.3 |
| Stations, catalogue, albums, playlists, artistes, concerts, classements, modération | 0.3 |

### dApp (Vite + React)
| Fonctionnalité | Phase |
|---|---|
| Lecteur Library + Live, file d'attente, aléatoire, répétition | dApp |
| Save (local, gratuit) vs Like (on-chain, public) | dApp |
| Upload audio et pochette, calcul du sha256 | dApp |
| Recherche (index construit depuis les exports et les événements) | dApp |
| Cache hors ligne, normalisation du volume, vérification d'empreinte | dApp |
| Clés de session (moins de popups Adena) — à valider avec Adena | dApp |
| Partage, lecteur intégrable | dApp |

## 3. Où vit chaque donnée

| Niveau | Contenu |
|---|---|
| **On-chain** | ce qui prouve, paie ou engage : identités, fiches, liens + empreintes, licences, parts, tips, albums, playlists publiques, likes, follows, stations, grilles, billets, modération |
| **Calculé** | pochettes SVG par défaut, badges, billets dessinés, compteurs |
| **Stockage externe** (lien + sha256) | audio, pochettes, paroles, bio longue |
| **App seulement** | écoutes, historique, file d'attente Library, Save, playlists privées, recherche, nombre d'auditeurs |

Une écoute ne coûte jamais rien et ne passe jamais par la chaîne.

## 4. Architecture on-chain

```
gno.land/p/gnoradio/blocks/v0     somme de durées en blocs (rotation)      — pur, testé
gno.land/p/gnoradio/svg/v0        dessin SVG (pochette, billet, graphes)   — pur
gno.land/p/gnoradio/text/v0       helpers de texte (clés, JSON, GNOT)      — pur
gno.land/p/gnoradio/store/v0      encodages compacts (records, buckets)    — pur
gno.land/p/gnoradio/safe/v0       filtre des dédicaces                     — pur
gno.land/r/gnoradio/catalog/v0    artistes, morceaux, albums, playlists, likes, follows, tips
gno.land/r/gnoradio/radio/v0      stations, rotations, programmation       — lit catalog
gno.land/r/gnoradio/tickets/v0    concerts, billets GRC721                 — lit catalog
gno.land/r/gnoradio/home/v0       site gnoweb + Info()                     — lit tout
```

Dépendances à sens unique : `radio`, `tickets`, `home` importent `catalog` ; `catalog` n'importe aucun realm.
Échanges entre realms : par **identifiants** et getters qui renvoient des **valeurs** (jamais de pointeurs).
Chaque realm a son `admin` (initialisé au déployeur, puis `TransferAdmin`).
Le nom `gnoradio` devra être réservé on-chain avant onyx.

### 4.1 Règles de passage à l'échelle

1. Aucune boucle sur « tous » les morceaux, artistes ou utilisateurs dans une écriture ni dans une page : `avl.Tree`, pagination, plafonds.
2. Une action coûte le même gas avec 100 ou 100 000 morceaux : vérifié par des **tests de charge** (budgets §6).
3. Pas de gros slice global : les listes qui grandissent sont des arbres ou des blocs.
4. Données d'un utilisateur rangées sous son entrée (likes, follows, playlists) ; un like ne réécrit pas un objet partagé géant.
5. Classements = top 10 mis à jour à l'écriture.
6. Le spam coûte à son auteur (dépôt de stockage) + limites par compte.

### 4.2 Rotation radio scalable (`p/gnoradio/blocks`)

Chaque station a une liste ordonnée de créneaux (un morceau, une durée).
Stockage en **blocs de 128 créneaux**, regroupés par 128 blocs (un groupe = 16 384 créneaux, avec la somme de chaque bloc) + un tableau des totaux par groupe :

- trouver le créneau à la position `p` de la boucle : parcourir les totaux de groupes, les sommes d'un groupe, puis un bloc → O(n/16 384 + 128 + 128) ;
- ajouter en fin : O(1) ;
- retirer : la durée du créneau passe à 0 ; une écriture réécrit un bloc, un groupe (128 références et sommes) et les tableaux de groupes (une entrée par 16 384 créneaux), jamais un tableau de tous les blocs : coût plat jusqu'à ~2 M de créneaux ;
- `Set(i, id, dur)` réutilise un créneau (anneaux de New et Choice) ;
- l'ancre de temps est corrigée pour que personne ne saute de morceau.

Position dans la boucle à l'instant `t` : `(t − epoch − pausé(t)) mod total`, où `pausé` = temps pris par les morceaux programmés.

### 4.3 API principale (extraits)

```go
// catalog
func RegisterArtist(cur realm, name, bio string)
func CreateCuratedArtist(cur realm, name, bio, sourceURL string) int          // admin
func AssignArtist(cur realm, artistID int, owner address)                      // admin, réclamation
func PublishTrack(cur realm, title string, genre int, duration, license, credits, audio, audioSHA, cover, coverSHA, splits, rights string) int
func ImportTrack(cur realm, artistID int, title string, genre int, duration, license, credits, audio, audioSHA, cover, coverSHA, sourceURL, attribution string) int // admin
func EditTrack(cur realm, id int, ...)
func CreateAlbum(cur realm, title, cover, coverSHA string, year int, trackIDs string) int
func PublishPlaylist(cur realm, title, trackIDs string) int
func Like(cur realm, trackID int)
func Follow(cur realm, artistID int)
func Tip(cur realm, trackID int)                     // payable
func Report(cur realm, kind, target, reason string)
func AllowHost(cur realm, host string, allowed bool) // admin
// getters pour les autres realms (valeurs uniquement) — CONTRAT FIGÉ v0.3
const NumGenres = 20                                  // genres 1..20, 0 = invalide
func GenreName(g int) string                           // "" si hors bornes
func TrackCount() int                                  // ids 1..TrackCount()
func TrackBrief(id int) (artistID, genre int, duration int64, playable bool) // playable=false si inconnu, masqué, artiste masqué
func TrackTitle(id int) string
func ArtistCount() int                                 // ids 1..ArtistCount()
func ArtistName(artistID int) string
func ArtistOwner(artistID int) address                 // address("") si non réclamé (curé / Audius)
func ArtistOf(owner address) int                       // 0 si aucun profil
func ArtistVisible(artistID int) bool

// radio
func Sync(cur realm, max int)        // permissionless : intègre les nouveaux morceaux du catalogue
func RefreshArtist(cur realm, artistID, offset int) int // permissionless : rafraîchit 50 morceaux d'un artiste, renvoie l'offset suivant (0 = fini)
func Queue(cur realm, station, trackID int)
func NowPlaying(station int) (trackID int, offset int64, queued bool)
func ScheduleJSON(station, horizon int) string
```

### 4.4 Financement de GnoRadio et activité (v0.3.1)

L'artiste garde toujours 100 % ; la part de GnoRadio s'ajoute, visible, vers une trésorerie on-chain.

```go
// catalog
func SupportGnoRadio(cur realm)                                   // payable, 0.1..1 000 000 GNOT → trésorerie
func TipWithSupport(cur realm, trackID int, supportPct int)       // payable, supportPct 0..50 ; artiste = T*100/(100+pct), reste → trésorerie ; Tip = pct 0
func SetTreasury(cur realm, to address)                           // admin
func SetMonthlyGoal(cur realm, ugnot int64)                       // admin
func Treasury() address
func SupportJSON() string   // {"treasury","total","supporters","month":"YYYY-MM","monthTotal","goal","top":[{"address","amount"}]}
func ActivityJSON(limit int) string // ≤64, du plus récent : [{"kind","by","track","artist","amount","at"}]
                                    // kind : publish | like | follow | tip | support | playlist | album | claim
// radio
func CuratorQueue(cur realm, stationID, trackID int)              // admin radio : sans quotas (doublon, genre, 30 max conservés)
func ActivityJSON(limit int) string // ≤64 : [{"kind":"queue"|"curator","by","track","station","start","at"}]
// tickets
func SetServiceFee(cur realm, ugnot int64)                        // admin, 0..10 GNOT ; billets payants : prix + frais exacts
func ServiceFee() int64
func FeesJSON() string      // {"serviceFee","treasury"} ; EventsJSON ajoute "fee"
```

Les flux d'activité sont des anneaux de 64 entrées de taille fixe : le stockage ne grandit pas.

**Garde-fous (audit sécurité, v0.3.2)** — ajouts uniquement, aucune signature existante modifiée :

```go
// catalog
func ResolveReport(cur realm, id int)        // admin : clôt un signalement ; ≤5 ouverts par signaleur, maxReports = signalements OUVERTS
func ReleaseName(cur realm, name string)     // admin : libère un nom réservé qu'aucun artiste visible n'utilise
// radio
func DropSlot(cur realm, stationID, trackID int) // admin : coupe le créneau de rotation (durée 0, persistant malgré Refresh) et retire le titre de la file
func RestoreSlot(cur realm, stationID, trackID int) // admin : annule DropSlot
func Unqueue(cur realm, stationID, trackID int)  // admin : retire le titre de la file d'attente
```

- Noms d'artiste : lettres ASCII + accents Latin-1 (À–ÿ hors × ÷), chiffres, espace, `. ' - &` ; réservés sous un squelette (minuscules, accents retirés, pleine chasse → ASCII). Renommer libère l'ancien nom ; un artiste masqué ne peut pas renommer.
- `SetTreasury` refuse l'adresse du catalogue et celles des realms radio, tickets et home. `Like` n'ajoute pas deux fois la même adresse aux badges « early ».
- Radio : un changement de genre met à jour toutes les stations (créneau orphelin à 0) ; un titre non jouable n'est jamais diffusé (`NowPlaying`, `ScheduleJSON`). `Queue` : un titre par station et par heure et par wallet ; ≤ 7 200 s de programmation d'auditeurs à venir par station (`CuratorQueue` exempté).
- Tickets : index `upcoming` trié par date (ajout à la création, retrait à l'annulation ou au masquage) ; `Upcoming` et `EventsJSON(upcoming=true)` le lisent (le plus proche d'abord) ; ≤ 10 concerts futurs non annulés par artiste. `RefreshArtist(artistID)` (ouvert à tous) relit la visibilité de l'artiste dans le catalog : les concerts d'un artiste masqué quittent l'index (le spam masqué n'occupe plus le parcours de 1 000 entrées), ceux d'un artiste restauré y reviennent.

## 5. Catalogue de lancement (~1 200 morceaux)

**La qualité vient d'une liste blanche, jamais d'une recherche ouverte.** Internet Archive sert d'**hébergeur** stable pour des artistes et labels choisis, pas de source de découverte.

| Source | Titres | Stations | Hébergement |
|---|---|---|---|
| **Audius** : liste blanche d'artistes et de labels écoutés (pas de remix non autorisés) | ~400 | tous genres, surtout électro, hip-hop, house, lo-fi | Audius (lecture via API, pas de copie) |
| Artistes de référence (Scott Buckley, Komiku, Monplaisir, Josh Woodward, Jahzzar, Chris Zabriskie, Kevin MacLeod en BY, Rolemusic…) | ~300 | cinématique, chill, pop, jazz, folk, électro | archive.org ou site de l'artiste |
| ccMixter, sélections éditoriales (CC BY) | ~150 | hip-hop, beats, downtempo | **copie** IPFS/CDN (anti-hotlink) |
| ~15 netlabels écoutés et validés | ~200 | techno, house, synthwave, ambient | archive.org |
| Ziklibrenbib, Dogmazic (sélection manuelle) | ~150 | rock, indie, monde, scène FR | selon la source |

Exclus : FMA (liens directs interdits), SoundCloud (radio et agrégation interdites), Jamendo (licence commerciale probable, à demander), licences NC/ND (prudence, à revoir avec un avis juridique).

Audius (conditions lues le 06/10/2026, versions du 2 juillet 2025) : l'OML §1.2 accorde aux « Music Players » le droit de streamer et de diffuser publiquement ; l'API interdit le cache persistant, l'extraction massive et l'entraînement d'IA. On stocke l'identifiant Audius et l'attribution ; titre et pochette sont relus en direct par la dApp. Clé API à demander (api.audius.co/plans).

Pipeline (`tools/curate`) : liste blanche → métadonnées (API archive.org / ccMixter) → filtres (licence, durée 1:30–10:00, débit ≥ 192 kbps, pochette, métadonnées complètes) → normalisation (genre, artiste, licence SPDX) → calcul sha256 et LUFS → écran d'écoute keep / drop → fichier d'import → `ImportTrack` en lots.

Genres (liste fixe, `genre` = indice) : 1 Electronica · 2 Synthwave · 3 Ambient · 4 Techno · 5 House · 6 Drum & Bass · 7 Dubstep & Trap · 8 Lo-fi Beats · 9 Hip-hop & Rap · 10 R&B & Soul · 11 Rock & Indie · 12 Metal & Punk · 13 Pop · 14 Jazz & Blues · 15 Folk & Acoustic · 16 Cinematic & Classical · 17 World · 18 Latin · 19 Reggae & Dub · 20 Funk & Disco.

## 6. Budgets (vérifiés par les tests)

| Action | Gas max | Indépendant du volume |
|---|---|---|
| PublishTrack / ImportTrack | 25 M | oui |
| Like, Follow, Tip | 15 M | oui |
| Queue | 20 M | oui (file ≤ 30) |
| NowPlaying / rotation (100 000 créneaux) | 60 M | ~O(n/128) |
| Page gnoweb la plus lourde | 400 M (budget 3 Md) | oui |

## 7. Décisions

| Sujet | Décision |
|---|---|
| Langue | anglais |
| Admin | adresse personnelle (pas de multisig) |
| Déploiement | devnet local jusqu'à la recette ; onyx sur demande explicite |
| Front | style sobre « suisse » (canvas de design) |
| Programmation | gratuite avec quotas (ouvert) |
| Contrepartie bêta artistes | ouvert |

### Revue v0.4.1 (lecture et gnoweb)

- catalog : `GenrePage(genre, offset, limit)`, `GenreCount(genre)` (index par genre), `FollowsPage(addr, offset, limit)`, `SupportInfo()`, `AudiusLicense` exporté ; `ReportCount()` compte désormais les signalements **ouverts**. `Unlike`, `Unfollow` et `Report` respectent `Freeze`. Les noms d'artiste sont réservés sous un squelette sans espaces ni ponctuation, avec les confusables repliés (i/l/1, 0/o, rn/m) ; les doubles espaces sont refusés.
- radio : `Prune` supprimé (doublon de `Refresh`) ; `RefreshArtist`, `RestoreSlot`.
- tickets : un billet d'un concert masqué n'affiche plus titre, lieu ni artiste ; `CheckIn` refuse un concert annulé ; `&` accepté.
- JSON : les champs validés (texte, noms, URLs, hashes, licences, adresses) sortent avec `text.Str()` sans échappement, car échapper coûte ~1 M de gas par champ (`TracksJSON(0,50)` passait de ~96 M à ~300 M) ; des tests vérifient que les validateurs refusent `"`, `\` et les caractères de contrôle.
- home : `SetAppURL(cur, url)` (admin du catalog, https, 100 caractères max) et liens « Open in the app » ; lien d'achat = prix + frais de service ; licences CC toutes versions/ports ; `catalog?g=N`, pagination (artiste, playlist, auditeur, concerts passés, modération) ; soutien GnoRadio, fil d'activité, liens `$source` ; chaque realm a un `Render` qui renvoie vers home.

### Revue v0.4.2 (gas et dépôt)

- **Qui paie `Sync` :** `Sync` est ouvert à tous et le dépôt de stockage est payé par l'appelant, environ 0,1 à 0,2 Ko par morceau depuis la v0.4.4 (≈ 0,02 GNOT ; un lot de 200 ≈ 4 GNOT). En pratique c'est l'admin (Studio, lots de 20) qui le lance après une vague d'imports ; un artiste peut aussi le lancer pour passer à l'antenne sans attendre. La station principale ne tient plus d'index (le morceau `id` est au créneau `id-1`) et un index `homes` (morceau → stations de genre) limite `Refresh`/`RefreshArtist` aux stations qui tiennent le morceau.
- `PublishPlaylist` / `UpdatePlaylist` ne vérifient plus que la plage d'ids et les doublons (≈ 4× moins de gas pour 200 morceaux) ; les morceaux masqués sont filtrés à la lecture.
- `EventsJSON(offset, limit, false)` saute directement à `offset` (offset et limit comptent les concerts stockés, masqués compris) et renvoie `"next"`.
- tickets : `ownedCount` supprimé (écrit, jamais lu).
- catalog : `LikedPage` renvoie les morceaux les plus récents d'abord ; getters étroits `PlaylistBrief`, `ArtistTrackCount`, `ArtistTrackPage` ; pages de migration `UsersPage`, `SupportersPage` ; radio : `RotationPage(station, offset, limit)`.

### Revue v0.4.4 (dépôt de stockage compact)

- Nouveau paquet `p/gnoradio/store/v0`, déployé avant les realms (après `text`) : `Seq` (liste en morceaux de 16 enregistrements), `Map` (table de hachage à seaux fixes), enregistrements compacts (`Rec`/`Field`/`With`, en-tête de longueurs en base 64), listes d'ids prêtes pour le JSON (8 caractères + virgule), `IDs` (ensemble trié en morceaux de 512).
- catalog : morceaux, artistes, albums, playlists et auditeurs sont des chaînes compactes dans des `Seq` ; index par propriétaire / nom / auditeur dans des `Map` ; `Like`/`Unlike` réécrivent un seul champ sans décoder le morceau.
- radio : blocs de rotation en chaînes (4 caractères base 64 par id, 2 par durée : id ≤ 16 777 215, durée ≤ 4095 s) ; `homes` et `lastQ` compacts.
- Mesuré sur gnodev (devseed, 116 morceaux) — dépôt par opération : morceau importé ≈ 6,1 Ko → 0,31 Ko ; morceau publié ≈ 6,4 Ko → 0,28 Ko ; `Sync` ≈ 4,2 Ko → 0,08–0,22 Ko par morceau ; like suivant ≈ 2,5 Ko → 0,1 Ko. Lectures moins chères (`TracksJSON(0,100)` 181 M → 122 M de gas).
- Changements visibles : `UsersPage` suit l'ordre des seaux (stable, non trié) ; les tableaux d'ids du JSON contiennent des espaces (mêmes valeurs) ; une liste de likes par auditeur plafonne à ~29 000 ; dépôt initial des realms plus élevé (seaux vides).

### Revue v0.4.3 (simplification)

- Paquets partagés : `p/gnoradio/svg/v0` (canevas SVG, `Escape`, `Clip`, `FNV`) et `p/gnoradio/text/v0` (`Key`, `Str`, `Valid`, `Digits`, `GNOT`), déployés avant les realms ; rendu SVG identique à l'octet près (tests « golden »).
- API retirée : `catalog.HasLiked`, `catalog.IsFollowing` (remplacés par `LikedPage` / `FollowsPage` / `UserJSON`) et `home.AppURL` (lien lisible dans le rendu).

### Revue v0.5 (vérification, stockage, flow)

- **Vérification des artistes sans humain** (`catalog/verify.gno`, `docs/VERIFICATION.md`) : tips et billets payants réservés aux artistes vérifiés ; preuve sur une page de l'artiste lue par un robot à rôle limité, délai public de 72 h, `CancelClaim` / `ResetOwner` pour l'admin ; aucun séquestre.
- **Stockage en arbre** (`store/v0`) : `Seq`, `Map` et `IDs` reposent sur un arbre clairsemé de fanout 32 avec compteurs. Une écriture réécrit une feuille et un chemin (log32 du nombre de feuilles : 3 niveaux pour 32 000 feuilles) au lieu du tableau de tous les morceaux ou seaux, qui faisait croître le gas avec le catalogue. Les pages à un offset quelconque (`Keys`, `IDs.Page`) descendent par les compteurs. Seaux des `Map` clairsemés : dimensionnés pour 1 M d'auditeurs sans coût tant qu'ils sont vides.
- `updateTop` ne réécrit plus le classement quand il ne change pas.
- **Flow de Main** (`radio/flow.gno`) : voir §2 Radio.
- **Dédicaces** (`radio.QueueWithNote`, `p/gnoradio/safe/v0`) : un pick peut porter une dédicace de 40 caractères affichée à l'antenne. Filtrage sans humain : caractères simples, ni lien ni numéro de téléphone, liste multilingue (LDNOOBW en/fr/es/de/it/pt/nl, CC BY 4.0, mots-clés forts de gnolang/gno#5178, insultes et termes haineux ajoutés), après normalisation (accents, leet, lettres répétées ou espacées). `ReportNote` : trois signalements distincts (de listeners ayant déjà fait un pick) masquent la dédicace aussitôt ; une première dédicace masquée est un avertissement (strike), une deuxième en 7 jours (`muteFor`) suspend les dédicaces de l'auteur 7 jours. `RestoreNote` (admin) ne s'applique qu'à une dédicace masquée et retire le strike qu'elle avait donné. À remplacer par `p/gnoland/antispam` quand gnolang/gno#5178 sera déployé.
- **Pick prioritaire** : un pick prend immédiatement la place du flow à l'antenne (fondu côté app) et remplace son prochain titre ; après un pick d'auditeur en cours, il passe à la suite.
- **Modération des dédicaces avant la transaction, sans humain, gratuite pour GnoRadio** : (1) l'app envoie le texte au robot (`app/netlify/functions/dedication.mts`), qui applique le filtre on-chain `p/gnoradio/safe` (≈2 000 mots et expressions, 20 langues, contournements) puis le modèle de modération d'OpenAI (gratuit, multilingue, contextuel, seuils dans `app/src/lib/moderation.ts`) ; s'il passe, le robot signe `radio.NoteMessage(note, expires)` (Ed25519, 10 min) ; (2) l'auditeur envoie `QueueWithNote` avec ce certificat et paie son gas ; le realm revérifie `safe.Note` et la signature, refuse sinon, et la dédicace s'affiche aussitôt ; sans clé ou si OpenAI est en panne, les dédicaces sont en pause, le pick sans dédicace marche ; (3) trois signalements (de listeners ayant déjà fait un pick) la masquent ; une deuxième dédicace masquée en 7 jours coupe les dédicaces de l'auteur 7 jours. L'admin peut `RestoreNote`, `Unmute`, `SetModBot("")` (coupe les dédicaces). Masquée sur la chaîne = masquée partout (app et gnoweb).


### Incitations des auditeurs (v0.6)

Programmer et partager rapporte, payé par les tippers, jamais par GnoRadio (chacun paie son gas).

```go
// catalog (promo.gno)
func SetPromoShare(cur realm, pct int)   // artiste propriétaire : 0..20 %, 5 % par défaut ; ArtistJSON expose "promo"
func PromoShare(artistID int) int
func RadioTip(cur realm, trackID, supportPct int, tipper, picker, ref address, total int64) (toPicker, toRef int64)
                                         // appelable par le realm radio désigné seulement (cur.Previous().PkgPath() == RadioRealm())
func SetRadioRealm(cur realm, pkgPath string) // admin : radio v1 sans nouveau catalog ; l'ajoute aux realms frères
func SetSibling(cur realm, pkgPath string, on bool) // admin : realms GnoRadio (v0 et suivants) jamais trésorerie, référent ni collaborateur
// radio (curators.gno)
func TipOnAir(cur realm, stationID, trackID, supportPct int, ref address) // payable, IsUserCall
func CuratorOf(addr address) Curator     // picks, tips reçus à l'antenne, gains (ugnot), tous temps
func TopCurators(stationID int) []Curator // top 10 de la semaine (lundi 00:00 UTC), -1 = toutes stations
func CuratorJSON(addr address) string     // {"address","picks","tips","earned","week":{"picks","tips","earned","rank"}}
func TopCuratorsJSON(stationID int) string // {"station","since","top":[{"address","picks","tips","earned"}]}
```

- **Part du curateur, vérifiée on-chain.** `TipOnAir` reçoit le tip (`OriginSend`, ugnot seul), cherche lui-même dans sa grille le pick d'auditeur de `trackID` à l'antenne sur la station (ou fini depuis moins de 2 min), jamais un picker donné par le client, transfère tout au catalog puis appelle `RadioTip`. Le catalog paie comme `TipWithSupport` (artiste vérifié, pas son propre titre, bornes, trésorerie) et prélève sur la part artiste la part promo de l'artiste : au picker, ou moitié picker (ugnot impair au picker) / moitié `ref`. Aucune part au tipper, à l'artiste, à un realm GnoRadio, ni pour les picks de l'admin radio (`CuratorQueue`). Le total ne dépasse jamais le pourcentage accepté par l'artiste ; tout panic annule la transaction entière. `Tip`/`TipWithSupport` directs : aucune part.
- **Lien de partage.** `?ref=<g1…>` est gardé pour la session de l'app ; un tip de cette session passe par `TipOnAir` avec `ref`.
- **Statut de curateur.** Chaque pick d'auditeur (`Queue`, `QueueWithNote`) et chaque tip partagé met à jour en O(1) les compteurs de l'adresse et le top 10 hebdomadaire de la station et de toutes les stations (1 point par pick, 1 par tip reçu à l'antenne). gnoweb : bloc « Top curators this week » sur la page de station.
- **App.** Lecteur : état rouge « Your pick · on air » (titre, cadran) et notification du navigateur si permise (demandée au premier pick, jamais au chargement), puis le résultat à la fin : likes et tips gagnés pendant la diffusion (comptes du catalog avant/après) et gains du picker ; pas de nombre d'auditeurs (non on-chain). Pick next : sélection puis bouton « Push on air », gain affiché, partage avec `ref`, titres repris sous 3 h grisés. Fiche de tip : répartition exacte (artiste, collaborateurs, picker, référent, trésorerie), +10 % GnoRadio décoché par défaut, « A gift, not a purchase ». Me : picks, gains, rang de la semaine ; réglage de la part promo pour l'artiste. Community : top curateurs de la semaine.
- Gas mesuré (`gno test -print-runtime-metrics`, cycles VM hors stockage) : `Queue` ≈ 4,8 M → 6,8 M ; `TipWithSupport` ≈ 3,3 M → 3,4 M ; `TipOnAir` ≈ 7,2 M (3,5 M côté radio + 3,7 M `RadioTip` avec picker et référent).

### Revue v0.6.1 (sécurité, gas, migration)

- **Vérification** : plus de plafond global de 50 claims par jour (une seule personne pouvait l'épuiser chaque jour). `SetBot` (changement ou révocation de la clé du robot) annule d'un coup toutes les claims en attente signées par l'ancienne clé : `FinalizeClaim` les refuse, `ClaimJSON` ne les montre plus ; l'artiste refait sa claim avec un certificat neuf.
- **Realms frères réglables** : `SetRadioRealm(path)` (le realm autorisé à appeler `RadioTip`, ajouté aux frères), `SetSibling(path, on)`, `RadioRealm()`, `SiblingRealms()`. Un collaborateur (`splits`) ne peut plus être un realm GnoRadio (les parts y seraient bloquées). Le chemin catalog utilisé par radio reste celui de son import (`radio` v1 importera le catalog qu'il paie).
- **Likes** : rangés à part, par plage de 512 ids de morceaux (`likeSets`, clé `adresse/plage`) ; un like réécrit au plus une liste de 4,6 Ko et ne touche plus l'enregistrement de l'auditeur, ni ceux de ses voisins de chunk ; plus de plafond ~29 000. `LikedPage` et le compte de `UserStats` lisent une entrée par 512 morceaux du catalog. Migration : `LikesPage(offset, limit)` (clés `adresse/plage`), `TippedPage(addr, offset, limit)` (ensemble des morceaux soutenus).
- **store/v0** : `node.kids` devient un slice, nil sur les feuilles (un tableau fixe stockait 32 pointeurs nil typés dans chaque feuille) : une nouvelle feuille de `Map` coûte ~1,5 Ko de dépôt au lieu de ~4,7 Ko. `Slice` supprimé (inutilisé).
- **radio** : le cooldown d'un auditeur est lu dans son enregistrement hebdomadaire de curateur (5ᵉ champ, conservé d'une semaine à l'autre) : `lastQ` supprimé, une écriture de moins par pick ; `lastPick` dimensionné à 65 536 seaux. New et Choice sont des anneaux (voir §2). La grille d'une station garde au plus `maxSchedule` = 120 créneaux (le flow s'arrête là). `mainBase` supprimé (les tests préremplissent les créneaux). Migration : `StatePage(table, offset, limit)` (curators, weekly, muted, strikes, dropped, lastPick, noteReports), `StationState(id)` (epoch, anneau, grille), `FlowState()`, `SetSuccessor` / `Successor()`. `dropped` passe dans un `store.Map`.
- **tickets** : billets en enregistrements `store.Seq`, billets par détenteur en liste triée (`store.Map`), achats par concert et wallet dans un `store.Map` : ~6 Ko de dépôt par billet en régime établi au lieu de ~11 Ko (le reste est le registre GRC721). `RefreshArtist` (voir §4).
- Mesuré (`gno test -print-runtime-metrics`, cycles VM, hors gas d'écriture au stockage que `gno test` ne compte pas) : `Queue` (20 000 picks passés) 9,50 M → 9,48 M, dépôt net du premier pick sur une radio vide 113 Ko → 44 Ko ; `Like` (voisin de chunk d'un auditeur à 5 000 likes) 4,17 M → 3,87 M, et l'écriture ne réécrit plus les 45 Ko de likes du voisin ; achat de billet (2 000 vendus) 4,4 M → 5,2 M cycles, dépôt 11,3 Ko → 6,0 Ko.

### Picks sponsorisés (v0.7)

Un pick d'auditeur coûte des frais (~0,01 GNOT) et un dépôt de stockage (jusqu'à ~0,1 GNOT, rendu par la chaîne à celui dont la transaction libère ce stockage, rarement le picker). Un artiste peut le **rembourser** : c'est un remboursement, pas une écoute payée (au-dessus du coût, des wallets jetables gratuits videraient le budget). Rien n'est payé par GnoRadio.

```go
// catalog (sponsor.gno) — les GNOT restent dans le catalog, comptés exactement
func FundPromo(cur realm)                                // payable (ugnot, IsUserCall), artiste propriétaire vérifié, 0,1..1 000 000 GNOT
func SetPromoPay(cur realm, ugnotPerPick int64, perDay int) // 10 000..50 000 ugnot (0 = pause, 30 000 par défaut), plafond quotidien 0..100 (0 = aucun)
func WithdrawPromo(cur realm, artistID int)              // le financeur seul, part non réservée ; marche artiste masqué, non vérifié, profil repris, realm gelé
func PromoReserve / PromoClaim / PromoRelease            // realm radio seul (cur.Previous().PkgPath() == RadioRealm())
func PromoOffer(artistID int) int64                      // remboursement actuel (0 = aucun) ; ArtistJSON "sponsor"
func PromoJSON(artistID int) string                      // {"artist","funder","balance","reserved","free","pay","perDay","today","funded","paid","picks","offer"}
func PromoPage(offset, limit int) (keys, vals []string)  // migration / audit ; somme des balances == PromoHeld()
// radio (sponsor.gno)
func QueueSponsored(cur realm, stationID, trackID int)   // pick remboursé, sans dédicace ; le pick normal du même titre reste possible
func ClaimPickPayout(cur realm, stationID int, start int64) // le picker, une signature, son gas, une fois le créneau diffusé en entier ; marche realm gelé
func PickPayoutStatus(addr address, stationID int, start int64) string // "ok" | "airing" | "lapsed" (expiré, annulé ou titre retiré) | "none"
func SponsoredJSON(addr address) string                  // {"block":"raison ou vide","open":[{"station","start","track","end","amount","status"}]} ; status = PickPayoutStatus
func OnAirPay(stationID int) int64                       // libellé « sponsored pick » ; ScheduleJSON "sponsored", UpNext Slot.Pay
```

- **Séquestre.** `QueueSponsored` réserve le remboursement dans le budget (il sort du disponible) et garde un enregistrement par wallet et station (un seul ouvert à la fois). `ClaimPickPayout` vérifie l'enregistrement (picker = appelant, même `start`), que la fin prévue est passée, que le titre est encore jouable, puis le catalog paie. Un créneau retiré ou coupé avant sa fin (`Unqueue`, `DropSlot`, `Refresh` d'un titre masqué) supprime l'enregistrement et rend la réservation aussitôt. Un pick retiré avant d'avoir commencé rend aussi, le jour même de sa réservation, les compteurs du jour qu'il avait pris (plafond de l'artiste, 1 par artiste et 3 par jour du wallet). Les réservations sont rangées par jour d'expiration : jour UTC de (`held` + 7 jours), `held` étant la fin prévue à la réservation (`Slot.held`, 5ᵉ champ de `sponsor` : `at` + durée pour un pick réservé, `start` + durée au moment du pick sinon), jamais la fin recalée ; non réclamées, elles reviennent au budget d'elles-mêmes, sans transaction. L'app ne devine pas : `PickPayoutStatus` / `SponsoredJSON` `status`.
- **Comptabilité.** `PromoHeld()` = somme des balances = GNOT du catalog (le catalog ne garde aucune autre pièce : tips et soutien repartent dans la même transaction). `tip` refuse de payer si le solde du realm est inférieur à `PromoHeld + total` : un tip ne peut jamais dépenser les budgets. Aucune fonction admin ne touche les budgets ; `Freeze` n'empêche ni `WithdrawPromo` ni `ClaimPickPayout` (un gel ne fait jamais expirer un remboursement).
- **Changement de propriétaire.** Le budget garde son financeur. Il ne finance de nouveaux picks que si financeur = propriétaire actuel, artiste visible et vérifié. Quand un nouveau propriétaire finance, l'ancien financeur récupère tout son solde (réservations comprises, qui sont alors annulées).
- **Anti-abus.** Le picker n'est ni le propriétaire, ni un collaborateur (`splits`), ni un realm GnoRadio. Réputation : premier pick vieux de 7 jours et 3 picks normaux sur les 30 derniers jours (deux compteurs de 15 jours dans l'enregistrement curateur : la fenêtre réelle va de 15 à 30 jours). Antenne : 1 pick sponsorisé par artiste, station et heure ; temps d'antenne sponsorisé ≤ 1 800 s, un quart des 2 h programmables. Wallet : 1 par artiste et 3 par jour UTC (comptés à la réservation). Artiste : plafond quotidien optionnel. Les règles existantes s'appliquent (1 pick/h/station, pas de rejouer sous 3 h, 2 par artiste à venir). Des wallets d'une même personne peuvent quand même prendre jusqu'aux plafonds : c'est le coût de la promotion, accepté par l'artiste en finançant.
- **Hors classement.** Un pick sponsorisé ne donne aucun point de curateur, n'entre pas dans Listeners' choice, ne déclenche pas l'ingestion ; il garde le cooldown (`markPick`). Libellé partout : app (« Sponsored pick · paid by [artiste] »), gnoweb, `ScheduleJSON` ("sponsored"), activité (`kind:"sponsored"`). `CuratorJSON` expose `"promo"` (remboursements reçus).
- **App.** Pick next : case « Free pick: [artiste] refunds it (0.03 GNOT) », cochée par défaut si disponible, sinon la raison ; ligne de coût honnête (frais + dépôt). Lecteur et Me : bouton « Collect 0.03 GNOT » une fois le pick diffusé. Me (artiste vérifié) : budget, remboursement par pick, ajouter, retirer.
- Gas mesuré (`gno test -print-runtime-metrics`, cycles VM hors écriture au stockage) : `FundPromo` ≈ 2,0 M ; `Queue` ≈ 7,7 M ; `QueueSponsored` ≈ 6,7 M côté radio + `PromoReserve` ≈ 3,3 M ; `ClaimPickPayout` ≈ 2,5 M + `PromoClaim` ≈ 2,3 M ; `WithdrawPromo` ≈ 1,4 M.

### Picks à heure choisie (v0.8)

```go
// radio — at : heure unix UTC, entre maintenant + 15 min et + 24 h ; 0 = dès que possible (= la fonction sans At)
func QueueAt(cur realm, stationID, trackID int, at int64)
func QueueWithNoteAt(cur realm, stationID, trackID int, at int64, note string, expires int64, sigHex string)
func QueueSponsoredAt(cur realm, stationID, trackID int, at int64)
// Queue, QueueWithNote, QueueSponsored appellent ces fonctions avec at = 0 ; Slot.At = heure demandée (0 : pick pour maintenant)
// ScheduleJSON : "at" par entrée et "booked":[{"track","start","end","at","by"}] (tous les picks réservés à venir, quel que soit l'horizon)
```

- **Alignement.** Le pick démarre à la première frontière de morceau à partir de `at` : fin du morceau de rotation en cours à cette heure, ou fin des picks d'auditeurs qui occupent ce moment. Sur Main, à `at` exactement : le titre du flow en cours s'efface (fondu), comme pour un pick normal, et le flow (`lay`) reprend après ; `program`, `ahead` et `NeedsSync` ne comptent que le programme continu depuis maintenant, un pick réservé plus loin ne coupe pas le flow.
- **Il garde son heure.** Un pick pour maintenant (et un nouveau pick réservé) passe avant un pick réservé seulement s'il finit au plus tard à son heure, sinon après lui. Sur une station de genre, ce qui est inséré avant décale la rotation : `realign` recale les picks réservés suivants sur la nouvelle frontière (jamais avant leur heure, au plus un morceau plus tard), ceux qui les suivaient, et un pick pour maintenant qui attendait la fin d'un morceau de rotation après un trou (il attend la nouvelle fin de ce morceau) ; enregistrement sponsorisé et signalements suivent le `start`. Limite connue : `Unqueue`, `DropSlot` et les éditions de rotation ne recalent pas (le morceau de rotation fait une pause autour, comme autour d'un pick qui suit un pick retiré).
- **Règles.** Toutes celles de `Queue` (genre, New, 1 pick en attente par auditeur et station — réservé compris —, cooldown 1 h, 2 par artiste, 30 à venir). Le trou de 3 h se mesure entre heures de diffusion, dans les deux sens, contre les picks de la grille : `at` pour un pick réservé, le début calculé pour un pick pour maintenant (qui peut attendre jusqu'à 2 h derrière d'autres). `lastPick` garde ces heures (pick pour maintenant à sa mise en file, avec son début calculé, mis à jour si `realign` le décale ; pick réservé quand il est replié par `fold`). Le plafond de 2 h d'antenne ne concerne que les picks pour maintenant ; les picks réservés ont le leur : 4 par station et heure UTC. Sponsorisés : mêmes règles, quotas mesurés autour de `at` ; la réservation du catalog expire 7 jours après `at` + durée (`Slot.held`, 5ᵉ champ de `sponsor`).
- **Gas** (cycles VM, `gno test -print-runtime-metrics`, chaque test lancé seul) : station vide `Queue` +10,8 M, `QueueAt` +10,9 M ; station pleine (29 picks dont 14 réservés, tous recalés) `Queue` +18,8 M, `QueueAt` +18,6 M. Borné par les 30 créneaux à venir, indépendant du catalogue.
- **App** (Pick next, étape 2) : « Right away / At a time », heures par quart d'heure sur 24 h à l'heure locale avec le décalage (« 21:00 · GMT+2 »), envoyées en UTC ; les heures pleines sont grisées ; « 21:00 · booked » ; « On air at 21:00 your time ». gnoweb : le pick réservé apparaît dans Up next avec son heure (« booked by »).

