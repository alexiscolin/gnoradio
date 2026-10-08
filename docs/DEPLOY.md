# Deploying GnoRadio

How GnoRadio goes on a public chain, who holds which key, and what to do once it is live.
Nothing is deployed yet. The design behind it (a permanent data realm, rules realms that can
be replaced, an owner and a guardian) is in [ARCHITECTURE-v1.md](ARCHITECTURE-v1.md).

## Where it lives

The packages go under the deployer's gno.land name (onyx: next to gnogolf):

```
gno.land/p/nym-alexiscolin000/gnoradio/...           pure packages (text, svg, store, safe, blocks, role)
gno.land/r/nym-alexiscolin000/gnoradio/data          every record and the promo vault (permanent)
gno.land/r/nym-alexiscolin000/gnoradio/tickets/nft   the ticket NFTs (permanent)
gno.land/r/nym-alexiscolin000/gnoradio/{catalog,radio,tickets,home}/v1   the rules, release 1
```

`tools/deploy/stage.py` copies `gno/` with every `gno.land/{p,r}/gnoradio/` path rewritten to
that namespace (no tests, no devseed); `tools/deploy/test_stage.py` checks it. `tools/deploy/deploy.sh`
stages, lints every package with the chains' release (gno v1.5.0) and refuses to submit if one
fails, then submits each package in order with your gnokey key and waits for it to be enabled
before the next: `p/text`, `svg`, `store`, `safe`, `blocks`, `role`, then `r/data`, then
`catalog/v1`, `tickets/nft`, `tickets/v1`, `radio/v1`, `home/v1`.

```sh
tools/deploy/deploy.sh --dry-run onyx <your gnokey key name> nym-alexiscolin000   # checks, prints, signs nothing
tools/deploy/deploy.sh onyx <your gnokey key name> nym-alexiscolin000
```

Both chains run `inert` code submission: a submitted package is parked until an approver
enables it, and enabling type-checks its imports, hence one at a time. The script is
resumable: run it again and it skips what is live and waits on what is parked;
`--resubmit` sends a parked package again after a fix (only the same key may).

Deploy release 1 right after `data`: from its first block, `data` names
`<namespace>/{catalog,radio,tickets,home}/v1` its writers, so publish them before anyone else
can. The app then builds with `VITE_GNORADIO_NS=nym-alexiscolin000/gnoradio` (Netlify
environment, applied to the functions too, so the robot reads the same paths).

## Launch policy: free and non-commercial

Decided on 2026-10-08. GnoRadio launches free and non-commercial: the operator takes no fee.

- Ticket service fee 0: leave `tickets.SetServiceFee` unset (the realm's default is 0).
- No support fee to the operator: no "+10%" on tips and no direct support. Tips and ticket
  prices go 100% to the artists, as always.
- Listeners and artists still pay their own transactions' gas: that is the chain, not a fee.
- This allows CC BY-NC and BY-NC-SA music next to CC0, BY and BY-SA. ND stays excluded (jingles
  and crossfades could count as adaptation).

Done to launch this way:

- [x] The app still offers the "+10%" and direct support and describes a ticket service fee
      (`SupportSheet`, `lib/features.ts`, About, Legal): hide them and say "no fee" while no
      treasury and no fee are set.
- [x] The catalog realm limits curated imports to CC0, BY and BY-SA (`catalog.gno`, `licenses`):
      widen it to BY-NC and BY-NC-SA, and let `tools/curate` keep them.
- If fees are ever turned on, every NC track must be hidden first (its record stays on chain).

What the launch catalog can draw on, given that its records are written to a public chain for
good:

- **Audius and Jamendo: as pointers only.** Their API terms allow session caching only, so the
  chain keeps no title, name, cover or link of theirs: just what the radio needs (the platform's
  track id `audius:<id>` / `jamendo:<id>`, genre, duration, licence) and an artist record keyed
  by the platform id (`audius-user:<id>`, `jamendo-artist:<id>`), with no name. The app reads
  titles, names and covers live through `/api/meta` (ARCHITECTURE section 6, "Pointers"). An
  artist opting out is a `HideArtist`; a platform ending GnoRadio's access is
  `catalog.HideSource("audius" | "jamendo", from, 50, reason)`, repeated until it returns 0.
  A claimed pointer's owner may fill in their name and titles (their consent, on chain).
  Build a batch with `tools/curate/pointers.py`, import it with `tools/deploy/import.py`.
  Jamendo is free for non-commercial use only: keep the no-fee launch while Jamendo tracks
  are in.
- **Artists from anywhere** may publish on GnoRadio themselves (their own records, their own
  consent).
- **Sources without API terms** (archive.org, artists' own sites, open datasets): fine, under
  their CC licence, with attribution.

### Turning fees on later

1. Hide every NC track first, with the admin `HideTrack` per track. Nothing enforces this:
   `SetTreasury` does not check for visible NC tracks (a counter kept on import, hide and
   artist-hide would cost gas on every hot path), so the order is an operator rule. A bulk
   hide-by-licence can come as a new release when needed.
2. Set the treasury first (`catalog.SetTreasury`). A ticket fee needs it: `tickets.SetServiceFee`
   alone changes nothing and raises no error, because the fee only applies while a treasury is
   set. A fee stored earlier switches on, with the price plus fee to attach, the moment the
   treasury is set: quote it to buyers first.
3. Then set the service fee (`tickets.SetServiceFee`).
4. The app and gnoweb show the fee features again by themselves.

### Re-importing a pointer

`ImportTracks` refuses an Audius or Jamendo track already imported (key `track-<audio>` in
`catalog/names`, written by this release: pointers imported before it have none, fine on a
fresh chain). To import one again after a wrong import: `HideTrack`, then
`catalog.ReleaseName("track-audius:<id>")` (admin; allowed only once the track is hidden).
`ReleaseName("audius-user:<id>")` frees a hidden pointer artist's key the same way.

## Costs

Measured on the v1 devnet, gas price 1 ugnot per 1,000 gas and 100 ugnot per stored byte on
both chains (2026-10-08):

- Submissions: 12 × 0.2 GNOT at most = 2.4 GNOT.
- Storage deposits, charged when each package is enabled: about 91 GNOT for the code
  (`safe/v0`'s word list alone 30 GNOT, `catalog/v1` 23, `radio/v1` 12.5), a few more for
  `data`'s first records: budget **100 GNOT**. A deposit is locked, not spent: it comes back
  if the storage is freed. Each submission allows up to 100 GNOT (`-max-deposit`); only what
  is stored is taken.
- Setup calls after the deploy (robot keys, treasury, hosts, app URL, fee): well under 1 GNOT.
- The launch catalog, paid by the operator, in batches of 25 (`radio.ImportTracks`). Simulated
  on the 5k-track devnet: one line 60.8M gas, 25 lines 735M, so about 33M per call and 28.1M per
  track; each track stores about 360 bytes (its record and its genre station; an import skips New
  this week). `import.py` asks 1.5x the measured gas and prices it at the live gas price plus 20%
  (the whole offered fee is charged): about 1.32 GNOT of fee per full batch, so about 0.053 GNOT
  of fee + 0.036 GNOT of deposit = **about 0.09 GNOT a track**, plus about 0.11 GNOT per new
  artist. About **110 GNOT for the ~1,200 tracks SPEC §5 sources**, about **145 GNOT for 1,600**
  (80 per station, the ceiling `tools/curate` aims at), **about 445 GNOT for 5,000**.
  `tools/deploy/import.py --dry-run` prints the exact figure first.

Both networks start from an empty `data` realm. The radio's flow record layout (`radio/meta
"flow"`) changed during v1's development, so never point these realms at a `data` realm
seeded by an earlier build (a local devnet included): deploy fresh, or restart the devnet.

## Onyx (onyx-1), step by step

1. Toolchain: `~/.cache/gno-toolchains/onyx-v1.5.0/gno` (or `GNO=… GNOHOME=…`), and gnokey
   with your key. Your address holds about 930 GNOT on onyx: enough.
2. `tools/deploy/deploy.sh --dry-run onyx <key> nym-alexiscolin000`, then without `--dry-run`.
   onyx's approver is automatic: each package is live seconds after its submission; one still
   parked after 3 minutes failed its checks (the script says so).
3. Setup calls ([After the realms are live](#after-the-realms-are-live)): through a gnomcp
   session (`gno_session_propose` with your address as master; you approve it once with your
   gnokey), or with gnokey or Adena directly.
4. Netlify site for onyx ([Netlify](#netlify)), `VITE_NETWORK=onyx`.
5. **One test concert, onyx only** (never on mainnet), to try tickets end to end: NFT, service
   fee, door code and check-in. The gnomcp agent key on the `testnet` profile plays the artist:
   1. agent key: `catalog.RegisterArtist("Testnet Band", "A test profile on onyx, not a real artist.")`;
   2. you, as catalog admin: `catalog.Verify(<its id>, true)` (paid tickets need a verified artist);
   3. agent key: `tickets.CreateEvent("Test concert (onyx)", "Testnet venue, Paris", "", "<a date a few weeks ahead> 20:00", "1", 50)`;
   4. buy a ticket from another account, show it at the door, and check it in from the agent key
      (the artist).

   Cancel it with `tickets.CancelEvent` (agent key) or hide it with `tickets.HideEvent` (admin)
   once the tests are done.
6. Test every flow with **two or more accounts** (artist and listener, tips, picks, tickets,
   verification, sponsored picks) before mainnet.

## Mainnet (gnoland-1), step by step

Checked on 2026-10-08 (block 642,481):

- **Approval is not automatic.** `vm:p:pkg_approvers` is one address,
  `g1yaaa6rcp4ew5yjzdj4yms596wx2dtrj3a86704` (no registered name, no transactions yet,
  4,465 GNOT). Each of the 12 packages waits for it in turn: ask the gno.land core team
  before deploying (the approver's operators, through the usual gno.land channels: GitHub
  `gnolang/gno` or the team), give them the namespace and the order above, and the lint and
  test results. One approval at a time means 12 round trips unless they batch: plan for days.
- **Namespace.** `nym-alexiscolin000` is free on mainnet (`r/sys/users.IsNameTaken` false,
  canonical form free, valid for `r/sys/namereg/v0`, registration price 0 and not paused).
  Register it first: `gno.land/r/sys/namereg/v0.Register("nym-alexiscolin000")`, a direct call
  from your key. Or deploy under your address instead
  (`gno.land/r/g1mpkp5lm8lwpm0pym4388836d009zfe4maxlqsq/gnoradio/...`, no registration), at
  the cost of long URLs.
- **Funds.** `g1mpkp5lm8lwpm0pym4388836d009zfe4maxlqsq` does not exist on mainnet yet
  (balance 0). Mainnet has no faucet: it needs about **105 GNOT** (deposits, submissions,
  setup) before the first submission, plus what the launch catalog costs.
- **Imports.** Every package GnoRadio imports outside its namespace is live on mainnet:
  `p/moul/txlink/v0`, `p/nt/bptree/v0`, `p/nt/grc721/v0`, `p/nt/markdown/sanitize/v0`,
  `r/sys/users`.
- **Same VM as onyx.** Both chains run commit `e75fef82c`: what works on onyx works on
  mainnet. `MsgRun` is allowlisted on both, so setup goes through calls, never `maketx run`.
- **gnomcp is read-only on mainnet**: no session. The setup calls go through gnokey (or Adena).

1. Fund the address, register the name.
2. `tools/deploy/deploy.sh --dry-run mainnet <key> nym-alexiscolin000`, then without it. The
   script waits (polls every 30 s) and prints how to check a package
   (`gnokey query vm/qpkgmeta_json -data <path> -remote https://rpc.gno.land:443`: `inert` means
   parked) and the approval queue (`vm/qinertpaths`). Ctrl-C and run again later is fine.
3. Setup calls with gnokey, guardian on its second key **before** opening.
4. Netlify site for mainnet, `VITE_NETWORK=mainnet`.

## Netlify

**Recommended: one site per network**, both from this repository (`app/` as base directory):
`gnoradio-onyx` (a netlify.app address is enough) and the public one on mainnet. Separate
sites keep separate variables, function secrets, domains and analytics, and a build of one
never touches the other. (One site with a branch context also works, with every variable
scoped per context; it is easier to get wrong.) Both fit the free plan.

Set every variable in the Netlify UI, scope **All** (builds, functions, edge functions): the
functions read them at run time, and `netlify.toml` must not set them (its values would
override the UI's and pin every site to one chain).

| Variable | onyx site | mainnet site |
|---|---|---|
| `VITE_NETWORK` | `onyx` | `mainnet` |
| `VITE_GNORADIO_NS` | `nym-alexiscolin000/gnoradio` | the same (or the g1 address path) |
| `BOT_SIGNING_KEY` | a robot key | **another** robot key (a key per chain) |
| `OPENAI_API_KEY` | the dedication filter's key | the same or another |
| `VITE_POSTHOG_KEY` | optional | optional |
| `AUDIUS_API_KEY` | the Audius key (api.audius.co/plans), functions only | the same |
| `JAMENDO_CLIENT_ID` | the Jamendo client id (devportal.jamendo.com), functions only | the same |

Not used, keep them out of Netlify: Audius's bearer token (it acts for users; GnoRadio only
reads) and any `VITE_AUDIUS_KEY` (the key stays server-side; plays use `app_name`).

The operator's values live in `app/.env.local` on the build machine (git-ignored, mode 600); the
Netlify CLI can import them without printing them: `netlify link --id <site>`, then
`netlify env:import app/.env.local` (drop the two unused names first), then set `VITE_NETWORK`
and `VITE_GNORADIO_NS` per site, and check the names with `netlify env:list`.

`VITE_NETWORK` sets the chain id, the RPC (the page reads the chain's public RPC directly; both
answer cross-origin requests), the RPC given to Adena and the gnoweb links
(`app/src/lib/network.ts`); `VITE_RPC`, `VITE_CHAIN_ID`, `VITE_WALLET_RPC`, `VITE_GNOWEB` and
`BOT_RPC` override one value each. On mainnet the network badge, the "test GNOT" lines and the
testnet terms line disappear.

With `VITE_POSTHOG_KEY` set, turn on **"Discard client IP data"** in the PostHog project settings: the
Legal page says the IP address is discarded, and posthog-js has no client option for it.

## Before mainnet

- [ ] Every flow tested on onyx with several accounts.
- [ ] Guardian on its own key (`Guardian()` shows the second address).
- [ ] Robot keys set on both realms (`catalog.SetBot`, `radio.SetModBot`), private key only in Netlify.
- [ ] The approver contacted and the 12 approvals planned.
- [ ] Mainnet address funded: about 105 GNOT for the deploy, plus the launch catalog
      (`import.py --dry-run` prints it; about 0.09 GNOT a track), name registered.
- [ ] PostHog project: Discard client IP data on (the Legal page says the IP is discarded).
- [ ] Legal, blocking for a public launch: a private contact for notices and data requests
      (GDPR art. 13, DSA), the publisher's identity, SACEM/SPRE for the radio, an Audius API
      key and their terms on storing their data on chain, a lawyer on the ticket service fee
      and the treasury, and your employment contract checked.

## Keys and roles

Whoever deploys becomes the data realm's owner and guardian, and the admin of catalog, radio
and tickets (home follows the catalog admin). Every role is passed on in two steps (offered,
then accepted) and can be renounced; an admin survives a new release of the rules.

| Role | Can | Cannot |
|---|---|---|
| **Admin** (catalog, radio, tickets) | moderate (hide, resolve reports, restore dedications, unmute), allow hosts, set the robot keys, the treasury, the service fee, the app URL and contact line; reassign an imported (curated or Audius) profile with `ResetOwner` + `AssignArtist`, which sends its future tips to the new wallet; pass the role on with `OfferAdmin` / `AcceptAdmin`, or `RenounceAdmin` | take a tip, ticket money or support already paid (they are paid out in the same transaction), reassign a profile an artist registered themselves, touch the artists' promo budgets, pause or replace the rules |
| **Owner** (data realm) | propose a new release of the rules (it takes over 12 h after it is on chain and ready; onyx's data realm, deployed first, keeps 72 h), cancel it, pause and resume writes, pass the role on (`Offer` / `Accept`), renounce it, replace the guardian 24 h after announcing it (`GuardianReplace`) | write data, move anyone's money, skip the 12 h delay, change the guardian faster than 24 h |
| **Guardian** (data realm) | pause writes (while there is an owner), cancel a release not yet in force, hand its role to another address (two steps), renounce it | propose, resume, change the owner, cancel the owner's `GuardianReplace`, write data, move money |

Reads and promo withdrawals (`data.VaultWithdraw`, by the funder) keep working while
anything is paused. A stolen admin key can hide content, point the robot keys elsewhere,
change the treasury and reassign imported profiles (and so their future tips) to a wallet of
its own, but it cannot take money already paid or touch self-registered profiles or promo
budgets: pause from the guardian and move the admin role at once. The next admin is whoever
it offers the role to, so check the address twice.

Before a handover, end any Quick actions session on the address (Turn off Quick actions in
the app, which revokes it on chain): the old admin before `OfferAdmin`, the new one before
`AcceptAdmin`. An address holding a role must not keep a session that signs for it.

### Why a guardian, and why another key

GnoRadio holds money (artists' promo budgets in the data realm's vault); gnogolf holds scores,
so it has an owner only. With a guardian on a **different key**, a stolen owner key is not the
end: during the 12 h before a malicious release takes over, the guardian pauses and cancels it.
If owner and guardian are the same key, the guardian protects nothing: whoever steals the key
has both roles.

- **Owner:** your everyday address (`g1mpkp5lm8lwpm0pym4388836d009zfe4maxlqsq`, nym-alexiscolin000).
- **Guardian:** a second address of yours, on a key kept apart: a second Adena account on
  another device, a gnokey key on an offline machine, or a hardware wallet. It is almost never
  used.

At deploy both roles are the deployer's address. Move the guardian before GnoRadio holds sums
that matter.

A stolen guardian key alone can keep pausing writes and cancelling releases (no money moves,
reads and withdrawals go on), and can move the guardian role to the thief's own key, so the
holder cannot hand it on any more. The owner's way out: `GuardianReplace(<fresh address>)` on
`data`. The fresh address becomes guardian 24 h (twice the release delay) later, and the
guardian cannot cancel it; meanwhile the owner resumes after each pause. The same call in a
thief's hands (a stolen owner key) is public for that day, and its release then needs
12 h more: 36 hours for funders to withdraw. `GuardianReplace("")` withdraws an announced
replacement; `Writers()` shows it as `nextGuardian` and `guardianAt`.

### Moving the guardian to the second key

Two transactions, on `gno.land/r/nym-alexiscolin000/gnoradio/data`:

1. From the current guardian (your everyday key): `GuardianOffer(<second address>)`.
2. From the second key: `GuardianAccept()`.

Check with `Guardian()` (a read). Only the guardian hands its role on this way; the owner's
only call on the role is the slow `GuardianReplace` above.

## After the realms are live

1. Robot keys: `catalog.SetBot` and `radio.SetModBot` with the robot's public key (the private
   one only in Netlify, `BOT_SIGNING_KEY`; [VERIFICATION.md](VERIFICATION.md)).
2. `catalog.SetTreasury`: skipped for the free, non-commercial launch (no treasury by default;
   see [Launch policy](#launch-policy-free-and-non-commercial)). Without one, support is refused.
3. `catalog.AllowHost("archive.org", true)` if it is not allowed yet (`HostAllowed`), and any
   other https host the catalog uses.
4. `home.SetAppURL` to the app's public URL, so gnoweb links to the app and its Legal page;
   `home.SetContact` for the contact line on the rights-notice page.
5. `tickets.SetServiceFee` (ugnot, 10 GNOT at most): skipped for the free launch (fee 0 by default).
6. Launch catalog: build `tools/curate/import_batch.json` (`curate.py batch`), then
   `tools/deploy/import.py [--dry-run] <onyx|mainnet> <key> nym-alexiscolin000` as the catalog
   admin. It creates the missing artists, then calls `radio.ImportTracks` per 25 tracks (each joins
   its genre station in the same transaction, so nothing waits for `Sync`; imports skip New this week), prints the cost first and
   resumes where it stopped (`import_done.<net>.<namespace>.json` next to the batch: one per network and namespace). GnoRadio runs no robot that transacts: after
   the launch, artists' publications pay for their own stations.
7. Netlify: the variables in [Netlify](#netlify), scope "All". Without `VITE_GNORADIO_NS`
   there, the link previews query `gno.land/r/gnoradio/...` and fall back to the default card.
8. Move the guardian to its own key (above).
9. Audius and Jamendo keys (`AUDIUS_API_KEY`, `JAMENDO_CLIENT_ID`) in Netlify, functions only (table above). `JAMENDO_CLIENT_ID` is mandatory once Jamendo pointers are imported: without it they stay unnamed and silent (Audius pointers are still named).
10. Before the public launch: a private contact for notices and data requests (GDPR art. 13, DSA), shown on the Legal page.

## Upgrading the rules later

1. Deploy the new rules realms (`catalog/v2`, `radio/v2`, `tickets/v2`, `home/v2`) under the
   same namespace. Their `gnomod.toml` must have no `private` and no `replace`: a private
   package can be re-uploaded after the delay (checked on a v1.5.0 gnodev: a second
   `addpkg` of a `private = true` realm replaced its code; a normal one is refused with
   `PkgExistError`). Check it on gnoweb's source view before `Propose`, and again before
   the 12 h are over.
2. As owner, on `data`: `Propose(<role>, <new realm path>)` for each role in the release.
3. Call `Ready()` on each new realm (anyone may); 12 h after the last one, the whole release
   takes over at once. The data stays where it is: nothing is copied, no deposit is paid again.
   Admins carry over. The app then points to the new paths (`app/src/lib/realms.ts`).
4. During those 12 h anyone can read the new code on gnoweb; the owner or the guardian can
   `Cancel()` it.

## In an emergency

- Bug in the rules: owner or guardian `Pause("", true)` (every role) or `Pause("<role>", true)`;
  the owner resumes with `Pause(..., false)` once fixed, or proposes a fixed release.
- Owner key stolen: the guardian pauses and cancels any release the thief proposes, then you
  move what you can; a new owner can only be set by the current owner (`Offer` / `Accept`).
  If the thief calls `GuardianReplace`, the guardian keeps that up for the 24 h it takes;
  tell funders to withdraw their promo budgets.
- Guardian key stolen: as owner, `GuardianReplace(<fresh key>)`, and resume after each pause
  until it takes over 24 h later.
- `Renounce()` makes the rules permanent for good: no release, no pause, ever. Only for a
  GnoRadio meant to run on its own forever.
