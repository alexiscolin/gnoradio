# GnoRadio

Lecteur de musique et radio communautaire, on-chain sur gno.land. Interface en anglais.

- Spécification v0.3 : [docs/SPEC.md](docs/SPEC.md)
- Dossier (artifact) : https://claude.ai/artifact/WBWAyzE3AZtMNJDtkeEenM
- Canvas de design : https://claude.ai/artifact/DwJvjv3xLsJbKJ8FwgRKCY

## Contenu

```
gno/p/gnoradio/blocks/v0     rotation en blocs (package pur)
gno/r/gnoradio/catalog/v0    artistes, morceaux, albums, playlists, likes, follows, tips
gno/r/gnoradio/radio/v0      13 stations, rotations, programmation
gno/r/gnoradio/tickets/v0    concerts, billets GRC721
gno/r/gnoradio/home/v0       site gnoweb
app/                         dApp (Vite + React + TS), voir app/README.md
tools/curate/                sélection du catalogue de lancement (voir son README)
legacy/v0.2/                 première version, conservée pour référence
```

## Tester

```sh
export GNOROOT=~/go/pkg/mod/github.com/gnolang/gno@v1.5.0 GNOHOME=~/.cache/gno-toolchains/onyx-v1.5.0/gnohome
G=~/.cache/gno-toolchains/onyx-v1.5.0/gno
for d in gno/p/gnoradio/blocks/v0 gno/r/gnoradio/{catalog,radio,tickets,home}/v0; do $G lint ./$d && $G test ./$d; done
```

Devnet local (gnodev v1.5.0, compilé depuis le tag) : RPC `127.0.0.1:27157`, gnoweb `http://127.0.0.1:8911/r/gnoradio/home/v0`.

Rien n'est déployé sur un réseau public avant la recette.
