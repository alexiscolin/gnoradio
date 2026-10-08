# GnoRadio v1 architecture: data apart from rules

Status: P1 to P6 done. v1 (`p/role`, the `p/store` and `p/blocks` codecs, the
`data` realm and its vault, `catalog/v1`, `radio/v1`, `tickets/nft`, `tickets/v1`,
`home/v1`) is the only stack: the v0 realms are removed, the app, the certificate robot, the deploy
script and the devnet run on v1, and the release protocol was rehearsed (P6). Target: gno.land v1.5.0 (onyx and
mainnet). Prototype and measurements: `split-proto/` in the session scratchpad
(section 6). Decisions on the open questions: section 10.

## 0. The idea in one paragraph

All of GnoRadio's state moves into one permanent realm, `data`, that knows nothing
about music: ordered collections of string keys to string values. The rules realms
(catalog, radio, tickets, home) keep no state of their own. Each one is the only
writer of its role's collections ("catalog/…", "radio/…"). A new version of the
rules is a set of new realms. The data owner proposes it. Each new realm says
`Ready`. 72 hours later the whole set becomes the writers at once. No data is
copied, so no deposit is paid again. Coins held for promo budgets sit in a vault
inside `data`. Funders can always withdraw them, even while the rules are paused
or replaced. Every owner or admin role is passed in two steps (offer, accept)
and can be renounced. A separate guardian can pause and cancel a release, nothing
more. The guardian hands its role on, and the owner can replace it, but only six
days (2x the release delay) after announcing it, which the guardian cannot cancel.

## 1. Layout and paths

```
gno.land/p/<ns>/gnoradio/role/v0      two-step role (owner, guardian, admins), pinned to its realm (new)
gno.land/p/<ns>/gnoradio/store/v0     codecs only: Rec/Field/With, id lists, Pad, page rows, Ops (sparse trees removed)
gno.land/p/<ns>/gnoradio/blocks/v0    rotation as a codec over header/group/block strings (no persisted List)
gno.land/p/<ns>/gnoradio/{text,svg,safe}/v0   unchanged

gno.land/r/<ns>/gnoradio/data         the permanent data realm (no version)
gno.land/r/<ns>/gnoradio/tickets/nft  the permanent ticket NFT realm (P5, section 10)
gno.land/r/<ns>/gnoradio/catalog/v1   rules, release 1
gno.land/r/<ns>/gnoradio/radio/v1
gno.land/r/<ns>/gnoradio/tickets/v1
gno.land/r/<ns>/gnoradio/home/v1
```

Versioning, and how it differs from gnogolf:

- `data` has no version. It is the one realm that is never replaced, and its path
  identifies the deployment: it is the "GnoRadio" address users and robots bind to.
- Every rules realm has an explicit `/vN` from the start. gnogolf began with
  `golf` and then `golf/v2`. That asymmetry makes paths harder to predict. Here
  `vN` is the release number.
- One release number covers the whole set. radio, tickets and home import catalog,
  and home imports all three, so changing catalog means redeploying everything that
  imports it anyway. Bumping all four together means the import graph never mixes
  versions, and `Writers()` always shows a single `vN`. The cost is a few GNOT of
  code deposit per release.
- The `/p/` packages stay `/v0` and are edited in place. Nothing has been deployed
  publicly yet. After the first public deploy, any change needs a new `/vN` path.
- The former `r/gnoradio/{catalog,radio,tickets,home}/v0` realms (self-contained
  state) were removed in phase 6, before any public deploy. Release 1 is a new
  deployment, not a migration.

## 2. The data realm

### One shared realm, one writer per role

| | One shared `data` | One data realm per rules realm |
|---|---|---|
| Release protocol, pause, owner | one implementation, one audit | 3–4 copies, or a `/p/` type that holds writer authority (a Class 2 risk, see 5) |
| Atomic upgrade of the set | yes, one release | no. Three clocks and mixed versions are possible |
| Cross-role reads | one import | radio imports catalog's data realm and its own |
| Vault, sibling registry | in one place | spread out |
| Blast radius of a data-realm bug | everything | one role |

**Choice: one shared realm.** Its blast radius is the reason to keep it small
(target ≤ 500 lines), frozen and audited. It also owns the list of every realm that
has ever been a GnoRadio writer. That list replaces `SetSibling`, `SetRadioRealm`
and `SetSuccessor`.

### Writer swap: the release protocol

State: `writer[role]`, `paused[role]`, `proposed[role]`, `ready[role]`, `at`.
At deploy, release 1 is in force: each role's writer is `<data's path minus
"data">/<role>/v1`, so the staged namespace needs no edit, and the deployer is
owner and guardian.

1. `Propose(cur, role, pkgpath)`. Owner only. It adds a role to the next release
   and resets `at` to 0, so any change restarts the clock. It refuses `data` itself
   and the current writer. The path must start with `gno.land/r/`, be at most 100
   characters of `a-z 0-9 _-/.`, and contain no `.`, `..` or empty segment.
2. `Ready(cur)`. Called by a proposed realm, once. Each rules realm exposes
   `Ready(cur) { data.Ready(cross(cur)) }`, and anyone may call it: it only works
   for the realm whose code is now on chain. When every proposed role is ready,
   `at = now + DELAY`.
3. `DELAY = 72h` is a constant, so it can never be shortened. From `at` on, reads
   (`Writer`) already return the new set. The first write applies it (`settle`) and
   emits `WriterChanged` for each role.
4. `Cancel(cur)`. Owner or guardian. It drops a release that is not yet in force.
5. `Pause(cur, role, on)`. Owner, or the guardian for `on = true` only (and only
   while there is an owner to resume). `role` "" means every role. It stops that role's
   writes and vault operations at once. Reads and `VaultWithdraw` continue. Resume
   restarts the same writer at once, since no new code runs. Unlike gnogolf, a pause
   does not drop the pending release: cancelling it is a separate decision.
6. `Renounce(cur)`. Owner. Writers can never change again and nothing can be
   paused. It is refused while any role is paused, because that role could then
   never write again. It drops any release not yet in force.
7. Owner transfer: `Offer` / `Accept` / `Renounce`, through `p/role`.
8. Guardian: `GuardianOffer` / `GuardianAccept` / `GuardianRenounce`, a second
   `p/role`. The current guardian offers its role; the new one accepts. The
   owner's one call on it is `GuardianReplace(cur, to)`: `to` becomes guardian
   `2 × DELAY` (144 h) later, and the guardian cannot cancel it (`""` withdraws
   it, a new call restarts the clock). Without it a stolen guardian key could
   cancel every release and pause after every resume for good
   (`TestThiefGuardianIsReplaced`). The trade-off: a stolen owner key can also
   replace the guardian, but only after six public days, and its own release
   then needs 72 h more, so funders have nine days to withdraw. Once the owner
   renounced, the guardian can no longer pause, since nobody could resume.

Reads: `Writer(role)`, `Writers()` (JSON: writer, paused, proposed and ready per
role, plus `at`, owner, guardian, their pending offers, and `nextGuardian` /
`guardianAt` for a `GuardianReplace` on its way), `Owner()`,
`Guardian()`, and `IsGnoRadio(addr)` (any current, proposed or past writer,
`data` itself, or `tickets/nft`).

### API

All arguments and results are strings and ints. No pointer, slice or map ever
crosses the boundary in either direction (see 5, readonly taint).

| Call | Who | Notes |
|---|---|---|
| `Get(c, k) (string, bool)`, `Has`, `Size(c)` | anyone | non-crossing reads |
| `Index(c, k) int` | anyone | rank of `k` in `c`, O(log² n). Counts a key range without a counter |
| `Page(c, start, end, limit, reverse) string` | anyone | ≤ 100 rows with `start ≤ key < end` ("" no bound), highest first when `reverse`, encoded `len:key len:value` (`store.Row`, decoded by `store.Rows`). One call per page |
| `PageAt(c, offset, limit, reverse) string` | anyone | offset pages via the tree's sizes |
| `Set(cur, c, k, v)`, `Remove(cur, c, k) bool` | writer of `c`'s role | key 1–128 B, value ≤ 16 KiB |
| `Batch(cur, ops []string)` | writer | ≤ 64 ops of `set/del, c, k, v`. Strings are copied, the slice is not kept |
| `Make(cur, c)` | writer | a new collection under its own role, nothing if it exists. ≤ 32 per role; the whole name `<role>/<name>` ≤ 32 B, `a-z 0-9 _` after the role. A new release's realms make theirs once in force (in `init` they are not writers yet) |
| `Vault*` | see 4 | |

Reads of a collection that does not exist return nothing; writes to it panic.
A `Batch` is atomic only through the transaction: a refused op panics and the
chain reverts the ops before it.

There are no counter primitives. A single writer per role means a read-modify-write
inside one transaction is already atomic.

### Storage inside `data`: `p/nt/bptree/v0`, not `p/store`

Each collection is a `bptree.NewBPTree32()`, seeded with the key "" so that its
first leaf is paid by the deployer, never by the first user. Values are strings. A
bptree keeps each value as its own object, so updating one value rewrites that value
and not its neighbours. Measured on the same 5,000-track state (section 6):

| Layout of likes | first like | each further like |
|---|---|---|
| today: `p/store` hashed map, 65,536 buckets | 2,569 B | ~9 B (more on a new bucket) |
| `p/store` hashed map inside `data` | 1,796 B | – |
| bptree, one key per like | 659 B | 454 B |
| **bptree, one key per listener and 512 track ids (packed list)** | **665 B** | **~40 B** |

`p/store`'s sparse map is unordered and a new bucket costs ~1.5 KB, so it loses on
deposit and cannot serve pages. bptree is ordered, so prefix scans and offset pages
come for free, and the package is maintained upstream.

Layout rules (they decide the deposit):

- **Dense id data is chunked.** Tracks, artists and albums: 8 records per key
  (catalog `chunkSize`), tickets: 16 (`nft.Chunk`), `Pad((id-1) / n)`. Each new key
  costs roughly 400 B of object overhead, chunking pays it once per n ids. Measured: one key per track meant 1,233 B per
  publish, chunks mean 333 B.
- **Address-keyed data has one key per address** (users, curators, owners, budgets).
- **Growing id sets are packed lists per range of 512 ids** (likes per listener,
  genre index), as today.
- **Ordered indexes are key encodings**: zero-padded numbers, `key64(start)` for
  time. Paging and counting use `Page` and `Index`, never a stored counter list.
- **Each entrypoint writes a key at most once.** It loads what it needs, computes
  the final values, then writes them: one `Set` or `Remove` for a single key, one
  `Batch` from two keys on.

Limits: key 128 B, value 16 KiB (the longest value is a station record: at most 90
listener slots, a pick refused before the record leaves 1 KiB of headroom), `Batch`
64 ops, `Page` 100 rows, 32 collections per role. Every call is bounded, and none can
store or iterate without limit.

## 3. State mapping

Records keep today's `store.Rec` layouts and field order, so `records.gno`
decoding is reused. `P(n)` is `Pad`: 8-digit zero-padded. `T(t)` is a 12-digit unix
time. Each role's collections are written only by that role's current rules realm.

### catalog (writer: `catalog/vN`)

| Today | Collection / key → value |
|---|---|
| `artists` Seq(16) | `catalog/artists` P((id-1)/8) → 8 artist heads (layout frozen: `tickets/nft` reads it) (Rec of Recs) |
| `artistLists` Seq(8) | `catalog/alists` P(id) → Rec(track ids, album ids) |
| `byOwner` Map | `catalog/owners` addr → artist id |
| `names` Map | `catalog/names` skeleton → artist id |
| `tracks` Seq(16) | `catalog/tracks` P((id-1)/8) → 8 track records |
| `byGenre` [21]IDs | `catalog/genres` P(g)/P(id>>9) → packed ids. Per-genre counts live in `catalog/meta` |
| `albums` Seq(16) | `catalog/albums` P((id-1)/8) → 8 album records |
| `playlists` Seq(16) | `catalog/playlists` P(id) → record (up to 1.8 KB each, so not chunked) |
| `users` Map + `userRecs` Seq | `catalog/users` addr → Rec(follows, tipped, playlists, reports). The index indirection goes |
| tipped track ids | `catalog/tipped` addr/P(id>>9) → packed ids (a supporter counts once per track) |
| `likeSets` Map | `catalog/likes` addr/P(id>>9) → packed ids. The count and newest-first page come from prefix `Page`s of 100 ranges, at most 10 (512,000 track ids) |
| `reports` avl | `catalog/reports` P(id) → record |
| `removed` Map | `catalog/removed` kind:id → reason |
| `hosts` avl | `catalog/hosts` host → "1" |
| `nArtists … openReports`, genre counts, activity head | `catalog/meta` "n" → one Rec |
| `topLiked/topArtists/topFans/topSupport` | `catalog/tops` liked\|artists\|fans\|support → packed ranks |
| `activity` ring [64] | `catalog/activity` P(0..63) → record. Head in `meta` |
| `treasury, monthlyGoal, botKey, botGen`, admin mirror | `catalog/config` key → value |
| `supporterTotal` Map, `totalSupport, nSupporters` | `catalog/supporters` addr → total. Totals in `meta` |
| `monthly` avl | `catalog/monthly` YYYY-MM → total |
| `promo` Map | `catalog/promo` P(artist) → pct |
| `budgets` Map | money part → vault account `catalog/P(artist)` (4). Settings and stats → `catalog/budgets` P(artist) → Rec(pay, perDay, day, today, funded, paid, picks) |
| `walletDay` Map | `catalog/walletday` addr → day\|artist ids |
| `promoHeld` | gone: `data.VaultTotal()` |
| `claims`, `proofs` avl | `catalog/claims` P(artist) → Rec(to, proof, at, key generation), listed by `PendingClaims`. `catalog/proofs` P(artist) → url, whose host `ProofHost` shows next to the ✓ |
| `admin` | `p/role` in the rules realm, mirrored to `catalog/config` "admin" |
| `frozen, successor, radioRealm, siblingRealms, verifySig` | removed (7) |

### radio (writer: `radio/vN`)

From `radio/v1/db.gno`. Numbers inside the hot records are fixed-width base-64
digits (`store.Num`, `store.Fixed`).

| Today | Collection / key → value |
|---|---|
| `stations[i]` (epoch, live, ring, rotation header, schedule, recent picks, weekly top) | `radio/stations` P(i) → one Rec, schedule included: one read and one write per pick |
| `stations[i].rot` blocks.List | `radio/rot` P(i)/b/P(block) → ids+durs (768 B). `radio/rot` P(i)/g/P(group) → block sums |
| `homes` Seq | `radio/homes` P((id-1)/16) → 16 entries (a track's genre stations) |
| `synced, drops, activity head, top week/score, live[21]` | `radio/meta` "flow" → fixed-width record (Main's flow itself is computed, not stored) |
| `curators` Map | `radio/curators` addr → record |
| `tops` [23]weekTop | a station's weekly top is in its `radio/stations` record; the all-stations one is `radio/tops` "all" |
| `lastPick` Map | the recent picks are in the station record (no collection) |
| `dropped` Map | `radio/dropped` P(st)/P(track) → "1" |
| `noteReports, muted, strikes` | `radio/notes` P(st)/T(start). `radio/muted` addr → until (`MutedUntil`). `radio/strikes` addr |
| `sponsor` Map | `radio/sponsor` addr/P(st) → open sponsored pick |
| `activity` ring | `radio/activity` P(0..63) |
| `noteKey`, admin mirror | `radio/config` "modbot", "admin" |
| `frozen, successor, verifySig, radioTip, promo*` seams | removed |

`p/blocks` keeps its algorithm (Find, PrefixBefore, Set, Append). It now
works on a header string plus the one group and one block a call touches, and
returns the strings it changed. radio writes those back in its single `Batch`. The
cost per operation stays O(n/Size² + Size): three reads and up to three writes,
whatever the catalog size.

### tickets (writer: `tickets/vN`)

| Today | Collection / key → value |
|---|---|
| `events` avl of *event | `tickets/events` P(id) → record |
| `byArtist` | `tickets/byartist` P(artist)/P(event) → "" |
| `artistEvents` counts | gone: `Index` over the prefix |
| `upcoming` | `tickets/upcoming` T(start)/P(event) → "" (visible, not cancelled) |
| `artistAhead` | `tickets/ahead` P(artist)/T(start)/P(event) → "" |
| `tickets` Seq(16) + grc721 ledger | `tickets/tickets` P((id-1)/16) → 16 Rec(event, serial, attended). The holder is the NFT's owner in the permanent `tickets/nft` realm (section 10) |
| `owned` Map | `tickets/owned` addr → packed ids |
| `buyers` Map | `tickets/buyers` P(event)/addr → count |
| `attended` avl | `tickets/attended` addr → count |
| `nEvents, nTickets, serviceFee`, admin mirror | `tickets/meta`, `tickets/config` |
| (new) door presentations | `tickets/present` P(ticket) → Rec(holder, time, door code) of its last `Present`, deleted at check-in |
| `ticketTok, ticketLed, tokSeq` | the ledger moves to the permanent `tickets/nft` realm (section 10) |
| `artistVerified/artistVisible` seams | removed |

### home (writer: `home/vN`)

`appURL`, `contact` → `home/config` "app" and "contact". These remain gated on
the catalog admin, as today: home has no admin role of its own, so no `p/role`.
`onAirNote` and `tippable` (test seams) are removed: the tests verify artists
through the catalog's dev admin and dedicate through the robot's real
certificate (`home/v1/filetests/z_note_filetest.gno`). `Render` reads
`data.Writer("home")` (moved), `data.Paused` (paused) and `data.Writers()` "at"
(a ready release and when it takes over: the 72 h window is shown to visitors).

## 4. Coins

| Flow | Where the coins are | Across an upgrade |
|---|---|---|
| Tips, `TipOnAir`, `SupportGnoRadio`, ticket price and fee | passed through in the same transaction by the rules realm that received them | nothing is held |
| Promo budgets and sponsored-pick holds | **vault in `data`**, at the data realm's address | they never move: the next rules use the same vault |

The vault lives in `data`'s own unexported state, not in a collection, so no writer
can forge a balance. Each account (`catalog/<artist>`) holds its funder, balance and
holds (`expiryDay:amount`, lapsing by themselves exactly as today).

| Call | Who | Rule |
|---|---|---|
| `VaultCredit(cur, acct, funder, amt)` | writer of `acct`'s role | `banker.GetCoins(data) ≥ VaultTotal + amt` must hold first. The rules realm sends the coins it received before crediting. The funder is outside GnoRadio; a new funder needs an empty account (`VaultRefund` first), so a writer cannot hand one funder's coins to another |
| `VaultHold(cur, acct, amt, day)` | writer | requires `free ≥ amt`, `VaultDay() ≤ day ≤ real day + 31`: hold days are real UTC days (the key a claim finds again), and a hold lives until the vault clock passes it, so an account holds at most 32 days plus the total days roles were ever paused (a pause keeps every refund window open; by design, see review R29) |
| `VaultRelease(cur, acct, amt, day) int64` | writer | gives back up to `amt`, returns what it released |
| `VaultPay(cur, acct, to, amt, day)` | writer | takes from a live hold. `to` must not satisfy `IsGnoRadio` |
| `VaultRefund(cur, acct)` | writer | pays the whole balance to the funder and drops its holds (the profile changed hands) |
| `VaultWithdraw(cur, acct)` | **the funder**, `cur.Previous().Address()` | pays out `free`. Not gated by writer, pause or renounce |
| `VaultInfo(acct)` (funder, balance, free), `VaultHeld(acct, day)`, `VaultTotal()` | anyone | `PromoJSON` and `PromoClaimable` read these |

Guards:

- Every payable entrypoint checks `cur.Previous().IsUserCall()`, then a single
  `ugnot` coin with the exact or bounded amount from `unsafe.OriginSend()`.
- Every other entrypoint calls `noPayment()`. In `data` that is every call of the
  owner, the guardian and `VaultWithdraw`; writer calls do not, since they run
  inside a rules realm's payable transaction (`OriginSend` is the whole
  transaction's).
- A rules realm ends every transaction holding 0 ugnot, so its balance check is
  `GetCoins(self) ≥ amount`. Today the catalog checks `promoHeld + total`. The new
  check is simpler and stricter.
- `TipOnAir`: radio forwards the coins to `chain.PackageAddress(data.Writer("catalog"))`
  and calls `catalog.RadioTip(cross(cur), …)`. catalog checks
  `cur.Previous().PkgPath() == data.Writer("radio")`. No `radioRealm` setting is left.
- Tracks enter the same way: `radio.PublishTrack` / `ImportTrack` / `EditTrack` name the signer
  (`cur.Previous()`, a wallet's `MsgCall` for publish and edit) and call `catalog.PublishFor` /
  `ImportFor` / `EditFor`, which only the radio writer may call (the same `onlyRadio` guard).
  The catalog checks the signer as before (its own profile; the admin for imports); no caller
  can name another wallet. The radio then ingests the track with Sync's own `ingest` in the same
  transaction, so every track is on air from its first block, paid by its publisher. A paused
  radio role therefore pauses publishing and track edits too (a paused catalog already did).

What still protects funders against a malicious release: the 72-hour public delay
(events `WriterProposed` and `ReleaseReady`) during which `VaultWithdraw` works, and
the fact that a pause never blocks withdrawal. A writer can only reach the coins
through holds, and only after its delay. A pause stops the vault's clock
(`data.VaultDay`): no hold lapses while any role is paused, so a sponsored refund
keeps the rest of its 7-day window after the resume. The clock then lags real time
by the pause, and later holds last that much longer.

## 5. Roles and powers

`p/role` keeps `home` (the realm that created the role), `owner` and `pending`.
Every method takes `_ int, rlm realm` and first checks
`rlm.IsCurrent() && rlm.PkgPath() == home`. The `_ int` is not decoration: v1.5.0
treats a method whose first parameter is a `realm` as crossing, and refuses that in
`/p/` (verified in the prototype).

| Realm | Role | Can | Cannot |
|---|---|---|---|
| `data` | owner (multisig recommended) | propose, cancel, pause, resume, offer, renounce, replace the guardian 144 h after announcing it (`GuardianReplace`) | write data, touch the vault, offer, accept or renounce the guardian role |
| `data` | guardian (deployer at init, then a separate cold key or multisig) | pause (while an owner exists), cancel a pending release, offer or renounce its own role | resume, propose, anything of the owner's, cancel a `GuardianReplace`, write data, touch the vault |
| catalog | admin (moderator) | hide/restore content, resolve reports, curated imports, assign/verify/cancel/reset claims, allowed hosts, `SetBot`, treasury, monthly goal, release names | budgets, tips |
| radio | admin | curator queue, drop/restore slot, unqueue, unmute, restore note, `SetModBot` | |
| tickets | admin | hide concerts, service fee | ticket money |
| home | (catalog admin) | app link, contact line | |
| robots | off-chain Ed25519 keys | sign certificates only | anything on chain |

- **Two-step everywhere.** `Offer(to)` (offering it to the owner cancels the offer),
  `Accept()`, `Renounce()`. The three one-step `TransferAdmin` functions are removed.
- **Admins survive a release.** Each change is mirrored to `<role>/config "admin"`,
  and a new version's `init` reads it. A renounced admin is stored as renounced.
  The deployer becomes admin only when no mirror exists yet.
- **Under `gno test`** the deployer is empty, so `init` uses a fixed dev address on
  chain id `dev`, as gnogolf's `setUp` does. Tests then go through the real flow
  (`Verify`, `HideArtist`) instead of swapping function variables.
- **Successor pointers** are `data.Writer(role)`. A retired rules realm detects it
  (`data.Writer(role) != self`), says so in `Render` and `Info` (`"current": …`), and
  every write fails at the data gate anyway.
- **Freeze is removed.** It existed for migrations. `data.Pause(role)` is the
  emergency brake.
- **Robot keys.** The keys are stored in `<role>/config`. Rotating the catalog key
  voids pending claims (`botGen`, as today). Certificates are bound to the chain id,
  **the data realm path** (new: a staging deployment on the same chain cannot reuse
  them), the wallet, the target (artist, or station and note), and an expiry of
  2 hours or 15 minutes.

## 6. Cross-realm costs: measured

Prototype: `scratchpad/split-proto/`:

- `r/proto/data`: release protocol, collections, `p/role` owner. Tests pass on the
  onyx v1.5.0 toolchain.
- `r/proto/catalog/v1`: Like and Publish variants, and pages.
- `r/measure/*_filetest.gno`: one operation per filetest, with `Gas:` and `Storage:`
  goldens.

The baseline is today's catalog under the same harness (`scratchpad/baseline/`).
Both are seeded with 5,000 tracks, 20 artists and 300 likers in the realm's `init`,
so the measured operation loads its state from the store as a real transaction does.

Run: `GNOROOT=~/go/pkg/mod/github.com/gnolang/gno@v1.5.0 GNOHOME=~/.cache/gno-toolchains/onyx-v1.5.0/gnohome ~/.cache/gno-toolchains/onyx-v1.5.0/gno test ./r/measure`

| Operation (filetest gas, whole tx) | Today | Split | Deposit today | Deposit split |
|---|---|---|---|---|
| Like, first by a listener (same work as today: early badge, activity, event) | 5.37M | **5.37M** batched / 5.45M direct | 2,569 B = 0.257 GNOT | **786 B = 0.079 GNOT** |
| Like, then a second like in the same range | – | +4.1M | – | +63 B |
| PublishTrack, data work only | 1.22M | 3.11M (chunk, artist list, genre, meta, activity) | 345 B | 438 B (812 B once every 16 publishes, on a new chunk) |
| PublishTrack validation (same code both sides) | 4.14M | 4.14M | | |
| 20 newest tracks (`TracksJSON`) | 19.76M | 8.71M | | |
| Like at 20,000 tracks (chunked) | | 4.46M vs 4.37M at 5,000 (+2%) | | 648 B (flat) |

Unit costs: a `data.Get` is ≈ 35k gas. A `data.Set` that rewrites a value is
≈ 170k. Each extra cross-call costs ≈ 32k (10 writes: 4.99M direct, 4.67M in one
`Batch`).

**Measured on the real `data` realm (P2)**: `gno/r/gnoradio/data/filetests`, one
operation per filetest with exact `Gas:` and `Storage:` goldens, so any change
fails until reviewed. Each filetest's `init` stores one small collection and
5,000 keys in a transaction of its own; `Gas` counts that `init` too, so the
units below are differences between filetests.

| Unit | Prototype (above) | `data` realm | Filetests |
|---|---|---|---|
| `Get`, small collection | ≈ 35k | 32.3k | `c_get21 − b_get1`, ÷ 20 |
| `Get` of a key not yet loaded, 5,000 keys | – | 125k | `i_bigget21 − h_bigget1`, ÷ 20 |
| `Set` rewriting a value, its own cross-call | ≈ 170k | 198k (+16%) | `e_set21 − d_set1`, ÷ 20 |
| each extra cross-call (10 direct `Set`s against one `Batch`) | ≈ 32k | 61k | `f_new10direct − g_new10batch`, ÷ 9 |
| deposit of a new key, small value | ≈ 413 B | 414 B | `f_new10direct` ÷ 10 |
| deposit of a new key, 5,000 keys | – | 455 B | `j_bignew1` |

The cross-call costs more than in the prototype because `data` declares more
functions (the vault, the guardian): measured, removing the vault's functions
brings it back to 48k, and comments cost nothing. The cost of a cross-call grows
with the number of the realm's declarations, which is one more reason to keep
`data` small and `Batch` the writes. A `Get` on a big collection costs its tree
walk (three levels at 5,000 keys), which P3 budgets must use rather than the
prototype's one-leaf figure.

How to read these numbers:

- A filetest counts VM and store gas but not the transaction's fixed overhead.
  Today's on-chain Like is 17.5M against 5.37M here, so the overhead is about 12M per
  transaction.
- Projected on chain: **Like ≈ 17.5M (flat)** and **PublishTrack ≈ 24.5M (+1.9M,
  +8%)**. Deposits: **first like 0.079 GNOT instead of 0.24**, publish +0.009 GNOT.
  Expect first picks and first tickets to drop the most: per-address keys replace
  65,536-bucket maps, and the grc721 ledger goes. Re-measure them in phases 4–5.
- Publishing costs more gas because every write is a separate object save in another
  realm. Publishing is rare, liking is frequent. Phase 3 budgets it at ≤ 6.0M
  filetest gas without validation.

**Measured on `catalog/v1` (P3)**: `catalog/v1/filetests/z_gas_*`, a catalog of
5,000 and 20,000 tracks seeded by each filetest's `init` (activity ring full,
leaderboards held). "Main" is the filetest's gas minus `z_gas_noop`'s; v0 is the
baseline harness (main minus its 2.81M noop). The fixed cost of a call is 3.31M
on v1 (`z_gas_base`: catalog plus data loaded) against 2.81M on v0.

| Action (5k tracks) | v0 main | v1 main | v1 at 20k | Deposit v0 | Deposit v1 |
|---|---|---|---|---|---|
| Like, first by a listener | 2.55M | 3.09M | 3.13M | 2,569 B | 498 B |
| Like, same range again | 0.57M | 2.97M | 3.01M | 953 B | 58 B |
| PublishTrack (validation 1.77M included) | 2.60M | 5.67M | 5.86M | 374 B | 657 B |
| Register + publish | 8.71M | 10.02M | | 3,937 B | 2,093 B |
| Tip | 4.23M | 4.87M | 4.91M | 4,758 B | 1,023 B |
| Follow | 2.21M | 2.71M | | 3,087 B | 513 B |
| `TracksJSON(0, 20)` (full JSON) | 16.95M | 12.35M | 13.00M | | |

After the review fixes (main minus noop): Like and Follow +0.14M (one more read
for the feed check, L8), Tip +0.04M, Register + publish +0.82M (the reserved-name
check, L4), Publish and `TracksJSON` unchanged. The goldens hold whole-file gas
(mostly the seed), so nothing checks these budgets automatically: subtract the
noop golden by hand (review L32, accepted). `TracksJSON(0, 20)` is budgeted at
13M, not the plan's 9M: it is a read, and the app pages it.

Lessons that shaped the code: a `strconv` conversion costs ~33k and a
`store.Field`/`With` up to 130k on a long record, so hot paths change fields in
place (the counters come first in the track and artist records), JSON is
written from the stored decimal strings, and a write op in a `Batch` costs
~0.2M whatever its size. Changes from the plan: chunks of 8 records (a
1,500-byte record cap keeps 8 under 16 KiB with growth), the activity head is
its own key `catalog/meta "head"`, the tipped tracks are ranged like the likes
(`catalog/tipped`), `store.Append`, `data.Paused`, and the funder withdraws with
`data.VaultWithdraw("catalog/" + P(artist))` (catalog's `WithdrawPromo` is gone).

**No write queue.** Per-write cross-calls are cheap: 2 direct writes cost less than
gnogolf's queue and overlay (4.21M against 4.28M). The plan is: load the state once,
compute the final values, write each key once, and use `Batch` from three writes on.
There is no read-back overlay, and so no "walk after write" failure mode
(gnogolf's `view.clean` panic). `p/store` gains a pure `Ops` builder (`[]string`)
for `Batch`.

### P4 measurements: radio/v1 (main minus noop)

`radio/v1/filetests/z_gas_*`: 5,000 and 20,000 tracks by 20 verified artists,
synced, a Main flow written ahead, Listeners' choice holding 210 tracks, full
tops and activity ring, picks waiting, a dedication, a sponsoring artist (9)
and artist 1 sharing 5% of its tips. v0 is the same state and mains in the
baseline harness (its main minus its 2.50M noop). Deposit is main's, in the
data realm.

| Action | 5k v0 → v1 | 20k v0 → v1 | Deposit v1 (5k / 20k) |
|---|---|---|---|
| Queue (genre station) | 6.57M → 7.51M (+14%) | 6.72M → 7.58M (+13%) | 626 / 620 B |
| QueueAt (booked) | 6.23M → 7.63M (+22%) | 6.38M → 7.69M (+21%) | 618 / 612 B |
| Queue on Main (flow) | 11.74M → 11.88M (+1%) | 11.84M → 11.93M (+1%) | 668 / 662 B |
| QueueWithNote | 9.70M → 11.02M (+14%) | 9.85M → 11.09M (+13%) | 635 / 629 B |
| QueueSponsored | 11.04M → 11.03M (0%) | 11.24M → 11.13M (−1%) | 1,208 / 1,202 B (0.2 GNOT default refund) |
| TipOnAir (picker paid) | 8.24M → 7.89M (−4%) | 8.34M → 7.93M (−5%) | 1,015 / 1,039 B |
| ReportNote | 1.77M → 2.16M (+22%) | 1.77M → 2.16M (+22%) | 500 / 500 B |
| Sync of 20 tracks | 12.47M → 22.20M (+78%) | 12.75M → 22.67M (+78%) | 136 / 136 B |

Full-schedule Queue (measured in `gno test -v` gas, the test with the pick minus the same setup without it, a genre station at the listener-slot cap: 89 listener slots, 60 aired in the last hour, 14 for now, 15 booked, plus the new pick): 41.5M when every slot carries a 40-character dedication, 31.1M with none; at the old cap of 60 slots, 24.0M; an empty station, 9.6M. The cost follows the bytes of the station record (about 3k gas a byte). On chain add what an empty-station Queue costs beyond 9.6M (about 34M measured on the devnet, so about 24M): roughly 55M to 66M, under the app's 70M (Queue) and 80M (QueueWithNote) gas limits, but above the 30M budget for the Queue work itself.

Sync is the price of the split (each new track writes its homes entry and the
rotation strings of the stations it joins, in data). Since publishing puts a
track on air itself, that cost is paid per track by its publisher, and `Sync`
(anyone, 20 to 200 tracks a call) is only a safety net. No robot calls it:
GnoRadio pays nothing.

**PublishTrack on air** (`radio/v1/filetests/z_gas_publish_*`, main minus noop,
same seed): the catalog alone (the former `catalog.PublishTrack`) 4.13M at 5k
tracks / 4.36M at 20k; `radio.PublishTrack`, stations included, 11.18M / 11.67M:
**+7.0M / +7.3M** for the join. The join is one track's work whatever the
catalog size: Main's and the genre station's rotation tail (header, one group,
one block each), New's ring (a slot reused in place once full, O(log n) index
search), the track's homes chunk and the flow record, each read once and
written once in one `Batch`. Deposit 730 B (661 B before), 1,212 B on every
16th publish (a new homes key). The P5 shared fixes moved these
numbers: the `p/blocks` codec now uses `p/store`'s unrolled `Num`/`Fixed`
(−0.16M to −0.31M per pick or sync), radio uses them too instead of its own copy
(+20k to +50k: a bigger `p/store`), and storing the funding generation instead of
the funder saves sponsored picks a vault read (−0.65M, −40 B).

**Review after P5 (algorithms and Main's relay)**: main minus noop at 5,000 tracks,
before → after (`radio/v1/filetests`, `catalog/v1/filetests`). Queue 8.33M → 6.46M,
QueueWithNote 11.84M → 9.98M, Queue on Main 13.53M → 7.64M (no flow top-up),
PublishTrack 11.18M → 10.31M (one rotation write when New reuses a slot), a Sync with
nothing to ingest 22.49M → 3.81M (it writes no flow), BuyTicket 6.38M → 6.28M; reads: radio
`ActivityJSON(10)` 12.1M → 1.75M, catalog's 17.9M → 5.05M (point reads of the ring).
Main's flow is computed on read: `ScheduleJSON(Main, 3600)` 17.8M → 18.3M,
`ScheduleJSON(Main, 7200)` plus `NowPlaying(Main)` after 6 idle hours 66.6M
(`z_gas_nowplaying`), well under a query's limit.

**Main as a simulcast**: between its own picks Main plays what the hour's genre station
plays (track, offset and picks), so it never jumps when that station is edited, and it keeps
no rotation: ingest, Sync and Refresh no longer append to or re-anchor one, and Main's track
count and loop are the genre stations' added up. Main minus noop, 5k / 20k tracks:
PublishTrack 10.31M → 8.90M / 10.81M → 9.25M, Refresh 9.06M → 8.74M / 9.52M → 9.19M, Queue
on Main 7.64M → 6.45M / 7.32M → 6.48M, `ScheduleJSON(Main, 3600)` 18.3M → 18.3M,
`ScheduleJSON(Main, 7200)` plus `NowPlaying(Main)` after 6 idle hours 66.6M → 65.1M; a Sync
with nothing to ingest stays at 3.81M. ImportTrack runs the same ingest as PublishTrack, New left out; ImportTracks loads the realms once for up to 25 imports. The goldens count about 9.5M (5k) to 9.7M (20k) of execution and about 360 bytes per track (`z_gas_import1_*`, `z_gas_import25_*`); a simulated transaction on the 5k devnet uses more, about 33M per call plus 28.1M per track (735M for 25), which is what `tools/deploy/import.py` sizes its gas on.

### Pointers to Audius and Jamendo: gas and quotas

A pointer (`audius:<id>`, `jamendo:<id>`) goes through the same `ImportFor` / `ImportTracks`
path as a curated import, with no title, credits, cover, source or attribution (catalog
`TestCuratedAudiusAndClaim`, `TestClaimedPointerNamed`, `TestHideSource`). Measured on the
devnet fixtures (main minus noop, a batch of 25, `z_gas_import25_*` vs `z_gas_ref25_*`):

| Per track | Full import | Pointer |
|---|---|---|
| Gas, 5k / 20k tracks | 9.80M / 10.0M | 6.65M / 6.86M |
| Storage (data realm, artist record included) | 414 B (0.041 GNOT) | 305 B (0.031 GNOT) |

`tools/deploy/import.py` sizes its gas on a simulated full batch (60.8M for one line, 735M for
25), so pointers always fit.

The app reads titles, names and covers through `/api/meta?bucket=N` (`app/netlify/functions/meta.mts`),
only for the tracks a screen shows: one request per bucket of 100 on-chain track ids (ids
100·N to 100·N+99; the same URL for every visitor), up to 3 at a time, kept in memory for the
session (an LRU of 10,000), never in the stored catalog. A search asks for every bucket once.

The platform calls are bounded by what is on chain, not by what a client asks for. The function
reads the chain (a count, then one `TracksJSON` page of the bucket), keeps the pointers it
finds (hidden tracks are not there), and asks Audius and Jamendo for those only. Any other query
parameter is a 400, so the cache keys are a finite set: one per bucket (`netlify-vary: query=bucket`).
For a Jamendo pointer the answer also carries its `stream` URL (jamendo.com only, signed by Jamendo),
which the app keeps in memory and plays as it is: a play costs no Jamendo call. Link previews (`cards.ts`,
`og.mts`) never call the platforms: a pointer's card says "Audius track" / "Jamendo track".

Quotas. The platforms' terms allow session caching only, so the shared copies are short:
`/api/meta` is fresh 3 hours in Netlify's durable cache (one copy for every edge), then served
stale for 5 minutes while one call refreshes it; the browser keeps it 5 minutes.

- `/api/meta`: at most 8 runs per bucket per day (240 a month), each one chain read, one Audius
  call (up to 100 ids) and, for Jamendo, one call per 50 Jamendo pointers of the bucket (a full
  bucket: 2). Streams cost no extra call. With about 3,100 Jamendo pointers in about 31 buckets,
  the worst case is 31 · 2 · 240 ≈ 14,900 calls a month, under Jamendo's 35,000, whatever the
  audience; Jamendo fits up to about 7,000 pointers on that worst case. When Jamendo refuses,
  `/api/meta` still answers Audius (a partial answer, cached a minute at most) and the Jamendo
  pointers stay unnamed and silent until it answers again.
- Function runs: 8 · B a day, about 240 · B a month, far under 125,000.
- Audius plays go from the browser to api.audius.co with `app_name` only, so the key's quota
  does not grow with the audience.
- Netlify, legacy free plan (100 GB a month, a hard limit): a meta answer is about 7 KB gzipped
  for 100 tracks, kept three hours. The app itself is about 0.4 MB gzipped on a first visit (hashed
  assets, cached a year). Audio never goes through Netlify: archive.org, Audius or Jamendo serve
  it, and so do the station jingles and the promo video (archive.org items `gnoradio-jingles` and
  `gnoradio-promo`). A session is then about 0.5 MB on a first visit and well under that after:
  100 GB is roughly 200,000 sessions a month (about 6,500 a day). Past that, Netlify Pro.

Open: we do not know how long Jamendo's signed stream URLs stay valid. When one fails, the
player drops that bucket from its in-memory cache once, so the next `want()` fetches the meta
again (the browser and CDN copies can hold it for up to the cache window first).

### P5 measurements: home/v1

`Render` gas, the same 180 tracks, 6 artists, 6 concerts and 40 likes on v0 and
v1 (unit tests, `gno test -v`; a query may use 3,000M):

| Page | v0 → v1 | Page | v0 → v1 |
|---|---|---|---|
| home | 105.2M → 134.1M | stations | 16.4M → 40.2M |
| station/0 | 40.8M → 45.5M | catalog | 29.7M → 35.4M |
| artist | 61.0M → 66.5M | track | 18.1M → 19.7M |
| concerts | 8.1M → 15.4M | listener | 54.9M → 59.9M |
| charts | 13.4M → 17.6M | join | 7.6M → 9.1M |

Each reader is now a `data.Get` or two instead of a field read; the stations
page asks the radio and the catalog once per station (23). The SVG artwork
remains most of the home page's cost.

### P5 measurements: tickets/v1 (main minus noop; small = 1 concert / 10 tickets, large = 200 / 1,000)

| Action | Small v0 → v1 | Large v0 → v1 | First-action deposit (bytes) |
|---|---|---|---|
| BuyTicket | 5.73M → 6.36M (+11%) | 6.99M → 7.66M (+10%) | 8,908 / 7,509 → 5,051 / 5,083 |
| TransferTicket | 6.88M → 6.40M | 8.18M → 8.03M | about 0 net |
| CheckIn | 4.15M → 4.68M (+13%) | 4.43M → 4.89M (+10%) | 1,052 / 1,065 → 478 / 480 |
| CreateEvent | 8.51M → 6.94M (−18%) | 10.64M → 8.33M (−22%) | about 11.9K → 1.7K |

After the review fixes: BuyTicket and CreateEvent +0.01M, TransferTicket +0.07M
(canonical-address checks). The CheckIn filetests now include the holder's
`Present` (M5) in their seed, so their main minus noop is Present plus CheckIn:
8.05M small, 8.39M large.

## 7. Dead code

Done. The v0 realms and their comparison filetests, the migration readers, the
function-valued test seams, `p/store`'s typed state (`Seq`, `Map`, `IDs`, the sparse
tree), `store.Has`, `text.Key`, `blocks.SetDuration` and the old `blocks.List` tests
are gone; `List` survives only as the codec's test oracle
(`p/gnoradio/blocks/v0/list_test.gno`).

## 8. Security: threat model and tests

| Threat | Mitigation | Test (phase) |
|---|---|---|
| A realm or account writes data it does not own | `gate`: the immediate caller's pkgpath must equal `writer[role of c]`. Accounts, MsgRun and the owner never pass | `TestOnlyWriterWritesItsRole` (P2, passes) |
| catalog writes radio's collections | the role comes from the collection prefix, checked for every op of a `Batch` | same test, `Batch` case |
| A swap without the delay | `DELAY` is a constant. The clock starts when every proposed realm said `Ready`. Any `Propose` resets it. Only proposed realms call `Ready`, once. A proposed path is a plain realm path, never `data`, `tickets/nft` or the current writer | `TestReleaseTakesOverAfterDelay`, `TestProposeChecksPath` (P2, pass): an early write is refused, the switch happens after `SkipHeights` |
| **A private package re-uploaded after the delay** (`private = true` packages can be re-uploaded) | cannot be checked at runtime. Release checklist: the proposed `gnomod.toml` has no `private` or `replace`. Rehearsed on a v1.5.0 gnodev (P6): a second `addpkg` of a `private = true` realm **is accepted and replaces its code**; a normal realm is refused (`PkgExistError`). So the checklist is the only guard: the guardian checks every proposed realm during the 72 h | P6 release rehearsal |
| Owner key stolen: a malicious release | 72h public window, `VaultWithdraw` stays open, the owner should be a multisig, and the guardian (a separate key) pauses and cancels the release | `TestWithdrawWhilePaused` (a release proposed and ready, every role paused, the funder withdraws), `TestGuardian` (P2) |
| Owner key stolen: the thief removes or replaces the guardian first | the owner cannot offer, accept or renounce the guardian role. Its `GuardianReplace` takes 144 h (2 × DELAY), in public (`Writers()` "nextGuardian", the home banner reads `Writers()`); the guardian keeps pausing and cancelling meanwhile, and a malicious release still needs its own 72 h after that. **Accepted**: nine days of notice, not a permanent block, because the owner needs a way back from a lost or stolen guardian key (next row) | `TestGuardian` (owner-only `GuardianOffer`, `GuardianRenounce`, `GuardianAccept` fail), `TestThiefGuardianIsReplaced` |
| Guardian key stolen (review M3) | it can only pause and cancel: writes stop (reads and `VaultWithdraw` go on), no coin moves, no writer changes. The thief can move the role to its own key, but the owner's `GuardianReplace` hands it to a fresh key after 144 h, and the guardian can neither cancel that nor touch the owner. Until then the owner resumes after each pause | `TestThiefGuardianIsReplaced` (the thief takes the role, vetoes, cannot cancel the replacement, loses the role at 2 × DELAY), `TestGuardian` (P2) |
| Pause misused | owner, or guardian for a pause only. Never blocks reads or `VaultWithdraw` | `TestPauseResumeRenounce`, `TestGuardian`, `TestWithdrawWhilePaused`, `TestWithdrawAfterRenounce` (P2) |
| Renounce bricks GnoRadio | refused while any role is paused. Drops a pending release | `TestPauseResumeRenounce` |
| Stale or forged realm value used for authority (Class 2) | `p/role` checks `rlm.IsCurrent()` and `home`. Every entrypoint uses the runtime-current `cur.Previous()`. No `caller address` parameter carries authority (`VaultCredit`'s `funder` is data the writer records, not authority) | `TestRoleRefusesStaleRealm`, `TestRoleFromForeignRealm` (P1, pass) |
| A leaked `/p/` pointer used as a mutator (D2 borrow) | `*Role` and `*bptree.BPTree` sit in unexported vars and are never returned. `Role` methods refuse foreign realms even if the pointer leaks. `data` returns only strings and ints | grep lint in CI: no exported var, no exported func returning a pointer (P1–P5). Foreign-realm test (P1) |
| Readonly taint across the boundary | rules read only strings (immutable). `Page` returns one string. `Batch` copies the strings and never keeps the caller's slice | `TestBatchDoesNotAliasSlice` (P2): mutating the slice after `Batch` changes nothing |
| Function or interface values from callers (Class 3/4) | none in any API. Seams removed | grep check (P6) |
| Payment bypass through MsgRun | `IsUserCall` plus an exact `OriginSend` on every payable path. `noPayment()` elsewhere. `data` has no payable call | `TestOwnerCallsTakeNoCoins` (P2), `TestPayRefusesRealms` in catalog, radio and tickets (`threat_test.gno`): every payable entrypoint refuses a realm caller |
| Coins stuck or stolen | vault invariant `banker(data) ≥ VaultTotal`, checked before each credit and asserted after each test. Payouts never go to a GnoRadio realm. A new funder needs an empty account. Rules realms end every transaction at 0 balance. `VaultWithdraw` for the funder only. Coins sent to `data` outside a credit can only be credited by a writer (no owner sweep, by design). The credit check is a subtraction (`GetCoins − VaultTotal ≥ amt`), so a huge amount cannot wrap it (auditor Y1) | `TestVaultInvariant`, `TestVaultHoldsLapse`, `TestVaultGuards`, `TestWithdrawFunderOnly` (P2), `TestRulesHoldNothing` (P3) |
| Robot certificate replay | bound to chain id, data path, wallet, target and expiry. Short life. Rotating the key voids pending claims | catalog `filetests/z_cert_filetest.gno` and radio `filetests/z_note_cert_filetest.gno`: other wallet, other station, expired, other deployment |
| DoS through big keys or values, or many ops | key ≤ 128 B, value ≤ 16 KiB, `Batch` ≤ 64, `Page` ≤ 100, ≤ 32 collections per role, ≤ 32 holds per vault account, plus one per day roles were ever paused (R29). Per-user lists capped (a new 1,000-follow cap) | `TestLimits`, `TestVaultHoldsLapse` (P2), cap tests (P3) |
| Unbounded loops as data grows | all walks are paged (≤ 100). Upcoming scan ≤ 1,000. Like counts walk the user's own ranges only (≤ catalog/512 keys) | gas filetest budgets at 5k and 20k tracks (P3–P5) |
| Gas griefing (making someone else's action expensive) | fixed-size hot records (activity ring, 10-entry tops, early badges ≤ 10, schedule ≤ 120). A user's lists only cost that user. Leaf splits are O(log n) | the same filetests, with a heavy-user seed |
| A bug in `data` itself (it can never be replaced) | small (about 590 lines of code with the vault and the guardian, against a 500 target), no business logic, frozen API, a fuzz-style test of the row codec (`TestRowsRoundTrip`) and `Batch`, a gno-auditor pass, and a review before the first deploy | P2 |
| Report queue filled by throwaway wallets | as today (5 per wallet, 5,000 open). Not made worse | existing tests |
| Upper-case bech32 addresses (review M4): the chain maps them to the same account, realms compare strings | `role.Canonical` (valid and lower case) at every address argument: role offers, `SetTreasury`, `AssignArtist`, splits, the picker and ref of a tip (an upper-case one counts as none), `TransferTicket` and `nft.Transfer`, home's listener route and `who()`. `data.IsGnoRadio` lower-cases its input | role `TestCanonical`, data `TestIsGnoRadio`, catalog `TestUpperCaseAddresses`, tickets `TestTransferUpperCase`, home `TestUpperCaseAddress` |
| A forged door QR (review M5, final audit Y1): ticket id and holder are public | the door page shows a fresh code after each scan; `CheckIn(ticketID, code)` needs `Present(ticketID, code)` signed by the ticket's current holder with that code in the last 10 minutes, so a copied QR gets another code and the holder's Present does not admit it; door open from 12 h before to 12 h after the start (L1) | tickets `TestPresentThenCheckIn` |
| Domain verification proves a host, not an identity (review M6, L3, L6) | `ProofHost` is shown next to every ✓ (home, the artist JSON for the app), pending claims are listed (`PendingClaims`, home's moderation page) during their 72 h, and a curated import cannot be verified on its source site | catalog `TestPendingClaimsAndProofHost`, `TestCuratedNotRobotVerifiable`, home `TestProofHostAndPendingClaims` |
| Look-alike and staff names (review L4, L5) | the skeleton folds 0/1/3/4/5/7/9, u (to v), rn, vv and cl; names holding GnoRadio, moderator, moderation, treasury, administrator or gnoland, or the word admin, staff or official, or a name or word starting with Adena or Audius ("AdenaWallet", "Ade-na"), are refused; Pasadena, La Cadena and Claudius pass. The skeleton is a storage key (`catalog/names`): freeze it at the first public deploy | catalog `TestReservedNames`, `TestSkeletonMoreLookalikes` |
| A track published for another wallet, or kept off the air | catalog `PublishFor`, `ImportFor`, `EditFor` admit only the radio writer; radio passes the signer (`MsgCall` for publish and edit), never an argument; the radio ingests the track in the same transaction and refuses to publish past a gap (it would misfile Main) until `Sync` | catalog `TestTrackWritesRadioOnly`, radio `TestPublishJoinsStations`, `TestSyncCatchesUp`, `TestGenreEditLeavesNoOrphanSlot` |
| Sponsored-pick farming by a low-gas script | each budget has a daily cap (`defaultPerDay` = 10 unless the artist sets 1 to 100), plus three sponsored picks a wallet a day, one per artist. **Residual, accepted**: a script paying less gas than the 0.2 GNOT refund keeps about 0.05 to 0.1 GNOT a pick within those quotas | catalog `TestDefaultDailyCap`, `TestSponsoredPickCaps` |
| Wash tipping (review L9): an artist tips their own track from a second wallet with supportPct 0 | **accepted**: the coins come back, so only rankings move (track tips, supporters, top artists, the alt's fan rank), for the cost of gas; wallets cannot be tied together on chain. Rankings are labelled as tips received, not listeners. A tipper's own rank counts only what reached the artist side (L10), and like/unlike cycles keep no early badge (L11) and take one feed slot (L8) | catalog `TestTipRankCountsNet`, `TestUnlikeDropsEarlyBadge`, `TestLikeCyclingFeed` |

Process: after each phase, run a **gno-auditor pass** (agent type
`gnomcp:gno-auditor`) on the packages that changed, fix every RED, and either
resolve or document every YELLOW before the next phase starts.

Added in P5, from the P3–P4 audits:

| Threat | Mitigation | Test |
|---|---|---|
| A sponsored reservation paid from another funding: the vault pools an artist's holds per day, and a budget that goes back to an earlier funder within the 7-day claim window kept that funder's name | each budget has a funding generation (`catalog/budgets`), bumped when another wallet funds it (the previous one is refunded with its holds). `PromoReserve` returns it, radio stores it with the pick, and `PromoClaim`, `PromoClaimable` and `PromoRelease` act only in that generation | catalog `TestPromoBackToSameFunder`, radio `TestSponsoredBackToSameFunder` (both fail without it) |
| TipOnAir self-dealing: a listener tips and steers the promo share back to themselves | the promo share is opt-in (0% until the artist sets 0–20%). A tipper never pays it to the same wallet, in any spelling: not as picker, not as referrer, and nothing at all when they picked the track on air themselves. **Residual, accepted**: a second wallet (as referrer, or picking first) can still collect up to the artist's chosen share; the tipper's fan rank counts only the artist side; wallets cannot be tied together on chain, which is why the share is the artist's opt-in | catalog `TestRadioTipNoShare`, radio `TestTipOnAirOwnPick` |
| Cancelled or hidden concerts push past concerts off the site (home scanned 300 ids) | home pages past concerts from `tickets/upcoming` (`tickets.PastEvents`): cancelled and hidden concerts are not in it. `RefreshArtistPast` (anyone, 50 a call) takes a hidden profile's past concerts out of it too, as `RefreshArtist` does for future ones | home `TestPastConcertsSurviveCancelSpam`, tickets `TestPastEventsAndRefresh` |
| A later release writes values home/v1 renders raw | home re-checks what it puts in links and code spans: `sanitize.URL`, `sanitize.InlineCode`, plain license ids, valid addresses only, the app URL re-validated on read | home `TestTrackActionsAndTipOnAir` |
| A paused catalog blocks radio moderation of sponsored slots (`PromoRelease` writes catalog data) | while the catalog is paused, the radio drops slots without calling it: each hold lapses back to its budget by itself | radio `TestDropSponsoredWhileCatalogPaused` |
| The permanent NFT realm tied to a replaceable one | `tickets/nft` imports no versioned realm: the artist line reads the catalog's artist heads in `data` through frozen constants, like the tickets records | nft `TestArtistFromCatalogRecords` (agrees with catalog's readers), `TestTicketGolden` |

Also added in P5: **a malicious release takes tickets.** Mitigation: the permanent `tickets/nft` realm
mints to, and moves from, only the wallet that signed the transaction, so a rogue tickets release
cannot move the tickets of a holder who signs nothing. It does not prove the holder asked for that
move (review L2): a holder who signs any call to the rogue release can lose every ticket they hold,
since the NFT realm sees only the tickets realm and the signer, not the call. The 72 h window, and
the guardian's cancel, are the protection there. Tested in tickets/v1's threat tests and nft
`TestOnlyTicketsWriter`.

## 9. Plan

Done: phases P1 to P6 (`p/role`, `p/store`, `p/blocks`; `data`; `catalog/v1`;
`radio/v1`; `tickets/nft`, `tickets/v1`, `home/v1`; v0 removed and the release
rehearsed in `home/v1/filetests/z_rehearsal_filetest.gno`). Still due before a
public deploy: the full audit, the release checklist's no-`private` check (8), and
deploying `data` and the v1 realms under a namespace only its owner can publish to.

## 10. Decisions on the open questions

1. **Tickets stay real GRC721 NFTs** (option b). A small permanent
   `gnoradio/tickets/nft` realm (P5) holds a `grc721` token and mints and transfers
   only when its caller is `data.Writer("tickets")`. It survives releases like
   `data`, so no ledger migrates, and wallets list the tickets. The first-ticket
   deposit stays near today's. P2 leaves room for it: `Writer` is a plain read
   the NFT realm can check, `IsGnoRadio` counts the NFT realm (it never receives a
   vault payout), and `Propose` refuses its path as a writer. FEATURES keeps
   "tickets (NFTs)".
2. **Owner plus guardian.** The owner (the user's own address at first, a
   multisig recommended) proposes and cancels releases, pauses and resumes,
   passes the role on in two steps and can renounce. The guardian, the deployer at
   init, can only pause (while an owner exists) and cancel a pending release. Rule
   for changing the guardian: **the current guardian offers, the new guardian
   accepts; the owner can only replace it 144 h after announcing it, and the
   guardian cannot cancel that** (review M3). A stolen owner key alone therefore
   cannot remove the guardian quickly, and a stolen guardian key cannot veto
   forever (section 8).
   Right after deploy, owner and guardian are the same address: hand the guardian
   role to a separate cold key or multisig before any public use.

- **Ticket NFTs (P5):** `tickets/nft` is permanent and holds the ticket art and the frozen
  event/ticket record layout, since it cannot call the versioned rules realm. For the same
  reason it reads the artist's name and hidden flag from `catalog/artists` in `data`
  (chunks of 8 heads, field 0 hidden, field 6 name): every catalog release keeps that
  layout anyway, since releases share the records instead of copying them. A consequence:
  wallets' generic GRC721 transfer fails on these tickets (only a transaction the holder
  signed, through the current tickets rules, moves them; see section 8 for what that does
  not prove).
3. **Sponsored picks: a funding generation** (P5, auditor's case of a budget that goes back
   to the same funder within 7 days). See section 8.
4. **TipOnAir self-dealing** (P5, auditor YELLOW): the referrer's share is not paid when the
   referrer is the tipper or when the tipper picked the track on air; the artist's promo share
   defaults to 0% (opt-in, 0–20%). A second wallet can still collect it: accepted, see section 8. The app's About page says so; its tip-sheet preview
   (`app/src/lib/incentives.ts`, `promoSplit`) applies the same rules, the self-pick one
   included (P6).
5. **One base-64 codec** (P5): `p/store` exports `Digits`, `Num`, `Fixed` and `AppendFixed`;
   radio and the `p/blocks` codec use them. Radio keeps a decode table built from
   `store.Digits` for the digits its hot loops read in place (a call per digit costs about
   1% of a pick).
