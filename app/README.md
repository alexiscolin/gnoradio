# GnoRadio app

The Library + Live player: a static front end (Vite, React, strict TypeScript) deployed on Netlify, plus a few Netlify functions.

```sh
npm install
npm run dev        # http://127.0.0.1:5173, /rpc is proxied to the devnet at 127.0.0.1:27157
npm run check      # typecheck + lint + tests + build
npm run build      # static build in dist/
```

`VITE_NETWORK` (dev, onyx or mainnet) sets the chain (`src/lib/network.ts`). Reads go through `VITE_RPC`: the same-origin `/rpc` path that Vite proxies to the devnet in development, the chain's public RPC in production. Every variable, and the functions that use them, is listed in [docs/DEVELOPMENT.md](../docs/DEVELOPMENT.md#app).

```
src/lib/         types, gno client (qeval, Adena, sessions, gnokey), realm paths (realms.ts: the v1 rules
                 realms and the data realm), catalog loading and cache, formats,
                 legal constants, analytics (PostHog, docs/ANALYTICS.md)
src/player/      usePlayer (Library / Live in sync), useActions (every on-chain action), jingles, media session
src/components/  player, dial, covers, navigation (sidebar, phone tab bar), sheets, QR codes
src/views/       screens: Browse (Listen, Stations, Library), Collection (Your library: saved, liked),
                 Detail (track, artist, album, playlist, concerts), Door (ticket check-in from its QR, once the holder presented it),
                 Community (Community, Me, Studio), Listener, Contribute, About, Legal
src/wallet/      wallet connection, card, gno.land name
netlify/         functions: artist verification, dedication moderation, link-preview
                 images (og, rate-limited, canonical URLs only); edge meta (preview tags for bots)
e2e/             Playwright end-to-end and accessibility tests (npm run e2e)
```

Listening never touches the chain; only actions (like, tip, follow, pick, publish, report) need a wallet.
