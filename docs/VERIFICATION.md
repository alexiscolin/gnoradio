# Artist verification

Tips and paid concert tickets only reach artists who proved who they are.
Nobody reviews anything by hand: a robot checks a page the artist controls,
and the chain does the rest.

## How it works for an artist

1. In the app, open your artist page and press **Verify** (or Contribute ›
   Already on GnoRadio). Connect the wallet that should receive your tips.
2. Copy your code, for example `gnoradio:42:g1abc…`, and paste it:
   - **Audius artists**: in your Audius bio.
   - **Everyone else**: in a plain text file on your own website, at
     `https://yourname.com/.well-known/gnoradio.txt` (for an imported profile,
     on the domain of the page recorded for it). Pages others can comment on
     (Bandcamp, SoundCloud, archive.org…) never count: a stranger could post
     the code there.
3. Press **Check my page**. If the code is there, the robot hands back a
   signed certificate and your wallet submits it (one signature, about
   0.05 GNOT of gas, paid by you): the claim is recorded on-chain.
4. 72 hours later, press **Turn on tips** (one signature). The profile is
   verified and fans can tip it. You can remove the code from your page.

## Why it is safe

- **The proof lives where only the artist can write.** Audius is checked
  through the account that owns the artist's first track (a stable id), not
  through the handle, so a reused handle proves nothing. Elsewhere the proof is
  a file on the artist's own domain; pages others can write on or comment
  (archive.org, Bandcamp, SoundCloud, wikis, GitHub) never count. A file naming
  two wallets for the same artist counts for neither. The robot never fetches a
  name that resolves to a private or internal address.
- **72 hours in public.** `Claim` only records a pending claim. Anyone
  can see it (gnoweb, events) and the admin can `CancelClaim` it. Renaming the
  profile during the wait cancels it.
- **The robot holds no power.** Its key only signs certificates
  (`ClaimMessage`: chain, profile, wallet, proof page, expiry under 2 hours);
  a certificate works for the wallet it names only. It cannot move funds or
  change settings. The admin can revoke it with `SetBot("")` (or replace it):
  every claim still pending under the old key is void at once. The admin can
  also undo a wrong claim on an imported profile with `ResetOwner`.
- **GnoRadio never holds money.** There is no escrow: a tip to an unverified
  artist is refused before any coin moves, and a tip to a verified one reaches
  the artist in the same transaction.

What it cannot stop: someone who hacks an artist's Audius account or website
can claim during the 72 hours if nobody notices. The wait, the public events
and `ResetOwner` limit the damage; no money is at risk before verification.

## Realm API (`gno.land/r/gnoradio/catalog/v0`, `verify.gno`)

| Function | Who | What |
|---|---|---|
| `ProofLine(artistID, wallet)` | read | the code to publish |
| `ClaimMessage(artistID, wallet, proofURL, expires)` | read | what the robot signs |
| `Claim(artistID, proofURL, expires, sig)` | the artist | records a pending claim with the robot's certificate |
| `FinalizeClaim(artistID)` | anyone | applies it after 72 h |
| `CancelClaim(artistID)` | admin | drops a pending claim |
| `ResetOwner(artistID)` | admin | unclaims an imported profile |
| `SetBot(publicKeyHex)` | admin | sets the robot's Ed25519 key (`""` disables it) |
| `ClaimJSON(artistID)` | read | state for the app |
| `ArtistVerified(artistID)` | read | used by `tip` and `tickets.BuyTicket` |

## Running the robot

The robot is a set of Netlify functions sharing one module
(`app/netlify/bot.ts`). It costs GnoRadio almost nothing:

| Function | What it does | Who pays |
|---|---|---|
| `verify.mts` (`/api/verify`) | Reads the proof and signs a certificate (Ed25519) | Nobody: the artist submits it with `catalog.Claim` and pays the gas |
| `dedication.mts` (`/api/dedication`) | Before the transaction: checks a dedication with the on-chain word filter (`safe.Note`) and OpenAI's moderation model, then signs it (`radio.NoteMessage`, valid 10 min). `radio.QueueWithNote` refuses a dedication without that signature | Nobody: the listener sends it with their pick and pays the gas. OpenAI's moderation endpoint is free |
| `sync.mts` (every 30 min, optional) | Keeps Main's flow going when nobody picks | GnoRadio, ~0.02 GNOT per needed Sync; off unless `SYNC_ROBOT=on` (listener picks already feed the radio) |

Both endpoints only answer this site (Origin check) and keep their secrets
server-side. `verify` rereads the chain rather than trust the client; the
dedication text is the one thing sent to OpenAI, and the certificate binds
that exact text. If OpenAI or the key is down, dedications pause; picks
without one still work.

Environment (Netlify, never committed; `app/.env.local` in dev): `BOT_SIGNING_KEY`,
`OPENAI_API_KEY`, and for the optional Sync `SYNC_ROBOT`, `BOT_MNEMONIC`, `BOT_RPC`; see the
table in [DEVELOPMENT.md](DEVELOPMENT.md#app). The public key of `BOT_SIGNING_KEY` goes
on-chain with `catalog.SetBot(<public key hex>)` and `radio.SetModBot(<public key hex>)`.

Locally, `npm run dev` serves `/api/verify` and `/api/dedication` against the
devnet; without the keys they only report what they would do.
