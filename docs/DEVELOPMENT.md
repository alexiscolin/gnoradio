# Development

## Layout

```
gno/p/gnoradio/blocks/v0     rotation as strings in fixed-size blocks (pure package)
gno/p/gnoradio/role/v0       two-step role: offer, accept, renounce (pure package)
gno/p/gnoradio/safe/v0       screens dedications: plain text, no links, multilingual blocklist (pure package)
gno/p/gnoradio/store/v0      string codecs: records, id lists, keys and rows of the data realm (pure package)
gno/p/gnoradio/svg/v0        shared on-chain SVG canvas (covers, tickets, charts)
gno/p/gnoradio/text/v0       shared string helpers (JSON strings, numbers, URLs, text rules, GNOT)
gno/r/gnoradio/data          every record and the promo vault; owner, guardian, releases (permanent)
gno/r/gnoradio/catalog/v1    artists, tracks, albums, playlists, likes, follows, tips, treasury
gno/r/gnoradio/radio/v1      23 stations, rotations, listener and curator queue
gno/r/gnoradio/tickets/v1    concerts and tickets
gno/r/gnoradio/tickets/nft   the GRC721 ticket NFTs (permanent)
gno/r/gnoradio/home/v1       the gnoweb site
app/                         web app (Vite + React + strict TypeScript)
tools/curate/                launch catalog selection (see its README)
tools/gasfix/                writes the radio and catalog gas filetests from one fixture each
tools/deploy/                deploy and launch-catalog import, onyx or mainnet (see DEPLOY.md)
docs/SPEC.md                 full product and technical spec
```

The data lives in one permanent realm, `data`; the rules realms (`catalog`, `radio`,
`tickets`, `home`, release `v1`) write it and can be replaced by a new release without moving
it ([ARCHITECTURE-v1.md](ARCHITECTURE-v1.md)).

The realms target gno.land v1.5.0, the release running on onyx and mainnet.

## Realm tests

Use a toolchain that matches the chain:

```sh
export GNOROOT=~/go/pkg/mod/github.com/gnolang/gno@v1.5.0
export GNOHOME=~/.cache/gno-toolchains/onyx-v1.5.0/gnohome
G=~/.cache/gno-toolchains/onyx-v1.5.0/gno
$G lint ./gno/... && $G test ./gno/...
```

The `z_gas_*_{5k,20k}` filetests of `radio/v1` and `catalog/v1` are generated: edit the
fixture (`tools/gasfix/radio.tmpl`, `catalog.tmpl`) or a main (`tools/gasfix/cases.txt`), then
run `python3 tools/gasfix/gen.py` and refresh the goldens with
`$G test -update-golden-tests ./gno/r/gnoradio/radio/v1` (or `catalog/v1`). A golden should
move only when the change explains it; `python3 tools/gasfix/gen.py --check` fails when a
checked-in file drifted from its case.

## App, robot and end-to-end tests

```sh
cd app
npm run check   # typecheck, lint, unit tests (app and Netlify robot), build
npm run e2e     # Playwright, desktop and mobile, against the local devnet (start it first)
```

The end-to-end suite runs offline (remote audio and images are stubbed) and fails on any console error.

## Local devnet

`gnodev` built from the v1.5.0 tag, on non-default ports:

```sh
gnodev local -empty-blocks -no-watch \
  -node-rpc-listener 127.0.0.1:27157 -web-listener 127.0.0.1:8911 -chain-id dev \
  -extra-root ./gno \
  -paths gno.land/p/gnoradio/text/v0,gno.land/p/gnoradio/svg/v0,gno.land/p/gnoradio/store/v0,gno.land/p/gnoradio/safe/v0,gno.land/p/gnoradio/blocks/v0,gno.land/p/gnoradio/role/v0,gno.land/r/gnoradio/data,gno.land/r/gnoradio/catalog/v1,gno.land/r/gnoradio/tickets/nft,gno.land/r/gnoradio/tickets/v1,gno.land/r/gnoradio/radio/v1,gno.land/r/gnoradio/home/v1,gno.land/r/gnoradio/devseed/v0,gno.land/r/sys/users \
  -web-home /r/gnoradio/home/v1
```

- RPC: `http://127.0.0.1:27157`
- gnoweb: `http://127.0.0.1:8911/r/gnoradio/home/v1`

The deployer (gnodev's test1) is the data realm's owner and guardian and the admin of every
rules realm. A fresh devnet is empty. Seed it as the admin: create artists, then import tracks
with `radio.ImportTrack` (each joins its stations in the same transaction). A local-only `devseed` realm (gitignored, data from
`tools/curate/curate.py devseed`; leave it out of `-paths` if you do not have it) imports
thousands of Audius tracks in batches while it holds the catalog admin role, all signed by test1:

1. `catalog.OfferAdmin(<devseed.Address()>)`, then `devseed.Take()`.
2. `devseed.Base()` (Scott Buckley and ATTLAS, artists 1 and 2), then any artist of your own
   (`catalog.RegisterArtist` and `radio.PublishTrack`).
3. `devseed.Run()` until it returns 0.
4. `devseed.GiveBack()`, then `catalog.AcceptAdmin()`.
5. The admin calls (`Verify`, `SetBot`, `radio.SetModBot`, `home.SetAppURL`, …). `radio.Sync`
   only has work after something added tracks without the radio (`radio.Pending()` says how many).

Main's flow needs no call: it simulcasts the hour's genre station, computed from the clock,
and keeps no rotation of its own. A devnet seeded before that change holds another flow record
layout (and a Main rotation the radio no longer reads): restart it empty and seed it again.

## App

```sh
cd app
npm install
npm run dev        # http://127.0.0.1:5173, /rpc is proxied to the devnet
npm run check      # typecheck + lint + tests + build
npm run build      # static build in dist/
```

To use Adena on the devnet, add a custom network in Adena with chain id `dev` and the devnet RPC.

Build-time variables (read by Vite, public in the bundle):

| Variable | Meaning | Production |
|---|---|---|
| `VITE_NETWORK` | chain preset: `dev`, `onyx` or `mainnet` (`src/lib/network.ts`); also read by the functions | `onyx` or `mainnet`, per site (onyx when unset) |
| `VITE_RPC` | RPC used for reads | the network's public RPC (`/rpc`, proxied by Vite, on the devnet) |
| `VITE_CHAIN_ID` | chain the wallet must be on | from `VITE_NETWORK` |
| `VITE_WALLET_RPC` | RPC given to Adena (also read by the functions) | from `VITE_NETWORK` |
| `VITE_GNOWEB` | gnoweb base for links | from `VITE_NETWORK` |
| `VITE_SITE_URL` | public URL for Open Graph, robots.txt and the sitemap | set from Netlify's `URL` by the build command |
| `VITE_GNORADIO_NS` | namespace of the packages (also read by the functions) | the deployer's, e.g. `nym-alexiscolin000/gnoradio` (default `gnoradio`, the devnet's) |
| `VITE_POSTHOG_KEY` | PostHog project key (public, write-only); unset, no analytics load ([ANALYTICS.md](ANALYTICS.md)) | set in Netlify |

Function secrets (Netlify environment, never committed):

| Variable | Used by | Meaning |
|---|---|---|
| `BOT_SIGNING_KEY` | `verify`, `dedication` | Ed25519 seed (64 hex) of the robot's certificates; its public key goes to `catalog.SetBot` and `radio.SetModBot` |
| `OPENAI_API_KEY` | `dedication` | OpenAI moderation API key |
| `BOT_RPC` | `verify`, `dedication` | RPC the robot reads (defaults to the site network's RPC: `VITE_WALLET_RPC`, else `VITE_NETWORK`'s; the devnet under `npm run dev`). The robot holds no account and sends no transaction |

`app/.env.example` is a template for `app/.env.local`.

`app/netlify.toml` holds the PostHog proxy (`/e`, only the capture, static and config paths; the page reads the chain's public RPC directly, `/rpc` exists only on the dev server), the CSP and cache headers. Netlify functions in `app/netlify/`:

- `functions/verify.mts`: the artist verification robot ([VERIFICATION.md](VERIFICATION.md)).
- `functions/dedication.mts`: screens a dedication (word list, then OpenAI moderation) and signs a certificate for `radio.QueueWithNote`.
- `functions/og.mts`: the link-preview image of a page (`/og/<kind>/<id>.png?v=<hash>`). Draws only the canonical URL (any other slug or `v` is redirected there), 30 images per client IP a minute, covers up to 4 MB and 4096×4096 px, cached an hour on the CDN.
- `edge-functions/meta.ts`: for preview bots only, a page's title, description and image read on-chain (`cards.ts`); an unverified artist's preview says so, a verified one names its proof's host.

## Deploying

Nothing is deployed to a public network yet. How to deploy to onyx, who holds which role and
what to set up afterwards: [DEPLOY.md](DEPLOY.md).

## Git hooks

After cloning, enable the repo hooks once:

```sh
git config core.hooksPath .githooks
```

`commit-msg` rejects co-author and AI attribution lines.
