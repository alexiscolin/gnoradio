# Artist verification

Tips and paid concert tickets only reach artists who proved who they are.
Usually a robot checks a page the artist controls and the chain does the
rest. The moderator can also verify a profile by giving it to the wallet that
proved it (`AssignArtist`): curated imports are verified only that way.

## How it works for an artist

1. In the app, open your artist page and press **Verify** (or Contribute ›
   Already on GnoRadio). Connect the wallet that should receive your tips.
2. Copy your code, for example `gnoradio:42:g1abc…`, and paste it:
   - **Audius artists**: in your Audius bio.
   - **Everyone else**: in a plain text file on your own website, at
     `https://yourname.com/.well-known/gnoradio.txt`. A curated import cannot
     be verified on the site it was imported from (ccMixter, say): the admin
     assigns it (`AssignArtist`). Pages others can comment on (Bandcamp,
     SoundCloud, archive.org…) never count: a stranger could post the code
     there.
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
  name that resolves to a private or internal address. `Claim` takes a proof
  on a plain host only (no user info or port), and that host (`ProofHost`,
  `"proofHost"` in the artist JSON) is shown next to the ✓: a ✓ proves control
  of that page, not a legal identity. A profile the moderator verified has no
  proof host; the app says "✓ verified by the GnoRadio moderator" instead.
- **72 hours in public.** `Claim` only records a pending claim. Anyone
  can see it (gnoweb, events) and the admin can `CancelClaim` it. Renaming the
  profile during the wait cancels it.
- **The robot holds no power.** Its key only signs certificates
  (`ClaimMessage`: chain, GnoRadio deployment (its data realm), profile, wallet, proof page, expiry under 2 hours);
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

## Realm API (`gno.land/r/gnoradio/catalog/v1`, `verify.gno`)

| Function | Who | What |
|---|---|---|
| `ClaimMessage(artistID, wallet, proofURL, expires)` | read | what the robot signs |
| `Claim(artistID, proofURL, expires, sig)` | the artist | records a pending claim with the robot's certificate |
| `FinalizeClaim(artistID)` | anyone | applies it after 72 h |
| `CancelClaim(artistID)` | admin | drops a pending claim |
| `ResetOwner(artistID)` | admin | unclaims an imported profile |
| `AssignArtist(artistID, owner)` (`artists.gno`) | admin | gives an unclaimed profile to its artist and verifies it |
| `SetBot(publicKeyHex)` | admin | sets the robot's Ed25519 key (`""` disables it) |
| `ClaimJSON(artistID)` | read | state for the app |
| `ArtistVerified(artistID)` | read | used by `tip` and `tickets.BuyTicket` |
| `ProofHost(artistID)` | read | the host of a verified artist's proof, shown next to the ✓ (`""` when the moderator verified it) |
| `PendingClaims(offset, limit)` | read | claims in their 72 h wait (home's moderation page) |

## Running the robot

The robot is a set of Netlify functions sharing one module
(`app/netlify/bot.ts`). It holds no account and sends no transaction, so it
costs GnoRadio nothing on chain:

| Function | What it does | Who pays |
|---|---|---|
| `verify.mts` (`/api/verify`) | Reads the proof and signs a certificate (Ed25519) | Nobody: the artist submits it with `catalog.Claim` and pays the gas |
| `dedication.mts` (`/api/dedication`) | Before the transaction: checks a dedication with the on-chain word filter (`safe.Note`) and OpenAI's moderation model, then signs it (`radio.NoteMessage`, valid 10 min). `radio.QueueWithNote` refuses a dedication without that signature | Nobody: the listener sends it with their pick and pays the gas. OpenAI's moderation endpoint is free |

Both endpoints only answer this site (Origin check) and keep their secrets
server-side. `verify` rereads the chain rather than trust the client; the
dedication text is the one thing sent to OpenAI, and the certificate binds
that exact text. A muted author (`radio.MutedUntil`) gets a 422 before
anything is sent to OpenAI. If OpenAI or the key is down, dedications pause;
picks without one still work.

Environment (Netlify, never committed; `app/.env.local` in dev): `BOT_SIGNING_KEY`,
`OPENAI_API_KEY`, `BOT_RPC` (the chain it reads); see the
table in [DEVELOPMENT.md](DEVELOPMENT.md#app). The public key of `BOT_SIGNING_KEY` goes
on-chain with `catalog.SetBot(<public key hex>)` and `radio.SetModBot(<public key hex>)`.

Locally, `npm run dev` serves `/api/verify` and `/api/dedication` against the
devnet; without the keys they only report what they would do.
