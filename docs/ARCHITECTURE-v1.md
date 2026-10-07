# GnoRadio v1 architecture: data apart from rules

Status: design, not implemented. Target: gno.land v1.5.0 (onyx and mainnet).
Prototype and measurements: `split-proto/` in the session scratchpad (section 6).

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
and can be renounced.

## 1. Layout and paths

```
gno.land/p/<ns>/gnoradio/role/v0      two-step owner role, pinned to its realm (new)
gno.land/p/<ns>/gnoradio/store/v0     codecs only: Rec/Field/With, id lists, Pad, page rows, Ops (sparse trees removed)
gno.land/p/<ns>/gnoradio/blocks/v0    rotation as a codec over header/group/block strings (no persisted List)
gno.land/p/<ns>/gnoradio/{text,svg,safe}/v0   unchanged

gno.land/r/<ns>/gnoradio/data         the permanent data realm (no version)
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
- The current `r/gnoradio/{catalog,radio,tickets,home}/v0` realms (self-contained
  state) are retired in phase 6. Release 1 is a new deployment, not a migration.

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
4. `Cancel(cur)`. Owner. It drops a release that is not yet in force.
5. `Pause(cur, role, on)`. Owner. `role` "" means every role. It stops that role's
   writes and vault operations at once. Reads and `VaultWithdraw` continue. Resume
   restarts the same writer at once, since no new code runs. Unlike gnogolf, a pause
   does not drop the pending release: cancelling it is a separate decision.
6. `Renounce(cur)`. Owner. Writers can never change again and nothing can be
   paused. It is refused while any role is paused, because that role could then
   never write again. It drops any release not yet in force.
7. Owner transfer: `Offer` / `Accept` / `Renounce`, through `p/role`.

Reads: `Writer(role)`, `Writers()` (JSON: writer, paused and proposed per role,
plus `at` and the owner), and `IsGnoRadio(addr)` (any current, proposed or past
writer, or `data` itself).

### API

All arguments and results are strings and ints. No pointer, slice or map ever
crosses the boundary in either direction (see 5, readonly taint).

| Call | Who | Notes |
|---|---|---|
| `Get(c, k) (string, bool)`, `Has`, `Size(c)` | anyone | non-crossing reads |
| `Index(c, k) int` | anyone | rank of `k` in `c`, O(log² n). Counts a key range without a counter |
| `Page(c, start, end, limit, reverse) string` | anyone | ≤ 100 rows, encoded `len:key len:value`. One call per page |
| `PageAt(c, offset, limit, reverse) string` | anyone | offset pages via the tree's sizes |
| `Set(cur, c, k, v)`, `Remove(cur, c, k) bool` | writer of `c`'s role | key 1–128 B, value ≤ 16 KiB |
| `Batch(cur, ops []string)` | writer | ≤ 64 ops of `set/del, c, k, v`. Strings are copied, the slice is not kept |
| `Make(cur, c)` | writer | a new collection under its own role. ≤ 32 per role, name ≤ 32 B |
| `Vault*` | see 4 | |

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

- **Dense id data is chunked.** Tracks, artists, albums and tickets: 16 records per
  key, `Pad(id-1 / 16)`. Each new key costs roughly 400 B of object overhead,
  chunking pays it once per 16 ids. Measured: one key per track meant 1,233 B per
  publish, chunks mean 333 B.
- **Address-keyed data has one key per address** (users, curators, owners, budgets).
- **Growing id sets are packed lists per range of 512 ids** (likes per listener,
  genre index), as today.
- **Ordered indexes are key encodings**: zero-padded numbers, `key64(start)` for
  time. Paging and counting use `Page` and `Index`, never a stored counter list.
- **Each entrypoint writes a key at most once.** It loads what it needs, computes
  the final values, then writes them. It uses `Batch` once it writes three or more
  keys.

Limits: key 128 B, value 16 KiB (the longest value is a station schedule: 120 slots
at ~110 B each), `Batch` 64 ops, `Page` 100 rows, 32 collections per role. Every
call is bounded, and none can store or iterate without limit.

## 3. State mapping

Records keep today's `store.Rec` layouts and field order, so `records.gno`
decoding is reused. `P(n)` is `Pad`: 8-digit zero-padded. `T(t)` is a 12-digit unix
time. Each role's collections are written only by that role's current rules realm.

### catalog (writer: `catalog/vN`)

| Today | Collection / key → value |
|---|---|
| `artists` Seq(16) | `catalog/artists` P((id-1)/16) → 16 artist heads (Rec of Recs) |
| `artistLists` Seq(8) | `catalog/alists` P(id) → Rec(track ids, album ids) |
| `byOwner` Map | `catalog/owners` addr → artist id |
| `names` Map | `catalog/names` skeleton → artist id |
| `tracks` Seq(16) | `catalog/tracks` P((id-1)/16) → 16 track records |
| `byGenre` [21]IDs | `catalog/genres` P(g)/P(id>>9) → packed ids. Per-genre counts live in `catalog/meta` |
| `albums` Seq(16) | `catalog/albums` P((id-1)/16) → 16 album records |
| `playlists` Seq(16) | `catalog/playlists` P(id) → record (up to 1.8 KB each, so not chunked) |
| `users` Map + `userRecs` Seq | `catalog/users` addr → Rec(follows, tipped, tipped ids, playlists, reports). The index indirection goes |
| `likeSets` Map | `catalog/likes` addr/P(id>>9) → packed ids. The count and newest-first page come from one prefix `Page` (no more loop over every range of the catalog) |
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
| `claims`, `proofs` avl | `catalog/claims` P(artist) → record. `catalog/proofs` P(artist) → url |
| `admin` | `p/role` in the rules realm, mirrored to `catalog/config` "admin" |
| `frozen, successor, radioRealm, siblingRealms, verifySig` | removed (7) |

### radio (writer: `radio/vN`)

| Today | Collection / key → value |
|---|---|
| `stations[i]` header (epoch, live, ring, rotation n/total/group totals) | `radio/stations` P(i) → Rec |
| `stations[i].schedule` []Slot | `radio/sched` P(i) → packed slots (≤ 120). One read and one write per pick, as today's slice rewrite |
| `stations[i].rot` blocks.List | `radio/rot` P(i)/b/P(block) → ids+durs (768 B). `radio/rot` P(i)/g/P(group) → block sums |
| `homes` Seq(128) | `radio/homes` P((id-1)/128) → 128 entries |
| `synced, setGenre, setLeft, cursor[21]`, activity head | `radio/meta` "flow" → Rec |
| `curators` Map | `radio/curators` addr → record (today's 13 fields) |
| `tops` [23]weekTop | `radio/tops` P(st+1) → Rec(week, packed ranks) |
| `lastPick` Map | `radio/lastpick` P(st) → fixed-width entries |
| `dropped` Map | `radio/dropped` P(st)/P(track) → "1" |
| `noteReports, muted, strikes` | `radio/notes` P(st)/T(start). `radio/muted` addr. `radio/strikes` addr |
| `sponsor` Map | `radio/sponsor` P(st)/addr → record |
| `activity` ring | `radio/activity` P(0..63) |
| `noteKey`, admin mirror | `radio/config` |
| `frozen, successor, verifySig, radioTip, promo*` seams | removed |

`p/blocks` keeps its algorithm (Find, PrefixBefore, SetDuration, Append). It now
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
| `tickets` Seq(16) + grc721 ledger | `tickets/tickets` P((id-1)/16) → 16 Rec(event, serial, attended, **holder**) |
| `owned` Map | `tickets/owned` addr → packed ids |
| `buyers` Map | `tickets/buyers` P(event)/addr → count |
| `attended` avl | `tickets/attended` addr → count |
| `nEvents, nTickets, serviceFee`, admin mirror | `tickets/meta`, `tickets/config` |
| `ticketTok, ticketLed, tokSeq`, `artistVerified/artistVisible` seams | removed (open question 1) |

### home (writer: `home/vN`)

`appURL`, `contact` → `home/config`. These remain gated on the catalog admin, as
today. `onAirNote` and `tippable` (test seams) are removed.

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
| `VaultCredit(cur, acct, funder, amt)` | writer of `acct`'s role | `banker.GetCoins(data) ≥ VaultTotal + amt` must hold first. The rules realm sends the coins it received before crediting |
| `VaultHold(cur, acct, amt, day)` | writer | requires `free ≥ amt` |
| `VaultRelease(cur, acct, amt, day)` | writer | |
| `VaultPay(cur, acct, to, amt, day)` | writer | takes from a live hold. `to` must not satisfy `IsGnoRadio` |
| `VaultRefund(cur, acct)` | writer | pays the whole balance to the funder and drops its holds (the profile changed hands) |
| `VaultWithdraw(cur, acct)` | **the funder**, `cur.Previous().Address()` | pays out `free`. Not gated by writer, pause or renounce |
| `VaultInfo(acct)`, `VaultTotal()` | anyone | `PromoHeld()` and `PromoJSON` read these |

Guards:

- Every payable entrypoint checks `cur.Previous().IsUserCall()`, then a single
  `ugnot` coin with the exact or bounded amount from `unsafe.OriginSend()`.
- Every other entrypoint calls `noPayment()`.
- A rules realm ends every transaction holding 0 ugnot, so its balance check is
  `GetCoins(self) ≥ amount`. Today the catalog checks `promoHeld + total`. The new
  check is simpler and stricter.
- `TipOnAir`: radio forwards the coins to `chain.PackageAddress(data.Writer("catalog"))`
  and calls `catalog.RadioTip(cross(cur), …)`. catalog checks
  `cur.Previous().PkgPath() == data.Writer("radio")`. No `radioRealm` setting is left.

What still protects funders against a malicious release: the 72-hour public delay
(events `WriterProposed` and `ReleaseReady`) during which `VaultWithdraw` works, and
the fact that a pause never blocks withdrawal. A writer can only reach the coins
through holds, and only after its delay. A hard pause longer than 7 days lets
uncollected sponsored refunds lapse back to the artist's budget: the money is not
lost.

## 5. Roles and powers

`p/role` keeps `home` (the realm that created the role), `owner` and `pending`.
Every method takes `_ int, rlm realm` and first checks
`rlm.IsCurrent() && rlm.PkgPath() == home`. The `_ int` is not decoration: v1.5.0
treats a method whose first parameter is a `realm` as crossing, and refuses that in
`/p/` (verified in the prototype).

| Realm | Role | Can | Cannot |
|---|---|---|---|
| `data` | owner (multisig recommended, open question 2) | propose, cancel, pause, resume, offer, renounce | write data, touch the vault |
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

**No write queue.** Per-write cross-calls are cheap: 2 direct writes cost less than
gnogolf's queue and overlay (4.21M against 4.28M). The plan is: load the state once,
compute the final values, write each key once, and use `Batch` from three writes on.
There is no read-back overlay, and so no "walk after write" failure mode
(gnogolf's `view.clean` panic). `p/store` gains a pure `Ops` builder (`[]string`)
for `Batch`.

## 7. Dead code to remove

| What | Evidence |
|---|---|
| catalog `UsersPage, LikesPage, TippedPage, SupportersPage, PromoPage`; radio `RotationPage, StatePage, StationState, FlowState` | migration readers. Only tests call them (script: no use in `gno/`, `app/`, `tools/`). No migration remains |
| catalog `SetRadioRealm, RadioRealm, radioRealm, SetSibling, SiblingRealms, siblingRealms, addSibling` | replaced by `data.Writer` and `data.IsGnoRadio`. Only tests call `SetRadioRealm` and `SetSibling` |
| `SetSuccessor/Successor/successor` (catalog, radio), `Freeze/Frozen/frozen/notFrozen` (catalog, radio, tickets) | replaced by the release and `Pause`. home reads `catalog.Successor/Frozen` → `data.Writers()` |
| `TransferAdmin` ×3 | replaced by the two-step `p/role` |
| test seams: catalog `verifySig`; radio `verifySig, radioTip, promoReserve, promoClaim, promoRelease, promoClaimable`; tickets `artistVerified, artistVisible`; home `onAirNote, tippable` | function-valued globals (Class 4 latent, security.md). Replaced by the dev-admin fallback, Ed25519 test vectors generated by the robot's signing code (`crypto/ed25519` in Gno has only `Verify`), and `testing.NewCodeRealm(writer)` to seed data |
| `p/store` `Seq, Map, IDs, tree, node, walk` (~300 lines) | no realm keeps typed state once everything is in `data` |
| `blocks.List` as a persisted object | becomes a codec over strings |
| tickets `grc721`, `seqid`, `ticketTok/ticketLed/tokSeq`, `type event struct{Event}` | no exported grc721 surface. Only `TicketOwner` and `TokenURI` are read (open question 1) |
| catalog `ProofLine` | not used by the realms, the app or the robot (the app builds the line itself) |
| catalog `promoHeld` | `data.VaultTotal()`. `PromoHeld()` stays as a reader for the FEATURES invariant |

## 8. Security: threat model and tests

| Threat | Mitigation | Test (phase) |
|---|---|---|
| A realm or account writes data it does not own | `gate`: the immediate caller's pkgpath must equal `writer[role of c]`. Accounts, MsgRun and the owner never pass | `TestOnlyWriterWritesItsRole` (P2, prototype passes) |
| catalog writes radio's collections | the role comes from the collection prefix, checked for every op of a `Batch` | same test, `Batch` case |
| A swap without the delay | `DELAY` is a constant. The clock starts when every proposed realm said `Ready`. Any `Propose` resets it. Only proposed realms call `Ready`, once | `TestReleaseTakesOverAfterDelay` (P2, passes): an early write is refused, the switch happens after `SkipHeights` |
| **A private package re-uploaded after the delay** (`private = true` packages can be re-uploaded) | cannot be checked at runtime. Release checklist: the proposed `gnomod.toml` has no `private` or `replace`. Rehearse a re-upload on a devnet (if it is refused there, note it) | P6 release rehearsal |
| Owner key stolen: a malicious release | 72h public window, `VaultWithdraw` stays open, the owner should be a multisig, plus an optional guardian (open question 2) | P2 vault tests under a pending release |
| Pause misused | owner only. Never blocks reads or `VaultWithdraw` | `TestPauseResumeRenounce` (P2, passes), `TestWithdrawWhilePaused` (P2) |
| Renounce bricks GnoRadio | refused while any role is paused. Drops a pending release | `TestPauseResumeRenounce` |
| Stale or forged realm value used for authority (Class 2) | `p/role` checks `rlm.IsCurrent()` and `home`. Every entrypoint uses the runtime-current `cur.Previous()`. No `caller address` parameter carries authority | `TestRoleRefusesStaleRealm` (P1, passes), `TestRoleFromForeignRealm` (P1) |
| A leaked `/p/` pointer used as a mutator (D2 borrow) | `*Role` and `*bptree.BPTree` sit in unexported vars and are never returned. `Role` methods refuse foreign realms even if the pointer leaks. `data` returns only strings and ints | grep lint in CI: no exported var, no exported func returning a pointer (P1–P5). Foreign-realm test (P1) |
| Readonly taint across the boundary | rules read only strings (immutable). `Page` returns one string. `Batch` copies the strings and never keeps the caller's slice | `TestBatchDoesNotAliasSlice` (P2): mutating the slice after `Batch` changes nothing |
| Function or interface values from callers (Class 3/4) | none in any API. Seams removed | grep check (P6) |
| Payment bypass through MsgRun | `IsUserCall` plus an exact `OriginSend` on every payable path. `noPayment()` elsewhere | `TestPayRefusesMsgRun` per payable entrypoint with `NewCodeRealm` and an ephemeral caller (P3–P5) |
| Coins stuck or stolen | vault invariant `banker(data) ≥ VaultTotal`, checked before each credit and asserted after each test. Rules realms end every transaction at 0 balance. `VaultWithdraw` for the funder only | `TestVaultInvariant`, `TestWithdrawFunderOnly`, `TestRulesHoldNothing` (P2–P3) |
| Robot certificate replay | bound to chain id, data path, wallet, target and expiry. Short life. Rotating the key voids pending claims | `TestCertOtherWallet/OtherStation/Expired/OtherDeployment` with vectors (P3–P4) |
| DoS through big keys or values, or many ops | key ≤ 128 B, value ≤ 16 KiB, `Batch` ≤ 64, `Page` ≤ 100, ≤ 32 collections per role. Per-user lists capped (a new 1,000-follow cap) | `TestLimits` (P2), cap tests (P3) |
| Unbounded loops as data grows | all walks are paged (≤ 100). Upcoming scan ≤ 1,000. Like counts walk the user's own ranges only (≤ catalog/512 keys) | gas filetest budgets at 5k and 20k tracks (P3–P5) |
| Gas griefing (making someone else's action expensive) | fixed-size hot records (activity ring, 10-entry tops, early badges ≤ 10, schedule ≤ 120). A user's lists only cost that user. Leaf splits are O(log n) | the same filetests, with a heavy-user seed |
| A bug in `data` itself (it can never be replaced) | ≤ 500 lines, no business logic, frozen API, a fuzz-style test of the row codec and `Batch`, a gno-auditor pass, and a review before the first deploy | P2 |
| Report queue filled by throwaway wallets | as today (5 per wallet, 5,000 open). Not made worse | existing tests |

Process: after each phase, run a **gno-auditor pass** (agent type
`gnomcp:gno-auditor`) on the packages that changed, fix every RED, and either
resolve or document every YELLOW before the next phase starts.

## 9. Plan

Each phase adds new packages next to the current v0 realms, so v0 and its tests stay
green until phase 6 removes them.

| Phase | Content | Tests | Size |
|---|---|---|---|
| P1 | `p/role`. `p/store` codecs (`Pad`, rows, `Ops`). `p/blocks` codec form (the old `List` kept until P6) | role: offer/accept/cancel/renounce, stale and foreign `rlm`. blocks: same results as the old List over random ops | ~350 lines + ~400 test |
| P2 | `r/<ns>/gnoradio/data`: collections, reads, writes, release, pause, renounce, `IsGnoRadio`, vault | protocol tests from the prototype, limits, vault invariant, batch aliasing, withdraw while paused or renounced. **Auditor** | ~500 + ~600 test |
| P3 | `catalog/v1` on `data` (records chunked, likes in ranges, vault budgets, config, admin mirror, dev admin) | port every catalog v0 test (seams removed, vectors added). Gas and deposit filetests with goldens: like ≤ 5.5M and ≤ 800 B, publish data ≤ 6.0M, 20 tracks ≤ 9M, at 5k and 20k tracks. **Auditor** | ~1,800 lines touched |
| P4 | `radio/v1` (stations, schedule, rotation codec, curators, sponsor through catalog and vault) | port the radio tests (seams removed). Pick and sponsored-pick deposit goldens. **Auditor** | ~1,800 touched |
| P5 | `tickets/v1` (holder in the ticket record, no grc721), `home/v1` (reads `data.Writers()`, settings in `data`) | port the tests and the home render goldens. First-ticket deposit golden. **Auditor** | ~900 touched |
| P6 | Remove v0 and dead code (7). Port `devseed`. App `realms.ts` paths (optional: resolve them from `data.Writers()` once, so future releases need no app change). Update FEATURES, DEVELOPMENT, SPEC and About. Gnodev end-to-end (139 checks). **Release rehearsal**: deploy v1, propose a v2 copy, `Ready`, skip 72h, writes switch, v1 refuses, every byte of data is unchanged, pause/resume, withdraw. **Full audit** | `npm run check`, `npm run e2e`, rehearsal script | ~600 + docs |

Risks:

- **Publish gas +8%.** Mitigate with one `Batch` per publish and by never decoding
  a whole chunk (`store.With` on the chunk).
- **The data realm is final.** Keep it small. Freeze its API before P3 and review it
  once more after P5, before any public deploy.
- **The radio port is the hardest.** Schedule and rotation are ported mechanically;
  the existing 1,800 lines of radio tests are the oracle.
- **The 16 KiB value cap and schedule size.** Assert worst-case encodings in tests:
  120 slots with 40-character notes.
- **Package size affects every transaction's gas** (measured: a larger proto catalog
  file added ~30k). Keep `home` (55 KB) out of the write paths, which it already is.
- **`private` re-upload** (8). It goes on the release checklist.

## 10. Open questions (product)

1. **Tickets as GRC721.** Today's tickets are minted on a `grc721` ledger that lives
   in the tickets realm, so it cannot survive a release without a migration. Choose
   one:
   - (a) Data-native ownership with GRC721-shaped reads (`OwnerOf`, `BalanceOf`,
     `TokenURI`). Simplest, and cuts the ~6 KB per ticket of ledger deposit (first
     ticket today 0.8–1.1 GNOT). Wallets will not list them as GRC721.
   - (b) A small permanent `tickets/nft` realm holding a real `grc721.Token`, minted
     and transferred only by `data.Writer("tickets")`. Real NFTs, a second permanent
     realm, and today's deposit.

   The FEATURES text "tickets (NFTs)" depends on this choice.
2. **Who holds the data owner role**, given it can replace every rule after 72 hours:
   the user's own address (current practice), a multisig, or the owner plus a
   separate guardian that can only `Pause` and `Cancel`? A guardian is about
   20 lines in `data` and closes the "owner key stolen" path. It is cheap to add
   now and impossible after deploy.
