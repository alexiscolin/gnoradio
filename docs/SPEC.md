# GnoRadio: specification v0.3

> A music player **and** a community radio, on-chain on gno.land.
> The interface is in **English**. Admin = the project owner's personal address.
> Nothing is deployed on a public network before it passes review on a local devnet.
> This describes the v0 realms that ship today. A v1 that keeps the data apart from the rules is in progress: [ARCHITECTURE-v1.md](ARCHITECTURE-v1.md).

## 1. Product

Two ways to listen, in the same player:

- **Library** (on demand): albums, playlists, tracks, in any order you like. Playback is 100% in the app, no transaction.
- **Live** (radio): **stations** (one main station + one per genre). Everyone hears the same thing at the same second, from an on-chain schedule.

Tracks come from three origins, mixed in the same genres, albums, playlists and stations:

| | Artist track | Curated CC track | Audius track |
|---|---|---|---|
| Published by | the artist (their wallet) | the admin (curated import) | the admin (selection) |
| Legal basis | the artist's statement | CC0 / CC BY / CC BY-SA | Audius Open Music License §1.2 (streaming and public performance granted to players) |
| Audio | `ipfs://`, `ar://`, `https://` + sha256 | source link + sha256, copy allowed | `audius:<trackId>`, played through the API, **session cache only** |
| Attribution | artist | artist, license, source | artist, ©, OML notice, Audius link (§1.5) |
| Tips | yes, to the artist + collaborators (minus the promo share the artist chose, see Listener rewards), once verified | no, "Claim this profile" | no, "Support on Audius" + "Claim this profile" |
| Concerts, tickets | yes | after a claim | after a claim |

A curated or Audius artist who **claims** their profile (a code on a page they control, checked by a robot that signs a certificate; 72 h public wait) gets their tracks back: tips and concerts are turned on.

## 2. Features, by module and by phase

Status: **0.3** = this work · **dApp** = app side · **0.4+** = later · **✕** = dropped.

### Catalog (`r/gnoradio/catalog`)
| Feature | Phase |
|---|---|
| Artist profiles (Latin name against impersonation, short bio, verified) | 0.3 |
| Unclaimed curated artists + claim (`AssignArtist`) | 0.3 |
| Tracks: title, genre (fixed list), duration, SPDX license, credits, `audio` + `cover` (URI + sha256), source + attribution | 0.3 |
| Allowed hosts (`https`), managed by the admin; `ipfs://`, `ar://`, `audius:` | 0.3 |
| Fixing a track (`EditTrack`), "broken link" report | 0.3 |
| Albums / EPs | 0.3 |
| Public playlists (published in one signature) | 0.3 |
| Likes, Follow (stored per user), first listener badges | 0.3 |
| Split tips (0% commission), incremental top 10 | 0.3 |
| Reports, hiding (track, album, artist), freeze, successor | 0.3 |
| Paginated JSON exports | 0.3 |
| Change splits with the collaborators' consent | 0.4+ |
| Lyrics (linked file) | 0.4+ |
| Comments | 0.4+ |
| Jamendo-style commercial licenses | ✕ |

### Radio (`r/gnoradio/radio`)
| Feature | Phase |
|---|---|
| Stations: main + one per genre | 0.3 |
| Rotation per station, scalable structure (§4.2), stable when tracks are added or removed | 0.3 |
| Programming by listeners: starts when the current track ends; quotas | 0.3 |
| Pick at a chosen time (`QueueAt`, 15 min to 24 h, 4 per hour, see v0.8) | 0.8 |
| Permissionless sync from the catalog to the stations (`Sync`, `Refresh`, `RefreshArtist`) | 0.3 |
| `ScheduleJSON(station)` for the dApp | 0.3 |
| Main flows like a real radio: sets of 3 to 5 tracks of one genre, transition to a nearby genre along an energy line, a daily clock (calm at night, energy in the evening), never the same artist twice in a row; `Sync` writes the next hour, called every 30 min by the robot (`app/netlify/functions/sync.mts`) | 0.5 |
| Station jingles (in the app, on tune-in and at the top of the hour) | dApp |
| Editorial stations based on a playlist, shows at fixed times | 0.4+ |
| "New this week" (`NumGenres+1`, the last 300 tracks added) and "Listeners' choice" (`NumGenres+2`, the last 500 distinct tracks picked by listeners through `Queue`/`QueueWithNote`, plus the top likes at each `Sync`) stations: fixed-size ring, once full the oldest slot is reused in place (its track leaves `homes`), the rotation stops growing, constant cost; can be programmed like any station, with no genre check | 0.5 |
| Slot auctions | ✕ (commercial radio) |

### Concerts and tickets (`r/gnoradio/tickets`)
| Feature | Phase |
|---|---|
| Concerts, GRC721 tickets drawn on-chain, 100% of the price to the artist | 0.3 (carried over from 0.2) |
| "I was there" check-in, cancellation, ticket gift | 0.3 |
| `TokenURI`, tickets per holder | 0.3 |
| Resale royalties | ✕ |

### gnoweb site (`r/gnoradio/home`)
| Feature | Phase |
|---|---|
| All pages in English, reads the 3 other realms | 0.3 |
| Generated SVG covers (when there is no `cover`) | 0.3 |
| Stations, catalog, albums, playlists, artists, concerts, charts, moderation | 0.3 |

### dApp (Vite + React)
| Feature | Phase |
|---|---|
| Library + Live player, shuffle (albums), track order (mix of the day, most liked, most tipped, newest) | dApp |
| Save (local, free) vs Like (on-chain, public), both under Your library | dApp |
| sha256 of a local audio or cover file (no upload: the artist hosts the file) | dApp |
| Search over the catalog loaded from the exports | dApp |
| Catalog cache in the browser (IndexedDB), only what changed is read again | dApp |
| Session keys (fewer Adena popups, daily spending cap) | dApp |
| Sharing with `?ref=` | dApp |
| Concerts: search, this week / this month, free, city and day filters; a QR per ticket that opens a door page for check-in | dApp |
| Audio upload, repeat, volume normalization, embeddable player | 0.4+ |

## 3. Where each piece of data lives

| Level | Content |
|---|---|
| **On-chain** | what proves, pays or commits: identities, records, links + hashes, licenses, splits, tips, albums, public playlists, likes, follows, stations, schedules, tickets, moderation |
| **Computed** | default SVG covers, badges, drawn tickets, counters |
| **External storage** (link + sha256) | audio, covers, lyrics, long bio |
| **App only** | plays, history, Library queue, Save, private playlists, search, listener count |

Listening never costs anything and never goes through the chain.

## 4. On-chain architecture

```
gno.land/p/gnoradio/blocks/v0     sum of durations in blocks (rotation)    (pure, tested)
gno.land/p/gnoradio/svg/v0        SVG drawing (cover, ticket, graphs)      (pure)
gno.land/p/gnoradio/text/v0       text helpers (keys, JSON, GNOT)          (pure)
gno.land/p/gnoradio/store/v0      compact encodings (records, buckets)     (pure)
gno.land/p/gnoradio/safe/v0       dedication filter                        (pure)
gno.land/r/gnoradio/catalog/v0    artists, tracks, albums, playlists, likes, follows, tips
gno.land/r/gnoradio/radio/v0      stations, rotations, programming         (reads catalog)
gno.land/r/gnoradio/tickets/v0    concerts, GRC721 tickets                 (reads catalog)
gno.land/r/gnoradio/home/v0       gnoweb site + Info()                     (reads everything)
```

Also in the tree, for v1 and not used by the v0 realms: `p/gnoradio/role/v0`, `r/gnoradio/data` and the `catalog/v1` being written ([ARCHITECTURE-v1.md](ARCHITECTURE-v1.md)).

One-way dependencies: `radio`, `tickets`, `home` import `catalog`; `catalog` imports no realm.
Realms talk to each other through **ids** and getters that return **values** (never pointers).
Each realm has its own `admin` (set to the deployer, then `TransferAdmin`).
On a public chain the packages go under the deployer's namespace ([DEPLOY.md](DEPLOY.md)).

### 4.1 Scaling rules

1. No loop over "all" tracks, artists or users in a write or in a page: `avl.Tree`, pagination, caps.
2. An action costs the same gas with 100 or 100,000 tracks: checked by **load tests** (budgets §6).
3. No big global slice: lists that grow are trees or blocks.
4. A user's data is stored under their own entry (likes, follows, playlists); a like does not rewrite a giant shared object.
5. Charts = top 10 updated on write.
6. Spam costs its author (storage deposit) + per-account limits.

### 4.2 Scalable radio rotation (`p/gnoradio/blocks`)

Each station has an ordered list of slots (a track, a duration).
Stored in **blocks of 128 slots**, grouped by 128 blocks (one group = 16,384 slots, with the sum of each block) + an array of totals per group:

- find the slot at position `p` in the loop: walk the group totals, the sums of one group, then one block → O(n/16,384 + 128 + 128);
- append at the end: O(1);
- remove: the slot's duration becomes 0; a write rewrites one block, one group (128 references and sums) and the group arrays (one entry per 16,384 slots), never an array of all blocks: flat cost up to ~2 M slots;
- `Set(i, id, dur)` reuses a slot (New and Choice rings);
- the time anchor is adjusted so nobody skips a track.

Position in the loop at time `t`: `(t − epoch − paused(t)) mod total`, where `paused` = time taken by programmed tracks.

### 4.3 Main API (excerpts)

```go
// catalog
func RegisterArtist(cur realm, name, bio string) int
func CreateArtist(cur realm, kind, name, bio, source string) int              // admin, unclaimed curated or Audius artist
func AssignArtist(cur realm, artistID int, owner address)                      // admin, claim
func PublishTrack(cur realm, title string, genre int, duration, license, cmo, credits, audio, audioSHA, cover, coverSHA, splits, rights string) int
func ImportTrack(cur realm, artistID int, title string, genre int, duration, license, credits, audio, audioSHA, cover, coverSHA, sourceURL, attribution string) int // admin
func EditTrack(cur realm, id int, ...)
func CreateAlbum(cur realm, artistID int, title, cover, coverSHA string, year int, trackIDs string) int
func PublishPlaylist(cur realm, title, trackIDs string) int
func Like(cur realm, trackID int)
func Follow(cur realm, artistID int)
func Tip(cur realm, trackID int)                     // payable
func Report(cur realm, kind string, target int, reason string)
func AllowHost(cur realm, host string, allowed bool) // admin
// getters for the other realms (values only): CONTRACT FROZEN v0.3
const NumGenres = 20                                  // genres 1..20, 0 = invalid
func GenreName(g int) string                           // "" if out of range
func TrackCount() int                                  // ids 1..TrackCount()
func TrackBrief(id int) (artistID, genre int, duration int64, playable bool) // playable=false if unknown, hidden, artist hidden
func TrackTitle(id int) string
func ArtistCount() int                                 // ids 1..ArtistCount()
func ArtistName(artistID int) string
func ArtistOwner(artistID int) address                 // address("") if unclaimed (curated / Audius)
func ArtistOf(owner address) int                       // 0 if no profile
func ArtistVisible(artistID int) bool

// radio
func Sync(cur realm, max int) int    // permissionless: adds the catalog's new tracks
func RefreshArtist(cur realm, artistID, offset int) int // permissionless: refreshes 50 tracks of an artist, returns the next offset (0 = done)
func Queue(cur realm, station, trackID int)
func NowPlaying(station int) (trackID int, offset int64, queued bool)
func ScheduleJSON(station, horizon int) string
```

### 4.4 Funding GnoRadio and activity (v0.3.1)

The artist always keeps 100%; GnoRadio's share is added on top, visibly, and goes to an on-chain treasury.

```go
// catalog
func SupportGnoRadio(cur realm)                                   // payable, 0.1..1,000,000 GNOT → treasury
func TipWithSupport(cur realm, trackID int, supportPct int)       // payable, supportPct 0..50; artist = T*100/(100+pct), rest → treasury; Tip = pct 0
func SetTreasury(cur realm, to address)                           // admin
func SetMonthlyGoal(cur realm, ugnot int64)                       // admin
func Treasury() address
func SupportJSON() string   // {"treasury","total","supporters","month":"YYYY-MM","monthTotal","goal","top":[{"address","amount"}]}
func ActivityJSON(limit int) string // ≤64, newest first: [{"kind","by","track","artist","amount","at"}]
                                    // kind: publish | like | follow | tip | support | playlist | album | claim
// radio
func CuratorQueue(cur realm, stationID, trackID int)              // radio admin: no quotas (duplicate, genre, 30 max kept)
func ActivityJSON(limit int) string // ≤64: [{"kind":"queue"|"curator","by","track","station","start","at"}]
// tickets
func SetServiceFee(cur realm, ugnot int64)                        // admin, 0..10 GNOT; paid tickets: price + exact fee
func ServiceFee() int64
func FeesJSON() string      // {"serviceFee","treasury"}; EventsJSON adds "fee"
```

Activity feeds are fixed-size rings of 64 entries: storage does not grow.

**Safeguards (security audit, v0.3.2)**: additions only, no existing signature changed:

```go
// catalog
func ResolveReport(cur realm, id int)        // admin: closes a report; ≤5 open per reporter, maxReports = OPEN reports
func ReleaseName(cur realm, name string)     // admin: frees a reserved name that no visible artist uses
// radio
func DropSlot(cur realm, stationID, trackID int) // admin: cuts the rotation slot (duration 0, kept despite Refresh) and removes the track from the queue
func RestoreSlot(cur realm, stationID, trackID int) // admin: undoes DropSlot
func Unqueue(cur realm, stationID, trackID int)  // admin: removes the track from the queue
```

- Artist names: ASCII letters + Latin-1 accented letters (À–ÿ except × ÷), digits, space, `. ' - &`; reserved under a skeleton (lowercase, accents removed, full width → ASCII). Renaming frees the old name; a hidden artist cannot rename.
- `SetTreasury` refuses the catalog's address and those of the radio, tickets and home realms. `Like` does not add the same address twice to the "early" badges.
- Radio: a genre change updates all stations (orphan slot set to 0); a track that is not playable is never aired (`NowPlaying`, `ScheduleJSON`). `Queue`: one track per station per hour per wallet; ≤ 7,200 s of upcoming listener programming per station (`CuratorQueue` exempt).
- Tickets: an `upcoming` index sorted by date (added on creation, removed on cancellation or hiding); `Upcoming` and `EventsJSON(upcoming=true)` read it (nearest first); ≤ 10 upcoming non-cancelled concerts per artist. `RefreshArtist(artistID)` (open to all) rereads the artist's visibility in the catalog: concerts of a hidden artist leave the index (hidden spam no longer takes up the 1,000-entry scan), those of a restored artist come back.

## 5. Launch catalog (~1,200 tracks)

**Quality comes from an allowlist, never from an open search.** Internet Archive is used as a stable **host** for chosen artists and labels, not as a discovery source.

| Source | Tracks | Stations | Hosting |
|---|---|---|---|
| **Audius**: allowlist of artists and labels we listened to (no unauthorized remixes) | ~400 | all genres, mostly electronic, hip-hop, house, lo-fi | Audius (played through the API, no copy) |
| Reference artists (Scott Buckley, Komiku, Monplaisir, Josh Woodward, Jahzzar, Chris Zabriskie, Kevin MacLeod under BY, Rolemusic…) | ~300 | cinematic, chill, pop, jazz, folk, electronic | archive.org or the artist's site |
| ccMixter, editorial selections (CC BY) | ~150 | hip-hop, beats, downtempo | IPFS/CDN **copy** (anti-hotlink) |
| ~15 netlabels listened to and approved | ~200 | techno, house, synthwave, ambient | archive.org |
| Ziklibrenbib, Dogmazic (hand-picked) | ~150 | rock, indie, world, French scene | depends on the source |

Excluded: FMA (direct links forbidden), SoundCloud (radio and aggregation forbidden), Jamendo (commercial license likely, to be asked), NC/ND licenses (caution, to be reviewed with legal advice).

Audius (terms read on 2026-10-06, versions of 2 July 2025): OML §1.2 grants "Music Players" the right to stream and to perform publicly; the API forbids persistent caching, bulk extraction and AI training. We store the Audius id and the attribution; title and cover are read live by the dApp. API key to request (api.audius.co/plans).

Pipeline (`tools/curate`): allowlist → metadata (archive.org / ccMixter API) → filters (license, duration 1:30–10:00, bitrate ≥ 128 kbps and flagged under 192, cover, complete metadata) → normalization (genre, artist, SPDX license) → sha256 and LUFS computation → listening screen keep / drop → import file → `ImportTrack` in batches.

Genres (fixed list, `genre` = index): 1 Electronica · 2 Synthwave · 3 Ambient · 4 Techno · 5 House · 6 Drum & Bass · 7 Dubstep & Trap · 8 Lo-fi Beats · 9 Hip-hop & Rap · 10 R&B & Soul · 11 Rock & Indie · 12 Metal & Punk · 13 Pop · 14 Jazz & Blues · 15 Folk & Acoustic · 16 Cinematic & Classical · 17 World · 18 Latin · 19 Reggae & Dub · 20 Funk & Disco.

## 6. Budgets (targets)

The gas tests (`TestScaleSmall` / `TestScaleLarge`, `TestScale*` in radio, `gas_test.gno`) print the figures to compare; they do not assert these numbers.

| Action | Max gas | Independent of volume |
|---|---|---|
| PublishTrack / ImportTrack | 25 M | yes |
| Like, Follow, Tip | 15 M | yes |
| Queue | 20 M | yes (queue ≤ 30) |
| NowPlaying / rotation (100,000 slots) | 60 M | ~O(n/128) |
| Heaviest gnoweb page | 400 M (budget 3 B) | yes |

## 7. Decisions

| Topic | Decision |
|---|---|
| Language | English |
| Admin | personal address (no multisig) |
| Deployment | local devnet until review; onyx on explicit request |
| Front | sober "Swiss" style (design canvas) |
| Programming | free with quotas (open) |
| Reward for beta artists | open |

### Review v0.4.1 (reading and gnoweb)

- catalog: `GenrePage(genre, offset, limit)`, `GenreCount(genre)` (index per genre), `FollowsPage(addr, offset, limit)`, `SupportInfo()`, `AudiusLicense` exported; `ReportCount()` now counts **open** reports. `Unlike`, `Unfollow` and `Report` respect `Freeze`. Artist names are reserved under a skeleton with no spaces or punctuation, with confusables folded (i/l/1, 0/o, rn/m); double spaces are refused.
- radio: `Prune` removed (duplicate of `Refresh`); `RefreshArtist`, `RestoreSlot`.
- tickets: a ticket for a hidden concert no longer shows title, venue or artist; `CheckIn` refuses a cancelled concert; `&` accepted.
- JSON: validated fields (text, names, URLs, hashes, licenses, addresses) are written with `text.Str()` without escaping, because escaping costs ~1 M gas per field (`TracksJSON(0,50)` went from ~96 M to ~300 M); tests check that the validators refuse `"`, `\` and control characters.
- home: `SetAppURL(cur, url)` (catalog admin, https, 100 characters max) and "Open in the app" links; buy link = price + service fee; CC licenses of all versions/ports; `catalog?g=N`, pagination (artist, playlist, listener, past concerts, moderation); GnoRadio support, activity feed, `$source` links; each realm has a `Render` that links to home.

### Review v0.4.2 (gas and deposit)

- **Who pays for `Sync`:** `Sync` is open to all and the storage deposit is paid by the caller, about 0.1 to 0.2 KB per track since v0.4.4 (≈ 0.02 GNOT; a batch of 200 ≈ 4 GNOT). In practice the admin (Studio, batches of 20) runs it after a wave of imports; an artist can also run it to go on air without waiting. The main station no longer keeps an index (track `id` is at slot `id-1`) and a `homes` index (track → genre stations) limits `Refresh`/`RefreshArtist` to the stations that hold the track.
- `PublishPlaylist` / `UpdatePlaylist` now only check the id range and duplicates (≈ 4× less gas for 200 tracks); hidden tracks are filtered on read.
- `EventsJSON(offset, limit, false)` jumps straight to `offset` (offset and limit count stored concerts, hidden ones included) and returns `"next"`.
- tickets: `ownedCount` removed (written, never read).
- catalog: `LikedPage` returns the newest tracks first; narrow getters `PlaylistBrief`, `ArtistTrackCount`, `ArtistTrackPage`; migration pages `UsersPage`, `SupportersPage`; radio: `RotationPage(station, offset, limit)`.

### Review v0.4.4 (compact storage deposit)

- New package `p/gnoradio/store/v0`, deployed before the realms (after `text`): `Seq` (list in chunks of 16 records), `Map` (hash table with fixed buckets), compact records (`Rec`/`Field`/`With`, length header in base 64), id lists ready for JSON (8 characters + comma), `IDs` (sorted set in chunks of 512).
- catalog: tracks, artists, albums, playlists and listeners are compact strings in `Seq`s; indexes by owner / name / listener in `Map`s; `Like`/`Unlike` rewrite a single field without decoding the track.
- radio: rotation blocks as strings (4 base 64 characters per id, 2 per duration: id ≤ 16,777,215, duration ≤ 4095 s); `homes` and `lastQ` compact.
- Measured on gnodev (devseed, 116 tracks), deposit per operation: imported track ≈ 6.1 KB → 0.31 KB; published track ≈ 6.4 KB → 0.28 KB; `Sync` ≈ 4.2 KB → 0.08–0.22 KB per track; next like ≈ 2.5 KB → 0.1 KB. Cheaper reads (`TracksJSON(0,100)` 181 M → 122 M gas).
- Visible changes: `UsersPage` follows bucket order (stable, not sorted); id arrays in JSON contain spaces (same values); a listener's like list caps at ~29,000; higher initial realm deposit (empty buckets).

### Review v0.4.3 (simplification)

- Shared packages: `p/gnoradio/svg/v0` (SVG canvas, `Escape`, `Clip`, `FNV`) and `p/gnoradio/text/v0` (`Key`, `Str`, `Valid`, `Digits`, `GNOT`), deployed before the realms; SVG output identical byte for byte ("golden" tests).
- API removed: `catalog.HasLiked`, `catalog.IsFollowing` (replaced by `LikedPage` / `FollowsPage` / `UserJSON`) and `home.AppURL` (link readable in the render).

### Review v0.5 (verification, storage, flow)

- **Artist verification with no human** (`catalog/verify.gno`, `docs/VERIFICATION.md`): tips and paid tickets are only for verified artists; proof on a page of the artist's, read by a robot with a limited role, 72 h public delay, `CancelClaim` / `ResetOwner` for the admin; no escrow.
- **Tree storage** (`store/v0`): `Seq`, `Map` and `IDs` sit on a sparse tree with fanout 32 and counters. A write rewrites one leaf and one path (log32 of the number of leaves: 3 levels for 32,000 leaves) instead of the array of all tracks or buckets, which made gas grow with the catalog. Pages at any offset (`Keys`, `IDs.Page`) go down through the counters. Sparse `Map` buckets: sized for 1 M listeners at no cost while they are empty.
- `updateTop` no longer rewrites the chart when it does not change.
- **Main flow** (`radio/flow.gno`): see §2 Radio.
- **Dedications** (`radio.QueueWithNote`, `p/gnoradio/safe/v0`): a pick can carry a 40-character dedication shown on air. Filtering with no human: simple characters, no link or phone number, a multilingual list (LDNOOBW en/fr/es/de/it/pt/nl, CC BY 4.0, strong keywords from gnolang/gno#5178, added insults and hate terms), after normalization (accents, leet, repeated or spaced letters). `ReportNote`: three distinct reports (from listeners who have already made a pick) hide the dedication at once; a first hidden dedication is a warning (strike), a second within 7 days (`muteFor`) suspends the author's dedications for 7 days. `RestoreNote` (admin) only applies to a hidden dedication and removes the strike it gave. To be replaced by `p/gnoland/antispam` when gnolang/gno#5178 is deployed.
- **Pick priority**: a pick takes the flow's place on air right away (fade in the app) and replaces its next track; after a listener pick in progress, it goes next.
- **Dedication moderation before the transaction, with no human, free for GnoRadio**: (1) the app sends the text to the robot (`app/netlify/functions/dedication.mts`), which applies the on-chain filter `p/gnoradio/safe` (≈2,000 words and phrases, 20 languages, workarounds) then OpenAI's moderation model (free, multilingual, context-aware, thresholds in `app/src/lib/moderation.ts`); if it passes, the robot signs `radio.NoteMessage(author, station, note, expires)` (Ed25519, 10 min; the realm accepts at most 15); (2) the listener sends `QueueWithNote` with this certificate and pays their gas; the realm checks `safe.Note` and the signature again, refuses otherwise, and the dedication shows at once; with no key or if OpenAI is down, dedications are paused, a pick without a dedication works; (3) three reports (from listeners who have already made a pick) hide it; a second hidden dedication within 7 days turns off the author's dedications for 7 days. The admin can `RestoreNote`, `Unmute`, `SetModBot("")` (turns dedications off). Hidden on the chain = hidden everywhere (app and gnoweb).


### Listener rewards (v0.6)

Picking and sharing pay off, paid by the tippers, never by GnoRadio (everyone pays their own gas).

```go
// catalog (promo.gno)
func SetPromoShare(cur realm, pct int)   // owning artist: 0..20%, 5% by default; ArtistJSON exposes "promo"
func PromoShare(artistID int) int
func RadioTip(cur realm, trackID, supportPct int, tipper, picker, ref address, total int64) (toPicker, toRef int64)
                                         // callable only by the designated radio realm (cur.Previous().PkgPath() == RadioRealm())
func SetRadioRealm(cur realm, pkgPath string) // admin: radio v1 without a new catalog; adds it to the sibling realms
func SetSibling(cur realm, pkgPath string, on bool) // admin: GnoRadio realms (v0 and later) are never treasury, referrer or collaborator
// radio (curators.gno)
func TipOnAir(cur realm, stationID, trackID, supportPct int, ref address) // payable, IsUserCall
func CuratorOf(addr address) Curator     // picks, tips received on air, earnings (ugnot), all time
func TopCurators(stationID int) []Curator // top 10 of the week (Monday 00:00 UTC), -1 = all stations
func CuratorJSON(addr address) string     // {"address","picks","tips","earned","week":{"picks","tips","earned","rank"}}
func TopCuratorsJSON(stationID int) string // {"station","since","top":[{"address","picks","tips","earned"}]}
```

- **Curator share, checked on-chain.** `TipOnAir` receives the tip (`OriginSend`, ugnot only), looks up itself in its schedule the listener pick of `trackID` on air on the station (or ended less than 2 min ago), never a picker given by the client, sends everything to the catalog, then calls `RadioTip`. The catalog pays like `TipWithSupport` (verified artist, not their own track, bounds, treasury) and takes the artist's promo share out of the artist's part: to the picker, or half to the picker (odd ugnot to the picker) / half to `ref`. No share for the tipper, the artist, a GnoRadio realm, nor for picks by the radio admin (`CuratorQueue`). The total never goes above the percentage the artist accepted; any panic reverts the whole transaction. Direct `Tip`/`TipWithSupport`: no share.
- **Share link.** `?ref=<g1…>` is kept for the app session; a tip from that session goes through `TipOnAir` with `ref`.
- **Curator status.** Each listener pick (`Queue`, `QueueWithNote`) and each shared tip updates in O(1) the address's counters and the weekly top 10 of the station and of all stations (1 point per pick, 1 per tip received on air). gnoweb: a "Top curators this week" block on the station page.
- **App.** Player: a red "Your pick · on air" state (title, dial) and a browser notification if allowed (asked on the first pick, never on load), then the result at the end: likes and tips earned during the airing (catalog counts before/after) and the picker's earnings; no listener count (not on-chain). Pick next: selection then a "Push on air" button, earnings shown, sharing with `ref`, tracks played in the last 3 h greyed out. Tip sheet: exact split (artist, collaborators, picker, referrer, treasury), +10% GnoRadio unchecked by default, "A gift, not a purchase". Me: picks, earnings, rank of the week; promo share setting for the artist. Community: top curators of the week.
- Measured gas (`gno test -print-runtime-metrics`, VM cycles without storage): `Queue` ≈ 4.8 M → 6.8 M; `TipWithSupport` ≈ 3.3 M → 3.4 M; `TipOnAir` ≈ 7.2 M (3.5 M on the radio side + 3.7 M `RadioTip` with picker and referrer).

### Review v0.6.1 (security, gas, migration)

- **Verification**: no more global cap of 50 claims per day (a single person could use it up every day). `SetBot` (changing or revoking the robot's key) cancels at once all pending claims signed by the old key: `FinalizeClaim` refuses them, `ClaimJSON` no longer shows them; the artist claims again with a new certificate.
- **Configurable sibling realms**: `SetRadioRealm(path)` (the realm allowed to call `RadioTip`, added to the siblings), `SetSibling(path, on)`, `RadioRealm()`, `SiblingRealms()`. A collaborator (`splits`) can no longer be a GnoRadio realm (the shares would be stuck there). The catalog path used by radio stays the one it imports (`radio` v1 will import the catalog it pays).
- **Likes**: stored separately, by range of 512 track ids (`likeSets`, key `address/range`); a like rewrites at most a 4.6 KB list and no longer touches the listener's record, nor those of their chunk neighbours; no more ~29,000 cap. `LikedPage` and the count in `UserStats` read one entry per 512 tracks of the catalog. Migration: `LikesPage(offset, limit)` (`address/range` keys), `TippedPage(addr, offset, limit)` (set of supported tracks).
- **store/v0**: `node.kids` becomes a slice, nil on leaves (a fixed array stored 32 typed nil pointers in each leaf): a new `Map` leaf costs ~1.5 KB of deposit instead of ~4.7 KB. `Slice` removed (unused).
- **radio**: a listener's cooldown is read from their weekly curator record (5th field, kept from one week to the next): `lastQ` removed, one write less per pick; `lastPick` sized at 65,536 buckets. New and Choice are rings (see §2). A station's schedule keeps at most `maxSchedule` = 120 slots (the flow stops there). `mainBase` removed (tests prefill the slots). Migration: `StatePage(table, offset, limit)` (curators, weekly, muted, strikes, dropped, lastPick, noteReports), `StationState(id)` (epoch, ring, schedule), `FlowState()`, `SetSuccessor` / `Successor()`. `dropped` moves into a `store.Map`.
- **tickets**: tickets as `store.Seq` records, tickets per holder as a sorted list (`store.Map`), purchases per concert and wallet in a `store.Map`: ~6 KB of deposit per ticket in steady state instead of ~11 KB (the rest is the GRC721 registry). `RefreshArtist` (see §4).
- Measured (`gno test -print-runtime-metrics`, VM cycles, without the storage write gas that `gno test` does not count): `Queue` (20,000 past picks) 9.50 M → 9.48 M, net deposit of the first pick on an empty radio 113 KB → 44 KB; `Like` (chunk neighbour of a listener with 5,000 likes) 4.17 M → 3.87 M, and the write no longer rewrites the neighbour's 45 KB of likes; ticket purchase (2,000 sold) 4.4 M → 5.2 M cycles, deposit 11.3 KB → 6.0 KB.

### Sponsored picks (v0.7)

A listener pick costs a fee (~0.01 GNOT) and a storage deposit (up to ~0.1 GNOT, returned by the chain to whoever's transaction frees that storage, rarely the picker). An artist can **refund** it: it is a refund, not a paid play (above the cost, free throwaway wallets would drain the budget). Nothing is paid by GnoRadio.

```go
// catalog (sponsor.gno): the GNOT stay in the catalog, counted exactly
func FundPromo(cur realm)                                // payable (ugnot, IsUserCall), verified owning artist, 0.1..1,000,000 GNOT
func SetPromoPay(cur realm, ugnotPerPick int64, perDay int) // 10,000..50,000 ugnot (0 = pause, 30,000 by default), daily cap 0..100 (0 = none)
func WithdrawPromo(cur realm, artistID int)              // the funder only, unreserved part; works with artist hidden, not verified, profile taken over, realm frozen
func PromoReserve / PromoClaim / PromoRelease            // radio realm only (cur.Previous().PkgPath() == RadioRealm())
func PromoOffer(artistID int) int64                      // current refund (0 = none); ArtistJSON "sponsor"
func PromoJSON(artistID int) string                      // {"artist","funder","balance","reserved","free","pay","perDay","today","funded","paid","picks","offer"}
func PromoPage(offset, limit int) (keys, vals []string)  // migration / audit; sum of balances == PromoHeld()
// radio (sponsor.gno)
func QueueSponsored(cur realm, stationID, trackID int)   // refunded pick, no dedication; a normal pick of the same track is still possible
func ClaimPickPayout(cur realm, stationID int, start int64) // the picker, one signature, their gas, once the slot has fully aired; works with realm frozen
func PickPayoutStatus(addr address, stationID int, start int64) string // "ok" | "airing" | "lapsed" (expired, cancelled or track removed) | "none"
func SponsoredJSON(addr address) string                  // {"block":"reason or empty","open":[{"station","start","track","end","amount","status"}]}; status = PickPayoutStatus
func OnAirPay(stationID int) int64                       // label "sponsored pick"; ScheduleJSON "sponsored", UpNext Slot.Pay
```

- **Escrow.** `QueueSponsored` reserves the refund in the budget (it leaves the available amount) and keeps a record per wallet and station (only one open at a time). `ClaimPickPayout` checks the record (picker = caller, same `start`), that the planned end has passed, that the track is still playable, then the catalog pays. A slot removed or cut before its end (`Unqueue`, `DropSlot`, `Refresh` of a hidden track) deletes the record and returns the reservation at once. A pick removed before it started also gives back, on the same day as its reservation, the daily counters it had taken (artist cap, 1 per artist and 3 per day for the wallet). Reservations are stored by expiry day: UTC day of (`held` + 7 days), `held` being the planned end at reservation time (`Slot.held`, 5th field of `sponsor`: `at` + duration for a booked pick, `start` + duration at pick time otherwise), never the re-timed end; if unclaimed, they go back to the budget on their own, with no transaction. The app does not guess: `PickPayoutStatus` / `SponsoredJSON` `status`.
- **Accounting.** `PromoHeld()` = sum of balances = the catalog's GNOT (the catalog keeps no other coin: tips and support go out in the same transaction). `tip` refuses to pay if the realm's balance is below `PromoHeld + total`: a tip can never spend the budgets. No admin function touches the budgets; `Freeze` blocks neither `WithdrawPromo` nor `ClaimPickPayout` (a freeze never makes a refund expire).
- **Owner change.** The budget keeps its funder. It only funds new picks if funder = current owner, artist visible and verified. When a new owner funds, the old funder gets their whole balance back (reservations included, which are then cancelled).
- **Anti-abuse.** The picker is not the owner, not a collaborator (`splits`), not a GnoRadio realm. Reputation: first pick at least 7 days old and 3 normal picks in the last 30 days (two 15-day counters in the curator record: the real window is 15 to 30 days). On air: 1 sponsored pick per artist, station and hour; sponsored airtime ≤ 1,800 s, a quarter of the 2 h that can be programmed. Wallet: 1 per artist and 3 per UTC day (counted at reservation). Artist: optional daily cap. Existing rules apply (1 pick/h/station, no replay within 3 h, 2 upcoming per artist). Wallets of the same person can still take up to the caps: that is the cost of promotion, accepted by the artist when funding.
- **Not ranked.** A sponsored pick gives no curator points, does not enter Listeners' choice, does not trigger ingestion; it keeps the cooldown (`markPick`). Labelled everywhere: app ("Sponsored pick · paid by [artist]"), gnoweb, `ScheduleJSON` ("sponsored"), activity (`kind:"sponsored"`). `CuratorJSON` exposes `"promo"` (refunds received).
- **App.** Pick next: a "Free pick: [artist] refunds it (0.03 GNOT)" checkbox, checked by default when available, otherwise the reason; an honest cost line (fee + deposit). Player and Me: a "Collect 0.03 GNOT" button once the pick has aired. Me (verified artist): budget, refund per pick, add, withdraw.
- Measured gas (`gno test -print-runtime-metrics`, VM cycles without storage writes): `FundPromo` ≈ 2.0 M; `Queue` ≈ 7.7 M; `QueueSponsored` ≈ 6.7 M on the radio side + `PromoReserve` ≈ 3.3 M; `ClaimPickPayout` ≈ 2.5 M + `PromoClaim` ≈ 2.3 M; `WithdrawPromo` ≈ 1.4 M.

### Picks at a chosen time (v0.8)

```go
// radio: at = unix UTC time, between now + 15 min and + 24 h; 0 = as soon as possible (= the function without At)
func QueueAt(cur realm, stationID, trackID int, at int64)
func QueueWithNoteAt(cur realm, stationID, trackID int, at int64, note string, expires int64, sigHex string)
func QueueSponsoredAt(cur realm, stationID, trackID int, at int64)
// Queue, QueueWithNote, QueueSponsored call these functions with at = 0; Slot.At = requested time (0: pick for now)
// ScheduleJSON: "at" per entry and "booked":[{"track","start","end","at","by"}] (all upcoming booked picks, whatever the horizon)
```

- **Alignment.** The pick starts at the first track boundary from `at`: the end of the rotation track playing at that time, or the end of the listener picks that fill that moment. On Main, at `at` exactly: the current flow track fades out, as for a normal pick, and the flow (`lay`) resumes after; `program`, `ahead` and `NeedsSync` only count the continuous programme from now, a pick booked further ahead does not cut the flow.
- **It keeps its time.** A pick for now (and a new booked pick) goes before a booked pick only if it ends at or before that pick's time, otherwise after it. On a genre station, what is inserted before shifts the rotation: `realign` re-times the following booked picks on the new boundary (never before their time, at most one track later), the ones that followed them, and a pick for now that was waiting for the end of a rotation track after a gap (it waits for the new end of that track); the sponsored record and reports follow the `start`. Known limit: `Unqueue`, `DropSlot` and rotation edits do not re-time (the rotation track pauses around it, as around a pick that follows a removed pick).
- **Rules.** All those of `Queue` (genre, New, 1 waiting pick per listener and station, booked included, 1 h cooldown, 2 per artist, 30 upcoming). The 3 h gap is measured between air times, both ways, against the picks in the schedule: `at` for a booked pick, the computed start for a pick for now (which can wait up to 2 h behind others). `lastPick` keeps these times (a pick for now when queued, with its computed start, updated if `realign` shifts it; a booked pick when it is folded in by `fold`). The 2 h airtime cap only applies to picks for now; booked picks have their own: 4 per station and UTC hour. Sponsored: same rules, quotas measured around `at`; the catalog reservation expires 7 days after `at` + duration (`Slot.held`, 5th field of `sponsor`).
- **Gas** (VM cycles, `gno test -print-runtime-metrics`, each test run alone): empty station `Queue` +10.8 M, `QueueAt` +10.9 M; full station (29 picks of which 14 booked, all re-timed) `Queue` +18.8 M, `QueueAt` +18.6 M. Bounded by the 30 upcoming slots, independent of the catalog.
- **App** (Pick next, step 2): "Right away / At a time", times by quarter hour over 24 h in local time with the offset ("21:00 · GMT+2"), sent in UTC; full hours are greyed out; "21:00 · booked"; "On air at 21:00 your time". gnoweb: the booked pick shows in Up next with its time ("booked by").

