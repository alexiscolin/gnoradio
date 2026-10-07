# GnoRadio app

The Library + Live player: a static front end (Vite, React, strict TypeScript) deployed on Netlify, plus a few Netlify functions.

```sh
npm install
npm run dev        # http://127.0.0.1:5173, /rpc is proxied to the devnet at 127.0.0.1:27157
npm run check      # typecheck + lint + tests + build
npm run build      # static build in dist/
```

Reads go through `VITE_RPC`, which defaults to the same-origin `/rpc` path: Vite proxies it in development, Netlify in production (`netlify.toml`). Every variable, and the functions that use them, is listed in [docs/DEVELOPMENT.md](../docs/DEVELOPMENT.md) and `.env.example`.

```
src/lib/         types, gno client (qeval, Adena, sessions, gnokey), catalog loading, formats, legal constants
src/player/      usePlayer (Library / Live in sync), useActions (every on-chain action)
src/components/  player, dial, covers, navigation, sheets
src/views/       screens: Browse (Listen, Stations, Library), Detail (track, artist, album, playlist, concerts),
                 Community (Community, Me, Studio), Contribute, About, Legal
src/wallet/      wallet connection and card
netlify/         functions: artist verification, dedication moderation, optional sync robot; optional edge meta
```

Listening never touches the chain; only actions (like, tip, follow, pick, publish, report) need a wallet.
