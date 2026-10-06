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

Un artiste curé ou Audius qui **réclame** son profil (preuve hors chaîne, validation admin) récupère ses morceaux : tips et concerts activés.

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
| Synchronisation permissionless du catalogue vers les stations (`Sync`, `Prune`) | 0.3 |
| `ScheduleJSON(station)` pour la dApp | 0.3 |
| Stations éditoriales basées sur une playlist, émissions à heure fixe, jingles | 0.4+ |
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

### dApp (Next.js)
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
gno.land/p/gnoradio/art/v0        dessin SVG (pochette, billet, badge…)    — pur
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
Stockage en **blocs de 128 créneaux** + un tableau des sommes par bloc :

- trouver le créneau à la position `p` de la boucle : parcourir les sommes de blocs puis un bloc → O(n/128 + 128) ;
- ajouter en fin : O(1) ;
- retirer : la durée du créneau passe à 0 (un bloc + une somme réécrits) ;
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
const NumGenres = 12                                  // genres 1..12, 0 = invalide
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
func Prune(cur realm, trackID int)   // permissionless : retire un morceau devenu injouable
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
func DropSlot(cur realm, stationID, trackID int) // admin : coupe le créneau de rotation (durée 0) et retire le titre de la file
func Unqueue(cur realm, stationID, trackID int)  // admin : retire le titre de la file d'attente
```

- Noms d'artiste : lettres ASCII + accents Latin-1 (À–ÿ hors × ÷), chiffres, espace, `. ' - &` ; réservés sous un squelette (minuscules, accents retirés, pleine chasse → ASCII). Renommer libère l'ancien nom ; un artiste masqué ne peut pas renommer.
- `SetTreasury` refuse l'adresse du catalogue et celles des realms radio, tickets et home. `Like` n'ajoute pas deux fois la même adresse aux badges « early ».
- Radio : un changement de genre met à jour toutes les stations (créneau orphelin à 0) ; un titre non jouable n'est jamais diffusé (`NowPlaying`, `ScheduleJSON`). `Queue` : un titre par station et par heure et par wallet ; ≤ 7 200 s de programmation d'auditeurs à venir par station (`CuratorQueue` exempté).
- Tickets : index `upcoming` trié par date (ajout à la création, retrait à l'annulation ou au masquage) ; `Upcoming` et `EventsJSON(upcoming=true)` le lisent (le plus proche d'abord) ; ≤ 10 concerts futurs non annulés par artiste.

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

Genres (liste fixe, `genre` = indice) : 1 Electronic · 2 Synthwave · 3 Ambient · 4 Techno & House · 5 Lo-fi & Chill · 6 Hip-hop & Beats · 7 Rock & Indie · 8 Pop · 9 Jazz & Soul · 10 Folk & Acoustic · 11 Cinematic & Classical · 12 World.

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
