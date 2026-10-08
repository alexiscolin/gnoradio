# GnoRadio

![GnoRadio](docs/img/app.jpg)

GnoRadio is a community radio and an open music player built on [gno.land](https://gno.land).

You can play any album or playlist on demand, or tune into one of the live stations. Everyone hears the same second at the same time, because the schedule lives on-chain. Listening is free and never needs a wallet.

The chain comes in when something matters. You can tip an artist: it goes to the artist and their collaborators, minus the promo share the artist chose; 0% to GnoRadio. You can also put a track on air for everyone, with a dedication, now or at a set time, follow someone, buy a concert ticket (an NFT), or support the project. Every one of these is a public transaction anyone can check. Running the stations costs GnoRadio nothing on chain: no robot transacts, and listeners and artists pay their own transactions. The operator pays the deploy and the curated launch catalog ([DEPLOY.md](docs/DEPLOY.md)).

The music comes from artists who publish their own tracks and from a hand-picked catalog of Creative Commons releases, each with proper credits, plus Audius and Jamendo tracks streamed from those platforms (the chain keeps only a reference; titles and names are read live from them). Artists prove they control a page (their Audius profile or their own domain) with a code checked by a robot before any tip reaches them; the domain is shown next to their ✓, and the few profiles the moderator verified say so ([how](docs/VERIFICATION.md)).

## Features

- **Listen:** live stations (Main, 20 genres, New this week, Listeners' choice), an on-demand library with Your library (saved and liked), jingles, media keys, a tab bar on phones.
- **Take part:** pick what plays next with a dedication, now or booked; likes, playlists, follows; tips with a share for the picker and for whoever shared the link; curator rankings and public listener pages.
- **For artists:** publishing and editing tracks (a new track joins its genre station in the same transaction, paid by the artist: GnoRadio runs no robot that transacts), hiding their own work, verification, promo share, sponsored picks, concerts with on-chain tickets that holders can give away, checked in at the door (the holder signs to present the ticket, the artist scans its QR); artists can cancel their own concerts.
- **Safe by design:** dedications checked before they reach the chain, fair pick rules, flat costs, upgradable realms, anonymous visit counts you can turn off.

Every promise, how the code keeps it and which test checks it: [docs/FEATURES.md](docs/FEATURES.md).

## What's in here

- `gno/`: the pure packages, the data realm that holds every record, the rules realms (catalog, radio, tickets) and the gnoweb site (home). The rules can be replaced without moving the data ([ARCHITECTURE-v1.md](docs/ARCHITECTURE-v1.md))
- `app/`: the web app (Vite, React, TypeScript)
- `tools/curate/`: the scripts used to pick the launch catalog
- `tools/deploy/`: deploy (onyx or mainnet) and launch-catalog import scripts
- `docs/`: the features and promises, the spec, the developer notes, how artist verification works, analytics, the architecture and how to deploy ([DEPLOY.md](docs/DEPLOY.md))

## Try it locally

```sh
cd app && npm install && npm run dev
```

The app expects a local gno.land devnet running the realms. [docs/DEVELOPMENT.md](docs/DEVELOPMENT.md) explains how to start one, run the tests and deploy.

## Status

Early days. GnoRadio only runs on a local devnet for now, and nothing is live on a public network yet.

GnoRadio is an independent personal project, not an official gno.land product; not affiliated with Audius, Adena or gno.land.

## Licence

Code licence: [CODE LICENCE]. Third-party material (word list, fonts, the tools behind the jingles) is listed in [NOTICE](NOTICE).
