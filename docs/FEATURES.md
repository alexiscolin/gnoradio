# Features and promises

What GnoRadio promises, how each promise is kept, and what checks it. "Realm" means the
rule lives in the on-chain code, so no app or server can bypass it. This describes the v0
realms that ship today; the v1 refactor is in progress ([ARCHITECTURE-v1.md](ARCHITECTURE-v1.md)).
"Manual devnet run" means a full run by hand on a local devnet on 2026-10-07, not a test in
the repository.

## Promises

| Promise | How it is kept | Checked by |
|---|---|---|
| Listening is free and needs no wallet | The app reads the chain without signing; audio comes from IPFS, Arweave, archive.org or Audius | e2e `app.spec.ts` (scenarios 1 to 4) |
| Everyone on a station hears the same second | The schedule is on-chain; players compute the offset from block time; jingles play over the music without shifting it | radio `TestScale*`, e2e scenario 3 |
| GnoRadio pays nothing to run | Listeners and artists sign and pay their own transactions; robots only sign certificates off-chain; the Sync robot is optional and off | manual devnet run (GnoRadio spent 0) |
| GnoRadio never holds your money | Tips, tickets and support are paid out in the same transaction; promo budgets sit in the catalog with no admin power over them and can be withdrawn at any time | catalog `TestTipSplitsAndGuards`, `TestSponsoredPickMoney`, `TestTipCannotSpendBudgets` (the `PromoHeld` invariant) |
| Tips reach the artist, not GnoRadio | 100% to the artist's wallet, minus the promo share the artist chose for the listeners who played the track; the +10% for GnoRadio is optional and off by default | catalog `TestTipSplitsAndGuards`, `promo_test.gno`, app `SupportSheet.test.tsx` |
| Only real artists can receive money | Tips and paid tickets need a verified profile: a code on the artist's own Audius bio or domain, a robot certificate, then a public 72-hour wait | catalog `TestVerifyFlow`, `TestVerifyGuards`, robot `verify.test.ts` |
| Picks are fair | One pick per listener per station per hour, one waiting per station, 2 per artist, a track not again on a station within 3 hours, genre stations take only their genre, "New this week" only new tracks, at most 2 hours of picks ahead, 4 booked picks per hour | radio `radio_test.gno`, `book_test.gno`, `fix_test.gno` |
| Dedications are safe without a human moderator | Checked before the transaction (on-chain word filter, then a moderation model); the robot signs a certificate bound to the listener, the station and the exact text, valid 10 minutes (the realm refuses more than 15); three reports hide one; repeat offenders are muted | radio `note_test.gno`, `safe` corpus (150 attacks / 150 legit texts), robot `dedication.test.ts` |
| Your pick is never cut and never cuts a song | Picks start at a track boundary; the main flow moves around them; booked picks are re-timed, never pushed | radio `TestBookAlignAndAround`, `TestRealignNowPickAfterGap` |
| Sponsored picks cannot be farmed | The artist refunds about the pick's cost (0.01–0.05 GNOT), reserved at pick time and paid after airing; quotas per artist, station and wallet; a reputation of 7 days and 3 normal picks | radio and catalog `sponsor_test.gno` |
| Costs stay flat as the catalog grows | Sparse fan-out storage, fixed-size rotation blocks, bounded schedules | `store_test.gno`, `blocks_test.gno`, `gas_test.gno` in catalog, radio and tickets, home `TestGasHome` |
| Artists keep control of their work | Hide their own tracks, albums or profile; every moderation removal carries a public reason; a rights notice works through a GitHub issue, without a wallet | catalog `TestHideOwn`, `TestModeration`, Legal page |
| Everything is public and checkable | Every action is a transaction; gnoweb renders every page from the chain | home `TestPages`, `TestGnowebPages`, manual devnet run (19 pages) |
| Visits are measured without knowing who you are | Anonymous PostHog EU audience measurement, no banner: nobody identified, addresses scrubbed from every event, one click on the Legal page stops it; nothing loads without a key ([ANALYTICS.md](ANALYTICS.md)) | app `analytics.test.ts` |
| The realms can be upgraded | Successor pointers, admin-settable sibling and radio realms, paginated migration readers | catalog `TestRadioRealmUpgrade`, `TestNarrowGettersAndPages`, radio `TestMigrationReads` |

## Features

**Listen**
- Live stations: Main (a programmed flow of genre sets by time of day), 20 genre stations, New this week, Listeners' choice.
- Library: search, genres, artists, albums, playlists, on-demand playback, drag to seek; tracks in four orders (mix of the day, most liked, most tipped, newest).
- Your library: the tracks you saved (in the browser) and the ones you liked (on-chain).
- Station jingles on tune-in and at the top of each hour (radio only), matched to the genre on Main.
- On a phone, a tab bar with every section of the sidebar.
- Media keys and lock screen: play, stop, next/previous station on the radio, next/previous track in the library.

**Take part**
- Pick next: choose a track for everyone, right away or at a set time (15 minutes to 24 hours ahead), with an optional dedication shown on air.
- Like, save, follow artists, make public playlists.
- Tip an artist, or tip during a pick: the picker and whoever shared the link get the artist's promo share.
- Sponsored picks: an artist can refund listeners who play them.
- Curator stats and a weekly top per station; public listener pages with a generated nickname until a gno.land name is registered.
- Support GnoRadio (optional), report content; contact the publisher through a GitHub issue.

**For artists**
- Register, publish tracks (IPFS or Arweave), albums, splits with collaborators.
- Verify the profile (Audius bio or own domain), then turn tips on.
- Promo share (0–20%) and sponsored-pick budget, withdrawable at any time.
- Concerts: free or paid tickets (NFTs), transfer, cancellation. Each ticket shows a QR code; the artist scans it and checks the holder in on the door page.
- Listeners find concerts by search, this week or this month, free only, city and day.

**Wallets**
- Adena in the browser, quick actions with a session (daily spending cap), or gnokey commands to copy.

## Known limits

- Some first actions lock a storage deposit: about 0.24 GNOT for a first like, 0.16 for a first tip, 0.3–0.9 for a first pick, 0.8–1.1 for a first ticket.
- Cover art from Audius is fetched per track and can hit Audius's rate limit.
- Past dedications are not kept anywhere readable on-chain; an indexer would be needed for history.
- Features that need several real people (three reports, sponsored payouts, curator shares, the full 72-hour verification) are covered by unit tests only.

## Running the checks

- Realms: see [DEVELOPMENT.md](DEVELOPMENT.md) (`gno test ./gno/...`).
- App and robot: `cd app && npm run check`.
- End to end, with the devnet running: `cd app && npm run e2e`.
