# Development

## Layout

```
gno/p/gnoradio/blocks/v0     rotation stored in blocks (pure package)
gno/p/gnoradio/safe/v0       screens dedications: plain text, no links, multilingual blocklist (pure package)
gno/p/gnoradio/store/v0      compact encodings for ids, records and buckets (pure package)
gno/p/gnoradio/svg/v0        shared on-chain SVG canvas (covers, tickets, charts)
gno/p/gnoradio/text/v0       shared string helpers (keys, JSON strings, text rules, GNOT)
gno/r/gnoradio/catalog/v0    artists, tracks, albums, playlists, likes, follows, tips, treasury
gno/r/gnoradio/radio/v0      13 stations, rotations, listener and curator queue
gno/r/gnoradio/tickets/v0    concerts and GRC721 tickets
gno/r/gnoradio/home/v0       the gnoweb site
app/                         web app (Vite + React + strict TypeScript)
tools/curate/                launch catalog selection (see its README)
docs/SPEC.md                 full product and technical spec
```

The realms target gno.land v1.5.0, the release running on onyx and mainnet.

## Realm tests

Use a toolchain that matches the chain:

```sh
export GNOROOT=~/go/pkg/mod/github.com/gnolang/gno@v1.5.0
export GNOHOME=~/.cache/gno-toolchains/onyx-v1.5.0/gnohome
G=~/.cache/gno-toolchains/onyx-v1.5.0/gno
for d in gno/p/gnoradio/{blocks,svg,text}/v0 gno/r/gnoradio/{catalog,radio,tickets,home}/v0; do
  $G lint ./$d && $G test ./$d
done
```


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
  -paths gno.land/r/gnoradio/home/v0,gno.land/r/gnoradio/catalog/v0,gno.land/r/gnoradio/radio/v0,gno.land/r/gnoradio/tickets/v0,gno.land/p/gnoradio/blocks/v0,gno.land/p/gnoradio/svg/v0,gno.land/p/gnoradio/text/v0,gno.land/p/gnoradio/store/v0,gno.land/p/gnoradio/safe/v0 \
  -web-home /r/gnoradio/home/v0
```

- RPC: `http://127.0.0.1:27157`
- gnoweb: `http://127.0.0.1:8911/r/gnoradio/home/v0`

A fresh devnet is empty. Seed it as the admin: create artists, import tracks, then call `radio.Sync`.

## App

```sh
cd app
npm install
npm run dev        # http://127.0.0.1:5173, /rpc is proxied to the devnet
npm run check      # typecheck + lint + tests
npm run build      # static build in dist/
```

To use Adena on the devnet, add a custom network in Adena with chain id `dev` and the devnet RPC.

Build-time variables (read by Vite, public in the bundle):

| Variable | Meaning | Production |
|---|---|---|
| `VITE_RPC` | RPC used for reads | `/rpc` (default; Netlify proxies it to onyx, see `netlify.toml`) |
| `VITE_CHAIN_ID` | chain the wallet must be on | `onyx-1` |
| `VITE_WALLET_RPC` | RPC given to Adena (also read by the edge function) | `https://rpc.onyx.testnets.gno.land:443` |
| `VITE_GNOWEB` | gnoweb base for links | `https://onyx.testnets.gno.land` |
| `VITE_SITE_URL` | public URL for Open Graph, robots.txt and the sitemap | set from Netlify's `URL` by the build command |

Function secrets (Netlify environment, never committed):

| Variable | Used by | Meaning |
|---|---|---|
| `BOT_SIGNING_KEY` | `verify`, `dedication` | Ed25519 seed (64 hex) of the robot's certificates; its public key goes to `catalog.SetBot` and `radio.SetModBot` |
| `OPENAI_API_KEY` | `dedication` | OpenAI moderation API key |
| `SYNC_ROBOT` | `sync` | `on` to enable the scheduled Sync (off by default) |
| `BOT_MNEMONIC` | `sync` | mnemonic of the robot's paying account; only needed with `SYNC_ROBOT=on` |
| `BOT_RPC` | `sync` | RPC the robot calls (defaults to onyx) |

`app/.env.example` lists them all.

`app/netlify.toml` holds the proxy, CSP and cache headers. Netlify functions in `app/netlify/`:

- `functions/verify.mts`: the artist verification robot ([VERIFICATION.md](VERIFICATION.md)).
- `functions/dedication.mts`: screens a dedication (word list, then OpenAI moderation) and signs a certificate for `radio.QueueWithNote`.
- `functions/sync.mts` (optional, `SYNC_ROBOT=on`): runs `radio.Sync` every 30 minutes when the chain says it has work.
- `edge-functions/meta.ts` (optional, commented out in `netlify.toml`): artist and track names in link previews.

## Deploying

Nothing is deployed to a public network yet. Before onyx:

1. Fill the owner placeholders: `app/src/lib/legal.ts` (publisher, contacts, host, minimum age, treasury holder, repeat-infringer rule) and the const block at the top of `gno/r/gnoradio/home/v0/home.gno` (abuse email, notice delay). The realms are immutable once deployed.
2. Register the `gnoradio` namespace.
3. Deploy the packages `blocks`, `svg`, `text`, `store` and `safe`, then the realms `catalog`, `radio`, `tickets` and `home`.
4. Call `TransferAdmin` on each realm to hand admin to the owner's address.
5. Set up the robot: `BOT_SIGNING_KEY` and `OPENAI_API_KEY` on Netlify, then `catalog.SetBot` and `radio.SetModBot` with its public key ([VERIFICATION.md](VERIFICATION.md)).
6. `catalog.SetTreasury` to the address that receives support and service fees.
7. `catalog.AllowHost("archive.org", true)` if it is not allowed yet (`HostAllowed`), and any other https host the catalog uses.
8. `home.SetAppURL` to the app's public URL, so gnoweb links to the app and its Legal page.
9. `tickets.SetServiceFee` (ugnot, 10 GNOT at most).

## Git hooks

After cloning, enable the repo hooks once:

```sh
git config core.hooksPath .githooks
```

`commit-msg` rejects co-author and AI attribution lines.
