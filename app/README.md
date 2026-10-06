# GnoRadio app

Lecteur Library + Live, front statique (Vite + React + TypeScript strict), prêt pour Netlify.

```sh
npm install
npm run dev        # http://127.0.0.1:5173, /rpc proxifié vers le devnet 127.0.0.1:27157
npm run typecheck  # tsc strict (noUncheckedIndexedAccess, exactOptionalPropertyTypes…)
npm run lint       # typescript-eslint strictTypeChecked + react-hooks
npm run build      # dist/ pour Netlify
```

En production (Netlify), définir `VITE_RPC` (ex. `https://rpc.onyx.testnets.gno.land:443`) et `VITE_CHAIN_ID` (`onyx-1`).

```
src/lib/       types, client gno (qeval + Adena), chargement du catalogue, formats, saves locaux
src/player/    usePlayer (Library / Live synchronisé), useActions (like, tip, follow, queue)
src/components lecteur, réglette, pochettes, barres de navigation
src/views/     écrans (Listen, Stations, Library, Search, Saved, Artist, Album, Playlist, Concerts)
```

Écouter ne passe jamais par la chaîne ; seules les actions (like, tip, follow, programmer) demandent Adena.
