# Local devnet

A throwaway chain for the app: gnodev on `127.0.0.1:27157` (RPC) and `127.0.0.1:8911`
(gnoweb), chain id `dev`, with the curated catalogue loaded. Never deploy anything from here.

Needs the onyx-matched toolchain in `~/.cache/gno-toolchains/onyx-v1.5.0/` and the gno v1.5.0
sources as GNOROOT (default: the Go module cache, `~/go/pkg/mod/github.com/gnolang/gno@v1.5.0`).

## 1. The catalogue (once, then after each curation change)

```sh
python3 tools/curate/curate.py hash --max 5000                          # sha256 of every file, cached in hashes.json
python3 tools/curate/curate.py batch --approved tools/curate/candidates.json   # every candidate (a launch uses review.html's approved.json)
python3 tools/dev/seedgen.py                                            # -> gno/r/gnoradio/devseed/v0 (gitignored)
```

`seedgen.py` also takes `tools/curate/pointers_batch.json` (Audius and Jamendo pointers, from
`tools/curate/pointers.py`) when it exists. It encodes the lines with `tools/deploy/import.py`'s
`batch_arg`, the encoder the real import uses.

## 2. Start

```sh
tools/dev/start.sh        # stops the previous devnet on 27157 only, then starts it
```

Both owner addresses get 1,000,000 GNOT (`-add-account`). The devseed realm is loaded when it
exists.

## 3. Seed (as test1, through gnomcp profile `radiodev`, or gnokey with the test1 key)

Realms are `gno.land/r/gnoradio/...`.

1. `catalog/v1.OfferAdmin(<devseed/v0.Address()>)`, then `devseed/v0.Take()`.
2. `devseed/v0.Artists(220)` until it returns 0 (about 850M gas).
3. `devseed/v0.Run(n)` until it returns 0, n being lines per call: gnomcp caps gas-wanted at 1B,
   so `Run(25)` while it imports curated tracks (600-840M gas), then `Run(100)` for pointers
   (about 800M).
4. `devseed/v0.GiveBack()`, then `catalog/v1.AcceptAdmin()`.
5. Demo data the e2e tests use (test1):
   - `catalog/v1.CreateAlbum(1, "<title>", "", "", 2024, "1,2,3")` (artist 1 owns tracks 1-3 when
     its seed comes first; check with `TrackJSON`), `catalog/v1.PublishPlaylist("Night Drive", "<ids>")`;
   - `catalog/v1.RegisterArtist("Lea Kosmos", "Night synthwave & cassettes from Lyon.")`, two
     `radio/v1.PublishTrack(...)` for her (any ipfs CID; the audio is not real), and
     `catalog/v1.Verify(<her id>, true)`;
   - `catalog/v1.SetBot` and `radio/v1.SetModBot` with the dev robot's public key (derived from
     `BOT_SIGNING_KEY` in `app/.env.local`; never print the private key);
   - three `tickets/v1.CreateEvent(...)` as Lea (one free) and a `tickets/v1.BuyTicket` of the free
     one, so ticket 1 exists;
   - a few likes, a follow, `SetPromoShare(10)`, a `radio/v1.Queue(0, <track>)`.
6. Dedications need a certificate from the app's `/api/dedication`: run the app with
   `VITE_NETWORK=dev npm run dev` (port 5173) and pick with a dedication from the app, or skip
   them (the e2e test 6 puts one on air itself).

## 4. Check

`cd app && npx playwright test` (the e2e suite reads this devnet). It reuses a dev server already
on 5173: one started before `vite.config.ts` or the deps changed fails with stale-dep 504s.

Import pointers later, once their batch exists: `python3 tools/dev/seedgen.py`, restart, and redo
steps 1 to 4 of the seed.
