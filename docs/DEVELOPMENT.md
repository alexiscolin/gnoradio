# Development

## Layout

```
gno/p/gnoradio/blocks/v0     rotation stored in blocks (pure package)
gno/r/gnoradio/catalog/v0    artists, tracks, albums, playlists, likes, follows, tips, treasury
gno/r/gnoradio/radio/v0      13 stations, rotations, listener and curator queue
gno/r/gnoradio/tickets/v0    concerts and GRC721 tickets
gno/r/gnoradio/home/v0       the gnoweb site
app/                         web app (Vite + React + strict TypeScript)
tools/curate/                launch catalog selection (see its README)
legacy/v0.2/                 first single-realm version, kept for reference
docs/SPEC.md                 full product and technical spec (French)
```

The realms target gno.land v1.5.0, the release running on onyx and mainnet.

## Realm tests

Use a toolchain that matches the chain:

```sh
export GNOROOT=~/go/pkg/mod/github.com/gnolang/gno@v1.5.0
export GNOHOME=~/.cache/gno-toolchains/onyx-v1.5.0/gnohome
G=~/.cache/gno-toolchains/onyx-v1.5.0/gno
for d in gno/p/gnoradio/blocks/v0 gno/r/gnoradio/{catalog,radio,tickets,home}/v0; do
  $G lint ./$d && $G test ./$d
done
```

## Local devnet

`gnodev` built from the v1.5.0 tag, on non-default ports:

```sh
gnodev local -empty-blocks -no-watch \
  -node-rpc-listener 127.0.0.1:27157 -web-listener 127.0.0.1:8911 -chain-id dev \
  -extra-root ./gno \
  -paths gno.land/r/gnoradio/home/v0,gno.land/r/gnoradio/catalog/v0,gno.land/r/gnoradio/radio/v0,gno.land/r/gnoradio/tickets/v0,gno.land/p/gnoradio/blocks/v0 \
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

Build-time variables:

| Variable | Meaning | Production |
|---|---|---|
| `VITE_RPC` | RPC used for reads | `/rpc` (proxied by Netlify) |
| `VITE_CHAIN_ID` | chain the wallet must be on | `onyx-1` |
| `VITE_WALLET_RPC` | RPC given to Adena | `https://rpc.onyx.testnets.gno.land:443` |
| `VITE_GNOWEB` | gnoweb base for links | `https://onyx.testnets.gno.land` |

The app is a static site. `app/netlify.toml` holds the proxy, CSP and cache headers.

## Deploying

Nothing is deployed to a public network yet. Before onyx:

1. Register the `gnoradio` namespace.
2. Deploy `blocks`, then `catalog`, `radio`, `tickets` and `home`.
3. Call `TransferAdmin` on each realm to hand admin to the owner's address.

## Git hooks

After cloning, enable the repo hooks once:

```sh
git config core.hooksPath .githooks
```

`commit-msg` rejects co-author and AI attribution lines.
