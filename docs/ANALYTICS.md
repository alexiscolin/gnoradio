# Analytics

Anonymous audience measurement on PostHog Cloud EU (`app/src/lib/analytics.ts`), in the same
project as gnogolf: every event carries `app = gnoradio`. It runs only in a build with
`VITE_POSTHOG_KEY` set (the project's public, write-only key, in Netlify's environment);
without it nothing is loaded and nothing is sent, as in local dev.

## Privacy: the CNIL audience-measurement exemption, no banner

- One anonymous first-party cookie on this host only, 13 months at most (`since_day` resets an older id).
- Visitors are told on the Legal page and can object there in one click ("don't measure my
  visits"): kept in this browser (`localStorage` `gnoradio.noStats`), it stops what is sent at
  once, drops PostHog's id and cookies, and posthog-js is not loaded again.
- Nobody is identified (`person_profiles: "identified_only"`, no `identify()`); no session
  replay, no heatmaps; autocapture with every element's text and attributes masked.
- Every event is scrubbed before it leaves (`before_send: clean`): URLs lose their query (`?ref=`
  carries an address), and any `g1…` address, `nym-…` name or 64-hex string is cut.
- The IP is discarded by the project setting. A dedication's text is never in an event.

A public build reaches PostHog EU through the site's own `/e` path (`netlify.toml`): a blocker
sees no third party and the CSP needs none. posthog-js is imported once the page is idle.

## Kept apart from gnogolf

The project is shared with gnogolf. `app = gnoradio` is set on every event in `before_send`
(the first pageview included, sent before any super property), so every GnoRadio insight
filters on it. gnogolf's events have no `app` yet: filter them with `app is not set` (or
`$host`), or add `app = gnogolf` the same way in its `web/lib/analytics.ts`.

## Said with every event

| property | what |
|---|---|
| `app` | `gnoradio` |
| `chain` | the chain id (onyx-1, dev) |
| `viewport` (phone/tablet/desktop), `touch`, `locale` | the device |
| `wallet` | the wallet state: missing, idle (not connected), connecting, connected, wrong-network |
| `since_day` | the day the anonymous id was made |

## Events

| event | properties | when |
|---|---|---|
| `$pageview`, `$pageleave` | (PostHog's) | each screen, as the address bar follows them |
| `listen` | `mode` (live/library), `station` | a station is tuned in, or a library list starts |
| `action` | `label` (Like, Pick next, Tip, Ticket…), `stage` (sent/ok/cancelled/failed), `via` (adena/session/gnokey) | every on-chain action |
| `share` | `what` (the screen kind shared: track, artist, stations…, or page) | a Share button |
| `save` | `on` | a track saved or unsaved in this browser |
| `pick_step` | `step` (open/track/push/close), `at` (the step it was on), `dedication`, `booked`, `sponsored` | the pick sheet's funnel |
| `dedication_refused` | `by` (filter) | the on-chain word filter refused a dedication before signing (never its text) |
| `search` | `results` (0, 1-9, 10-99, 100+) | a library search settled (never what was typed) |
| `load` | `what` (catalog), `ms` | the first catalog shown, from page start |
| `$exception` | (PostHog's) | an error the page did not catch |

## Dashboard "GnoRadio" (every insight filtered on app = gnoradio)

1. Visitors: unique users per day, last 30 days; breakdown by `viewport`.
2. Pages: `$pageview` count by `$pathname` (top 10), last 7 days.
3. Listening: `listen` per day, breakdown by `mode`; share of visitors with a `listen` (unique users of `listen` / unique users of `$pageview`).
4. Stations: `listen` where mode = live, breakdown by `station` (top 10).
5. On-chain actions: `action` where stage = ok per day, breakdown by `label`.
6. Transaction outcomes: `action` breakdown by `stage` (sent, ok, cancelled, failed), and by `via`.
7. Pick funnel: `pick_step` open → track → push (step property), 7-day window, conversion per step; plus `pick_step` close breakdown by `at`.
8. Dedications: `pick_step` push where dedication = true vs false; `dedication_refused` per day.
9. Sharing and saves: `share` breakdown by `what`; `save` where on = true per day.
10. Search: `search` breakdown by `results` (how often it finds nothing).
11. Speed: `load` median and p90 of `ms`, by `viewport`.
12. Errors: `$exception` per day, top messages.
