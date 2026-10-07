# GnoRadio

![GnoRadio](docs/img/app.jpg)

GnoRadio is a community radio and an open music player built on [gno.land](https://gno.land).

You can play any album or playlist on demand, or tune into one of the live stations. Everyone hears the same second at the same time, because the schedule lives on-chain. Listening is free and never needs a wallet.

The chain comes in when something matters. You can tip an artist: the tip goes straight to their wallet, minus the share they chose to give the listeners who played them. You can also put a track on air for everyone, with a dedication, now or at a set time, follow someone, buy a concert ticket (an NFT), or chip in to keep the station running. Every one of these is a public transaction anyone can check, and GnoRadio itself pays nothing to run.

The music comes from artists who publish their own tracks and from a hand-picked catalog of Creative Commons and Audius releases, each with proper credits. Artists prove who they are with a code on their own page, checked by a robot, before any tip reaches them ([how](docs/VERIFICATION.md)).

## Features

- **Listen:** live stations (Main, 20 genres, New this week, Listeners' choice), an on-demand library with Your library (saved and liked), jingles, media keys, a tab bar on phones.
- **Take part:** pick what plays next with a dedication, now or booked; likes, playlists, follows; tips with a share for the picker and for whoever shared the link; curator rankings and public listener pages.
- **For artists:** publishing, verification, promo share, sponsored picks, concerts with on-chain tickets checked in at the door by QR code.
- **Safe by design:** dedications checked before they reach the chain, fair pick rules, flat costs, upgradable realms, anonymous visit counts you can turn off.

Every promise, how the code keeps it and which test checks it: [docs/FEATURES.md](docs/FEATURES.md).

## What's in here

- `gno/`: the pure packages, the realms (catalog, radio, tickets) and the gnoweb site (home). A v1 that keeps the data in one realm apart from the rules is in progress ([ARCHITECTURE-v1.md](docs/ARCHITECTURE-v1.md))
- `app/`: the web app (Vite, React, TypeScript)
- `tools/curate/`: the scripts used to pick the launch catalog
- `tools/deploy/`: the onyx deploy scripts
- `docs/`: the features and promises, the spec, the developer notes, how artist verification works, analytics, the v1 architecture and how to deploy ([DEPLOY.md](docs/DEPLOY.md))

## Try it locally

```sh
cd app && npm install && npm run dev
```

The app expects a local gno.land devnet running the realms. [docs/DEVELOPMENT.md](docs/DEVELOPMENT.md) explains how to start one, run the tests and deploy.

## Status

Early days. GnoRadio only runs on a local devnet for now, and nothing is live on a public network yet.

## Licence

Code licence: [CODE LICENCE]. Third-party material (word list, fonts, the tools behind the jingles) is listed in [NOTICE](NOTICE).
