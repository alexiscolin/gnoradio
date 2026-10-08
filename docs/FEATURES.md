# Features and promises

What GnoRadio promises, how each promise is kept, and what checks it. "Realm" means the
rule lives in the on-chain code, so no app or server can bypass it. The realms are release 1
of the rules on a permanent data realm ([ARCHITECTURE-v1.md](ARCHITECTURE-v1.md)).
Tests named below are in `gno/r/gnoradio/{data,catalog/v1,radio/v1,tickets/v1,home/v1}`.
"Manual devnet run" means a full run by hand on a local devnet on 2026-10-07, not a test in
the repository.

## Promises

| Promise | How it is kept | Checked by |
|---|---|---|
| Listening is free and needs no wallet | The app reads the chain without signing; audio comes from IPFS, Arweave, archive.org or Audius | e2e `app.spec.ts` (scenarios 1 to 4) |
| Everyone on a station hears the same second | The schedule is on-chain; players compute the offset from block time; jingles play over the music without shifting it | radio `TestScale*`, e2e scenario 3 |
| GnoRadio pays nothing to run | Listeners and artists sign and pay their own transactions; a published track joins its stations in the artist's own transaction (`radio.PublishTrack`), so no robot transacts for GnoRadio; robots only sign certificates off-chain | radio `TestPublishJoinsStations`, `z_gas_publish_*` filetests; catalog `TestTrackWritesRadioOnly` |
| GnoRadio never holds your money | Tips, tickets and support are paid out in the same transaction; promo budgets sit in the data realm's vault with no admin power over them and can be withdrawn by their funder at any time, even while GnoRadio is paused; the rules realms end every transaction holding nothing | catalog `TestTipSplitsAndGuards`, `TestSponsoredPickMoney`, `TestTipCannotSpendBudgets`, `TestRulesHoldNothing`; data `TestVaultInvariant`, `TestWithdrawWhilePaused` |
| Tips reach the artist, not GnoRadio | 100% to the artist and their collaborators, minus the promo share the artist chose; 0% to GnoRadio; the +10% for GnoRadio is optional and off by default | catalog `TestTipSplitsAndGuards`, `promo_test.gno`, app `SupportSheet.test.tsx` |
| Only artists who proved a page can receive money | Tips and paid tickets need a verified profile: a code on the artist's own Audius bio or domain, a robot certificate, then a public 72-hour wait. The moderator can also verify a profile by assigning it (`AssignArtist`); curated imports are verified only that way. A ✓ proves control of that page or domain, not a legal identity: the host is shown next to every robot-verified ✓, and a moderator-verified one says "verified by the GnoRadio moderator" (artist page, Browse, Community, gnoweb; link previews show no ✓) so a look-alike domain is visible | catalog `z_cert_filetest.gno` (real certificates, bound to the chain and the data realm), robot `verify.test.ts` |
| Picks are fair | One pick per listener per station per hour, one waiting per listener per station, 2 per artist, a track not again on a station within 3 hours, genre stations take only their genre, "New this week" only new tracks, at most 2 hours of picks ahead, 30 waiting per station, 4 booked picks per station and UTC hour (aired ones included), 15 booked waiting at most | radio `radio_test.gno`, `book_test.gno`, `fix_test.gno`, `TestBookedHalfQueue`, `TestHourCapCountsAired` |
| Dedications are safe without a human moderator | Checked before the transaction (on-chain word filter, then a moderation model); the robot signs a certificate bound to the listener, the station and the exact text, valid 10 minutes (the realm refuses more than 15); three reports hide one, from listeners with the sponsored-pick reputation (a first pick 7 days old, 3 normal picks in the last two 15-day periods); a second hidden dedication within a week mutes the author for a week, and the robot refuses a muted author before asking the model | radio `note_test.gno`, `TestReportNeedsReputation`, `safe` corpus (150 attacks / 150 legit texts), robot `dedication.test.ts` |
| Your pick is never cut and never cuts a song | Picks start at a track boundary (on Main at once, over the hour's simulcast); booked picks are re-timed, never pushed | radio `TestBookAlignAndAround`, `TestRealignNowPickAfterGap` |
| Sponsored picks cannot be farmed | The artist refunds the pick, fee and deposit (0.2 GNOT by default, enough that a sponsored pick costs the listener nothing; 0.01–0.5 as the artist sets it), reserved at pick time and paid after airing; quotas per artist, station and wallet; a reputation of a first pick 7 days old and 3 normal picks in the last two 15-day periods | radio and catalog `sponsor_test.gno` |
| Costs stay flat as the catalog grows | Ordered trees in the data realm, records chunked by 8, likes packed by ranges of 512, fixed-size rotation blocks, bounded schedules | gas and deposit goldens at 5,000 and 20,000 tracks (`filetests/z_gas_*` in catalog, radio and tickets), `blocks` `TestCodecMatchesList`, home `TestGasSeeded` |
| Artists keep control of their work | Edit a track's info and file links, hide (and show again) their own tracks, albums or profile, cancel their own concerts, all in the app; every moderation removal carries a public reason; a rights notice works through a GitHub issue, without a wallet | catalog `TestHideOwn`, `TestModeration`, Legal page |
| Everything is public and checkable | Every action is a transaction; gnoweb renders every page from the chain | home `TestPages`, `TestGnowebPages`, manual devnet run (19 pages) |
| Visits are measured without knowing who you are | Anonymous PostHog EU audience measurement, no banner: nobody identified, addresses scrubbed from every event, one click on the Legal page stops it; nothing loads without a key ([ANALYTICS.md](ANALYTICS.md)) | app `analytics.test.ts` |
| The rules can be upgraded without moving the data, and never by surprise | Every record lives in one permanent data realm; its owner proposes new rules realms, which take over 72 hours after they are all on chain; a separate guardian can pause and cancel a release, and the owner can replace it only 144 hours after announcing it (the guardian cannot cancel that); admins carry over | data `TestReleaseTakesOverAfterDelay`, `TestGuardian`, `TestThiefGuardianIsReplaced`, `TestPauseResumeRenounce`; catalog `TestAdminFollowsMirror`; `z_release_filetest.gno` in catalog and radio |

## Features

**Listen**
- Live stations: Main (simulcasts one genre station an hour, by time of day), 20 genre stations, New this week, Listeners' choice.
- Library: search, genres, artists, albums, playlists, on-demand playback, drag to seek; tracks in four orders (mix of the day, most liked, most tipped, newest).
- Your library: the tracks you saved (in the browser) and the ones you liked (on-chain).
- Station jingles on tune-in and at the top of each hour (radio only), matched to the genre on Main.
- On a phone, a tab bar with every section of the sidebar.
- Media keys and lock screen: play/pause, next/previous station on the radio, next/previous track in the library.

**Take part**
- Pick next: choose a track for everyone, right away or at a set time (15 minutes to 24 hours ahead), with an optional dedication shown on air.
- Like, save, follow artists, make public playlists and edit your own.
- Tip an artist, or tip during a pick: the picker and whoever shared the link get the artist's promo share, when the artist set one. A tip on your own pick shares nothing, with you or with a link you name.
- Sponsored picks: an artist can refund listeners who play them.
- Curator stats and a weekly top (the per-station weekly top is on gnoweb); public listener pages with a generated nickname until a gno.land name is registered.
- Support GnoRadio (optional), report content; contact the publisher through a GitHub issue (public: no personal data in it).

**For artists**
- Register, publish and edit tracks (IPFS or Arweave), splits with collaborators; albums on gnoweb.
- Verify the profile (Audius bio or own domain), then turn tips on.
- Promo share (opt-in, 0–20%; 0% until set) and sponsored-pick budget, withdrawable at any time.
- Concerts: free or paid tickets (NFTs). The ticket price goes 100% to the artist; a service fee set by the admin (10 GNOT at most) is added for the treasury. Holders can give a ticket to another wallet from Me; the artist can cancel their concert from its ticket (refunds are the artist's to make: tickets are not refunded automatically). At the door the holder taps Show at the door and the QR shows; the artist scans it and the door page shows a fresh code; the holder enters it and their wallet signs `tickets.Present` with it (proof they hold it, valid 10 minutes); the door page then shows who presented it and when, and the artist checks the holder in. A copied QR gets another code, so it cannot use the holder's signature. The door opens 12 hours before the start and closes 12 hours after it.
- Listeners find concerts by search, this week or this month, free only, city and day.

**Wallets**
- Adena in the browser, quick actions with a session, or gnokey commands to copy. A session's daily cap bounds fees and deposits only: the chain lets it call any function of catalog and radio, so a key stolen from the browser can act as the user there (for an artist: edit their tracks and settings) until it expires (7 days) or is turned off. Sessions are refused to GnoRadio's admin, treasury, owner and guardian addresses.

## Known limits

- Some first actions lock a storage deposit (100 ugnot per byte; measured on the v1 devnet with 5,000 tracks): about 0.1 GNOT for a first like (0.005 for the next ones nearby), 0.05 for a first follow, 0.07 for a pick (0.22 for a listener's first), 0.4 for a first ticket, 0.55 to open a promo budget.
- Cover art from Audius is fetched per track and can hit Audius's rate limit.
- Past dedications are not kept anywhere readable on-chain; an indexer would be needed for history.
- The app reads the whole catalog on a first visit (then caches it a day); past tens of thousands of tracks it needs an indexer or per-view loading.
- When Main relays a genre whose only playable tracks were dropped from Main, Main is silent for those tracks' turns (rare: drop them from the genre station too).
- Rankings can be inflated by an artist tipping their own track from a second wallet: the coins come back, only rankings move (ARCHITECTURE section 8).
- Features that need several real people (three reports, sponsored payouts, curator shares, the full 72-hour verification) are covered by unit tests only.

## Running the checks

- Realms: see [DEVELOPMENT.md](DEVELOPMENT.md) (`gno test ./gno/...`).
- App and robot: `cd app && npm run check`.
- End to end, with the devnet running: `cd app && npm run e2e`.
