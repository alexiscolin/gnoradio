# Deploying GnoRadio

How GnoRadio goes on a public chain, who holds which key, and what to do once it is live. The
design behind it is in [ARCHITECTURE-v1.md](ARCHITECTURE-v1.md).

## Where it lives

On onyx, the packages go under the deployer's gno.land name, next to gnogolf:

```
gno.land/p/nym-alexiscolin000/gnoradio/...   pure packages (text, svg, store, role, safe, blocks)
gno.land/r/nym-alexiscolin000/gnoradio/...   realms (data, catalog, radio, tickets, home)
```

`tools/deploy/stage.py` copies `gno/` with every `gno.land/{p,r}/gnoradio/` path rewritten to
that namespace (no tests, no devseed). `tools/deploy/onyx.sh` stages, then submits each package
in order with your gnokey key and waits for onyx to enable it before the next:

```sh
tools/deploy/onyx.sh <your gnokey key name> nym-alexiscolin000
```

The app then builds with `VITE_GNORADIO_NS=nym-alexiscolin000/gnoradio` (Netlify environment,
applied to the functions too, so the robot reads the same paths).

## Keys and roles

Whoever deploys holds every role at first. Two of them matter.

| Role | Can | Cannot |
|---|---|---|
| **Owner** (the data realm's, and each rules realm's admin) | propose a new release of the rules (it takes over 72 h after it is on chain and ready), cancel it, pause and resume writes, transfer the role (two steps), renounce it | move anyone's money, skip the 72 h delay, touch the guardian |
| **Guardian** (data realm) | pause writes, cancel a release not yet in force, hand its role to another address (two steps), renounce it | propose, resume, change the owner, move money |

Reads and promo withdrawals keep working while anything is paused.

### Why a guardian, and why another key

GnoRadio holds money (artists' promo budgets in the data realm's vault); gnogolf holds scores,
so it has an owner only. With a guardian on a **different key**, a stolen owner key is not the
end: during the 72 h before a malicious release takes over, the guardian pauses and cancels it.
If owner and guardian are the same key, the guardian protects nothing: whoever steals the key
has both roles.

- **Owner:** your everyday address (`g1mpkp5lm8lwpm0pym4388836d009zfe4maxlqsq`, nym-alexiscolin000).
- **Guardian:** a second address of yours, on a key kept apart: a second Adena account on
  another device, a gnokey key on an offline machine, or a hardware wallet. It is almost never
  used.

At deploy both roles are your everyday address. Move the guardian whenever you like (it can be
done at any time, the code is in place); do it before GnoRadio holds sums that matter.

A stolen guardian key alone can only keep pausing writes (no money moves, reads and withdrawals
go on); the owner then resumes, and the guardian role can be handed to a fresh key.

### Moving the guardian to the second key

Two transactions, on `gno.land/r/nym-alexiscolin000/gnoradio/data`:

1. From the current guardian (your everyday key): `GuardianOffer(<second address>)`.
2. From the second key: `GuardianAccept()`.

Check with `Guardian()` (a read). The owner cannot do or undo this: only the guardian hands
its role on.

### Upgrading the rules later

1. Deploy the new rules realms (`catalog/v2`, …) under the same namespace.
2. As owner: `Propose(<role>, <new realm path>)` for each role in the release.
3. Each new realm calls `Ready()` on chain; 72 h after the last one, the whole release takes
   over at once. The data stays where it is: nothing is copied, no deposit is paid again.
4. During those 72 h anyone can read the new code on gnoweb; the owner or the guardian can
   `Cancel()` it.

### In an emergency

- Bug in the rules: owner or guardian `Pause("", true)` (every role) or `Pause("<role>", true)`;
  the owner resumes with `Pause(..., false)` once fixed, or proposes a fixed release.
- Owner key stolen: the guardian pauses and cancels any release the thief proposes, then you
  move what you can; a new owner can only be set by the current owner (`Offer` / `Accept`).
- `Renounce()` makes the rules permanent for good: no release, no pause, ever. Only for a
  GnoRadio meant to run on its own forever.

## After the realms are live

1. Robot keys: `SetBot` / `SetModBot` with the robot's public key (the private one only in
   Netlify, `BOT_SIGNING_KEY`).
2. Launch catalog: import the curated tracks (`tools/curate`), then sync the stations.
3. Netlify: `VITE_GNORADIO_NS`, `VITE_POSTHOG_KEY`, `BOT_SIGNING_KEY`, `OPENAI_API_KEY`.
4. Before opening to the public: an Audius API key (their terms).
