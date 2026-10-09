// Audience measurement (PostHog Cloud EU, the same project as gnogolf, every
// event marked app=gnoradio): anonymous and first-party, so no banner (the
// CNIL's audience-measurement exemption). No key (VITE_POSTHOG_KEY), nothing
// loads and nothing is sent, as in local dev. posthog-js comes in a chunk of
// its own once the page is idle; what is said before waits for it. Never who:
// no identify(), no replay, no heatmaps, the clicks' text and attributes
// masked, and every event scrubbed of addresses before it goes (clean). A
// visitor who objects (Legal page) is not measured again in this browser.
// docs/ANALYTICS.md lists the events.
import type { CaptureResult, PostHog } from "posthog-js";
import { NICKNAMES } from "./nickname";

const KEY = import.meta.env.VITE_POSTHOG_KEY ?? "";
/** 13 months, the CNIL's longest for an audience id. */
const MAX_DAYS = 390;

type Props = Record<string, string | number | boolean | null | undefined>;

/** GnoRadio's own events: what autocapture and the pageviews can't say. */
export interface Events {
  /** Sound starts: on a station (live) or a track of the library. */
  /** station and genre are names (dashboards read them as they are), not ids. */
  listen: { mode: "live" | "library"; station?: string; genre?: string };
  /** An on-chain action (useActions' label: Like, Pick next, Tip…) as it goes. */
  action: { label: string; stage: "sent" | "ok" | "cancelled" | "failed"; via: "adena" | "session" | "gnokey" };
  /** A link shared, by what it points at. */
  share: { what: string };
  /** The player could not play: no source yet, a file that never answered (dead), or no sound for 6 s. origin: curated, audius, jamendo… */
  player_issue: { kind: "no_source" | "dead" | "not_responding"; origin: string };
  /** Where a shared link went from the share sheet. */
  share_to: { to: string };
  /** A track saved in this browser, or unsaved. */
  save: { on: boolean };
  /** The pick sheet, step by step: open, a track chosen, pushed, or closed at a step without pushing. */
  pick_step: { step: "open" | "track" | "push" | "close"; at?: 1 | 2; station?: string; genre?: string; dedication?: boolean; booked?: boolean; sponsored?: boolean };
  /** A dedication the on-chain word filter refused before signing (never its text). */
  dedication_refused: { by: "filter" };
  /** A library search, by how many tracks it found (never what was typed). */
  search: { results: "0" | "1-9" | "10-99" | "100+" };
  /** How long the first catalog took to show, from page start. */
  load: { what: "catalog"; ms: number };
  /** A call to action followed: on which page, where on it, and where it leads (a view kind, "pick" or "gnoweb"). */
  cta: { page: "features" | "listener"; at: "hero" | "start" | "card" | "more" | "end" | "head"; to: string };
  /** An on-chain action stopped because this browser has no wallet (useActions' label). */
  wallet_needed: { label: string };
  /** What the visitor did in the "you need a wallet" sheet. */
  wallet_sheet: { choice: "install" | "later" | "gnokey" | "close" };
  /** The artist stepper: the step shown (1 profile, 2 track info, 3 rights & publish). */
  artist_step: { at: 1 | 2 | 3 };
  /** The promo video on /features: started, half watched, watched to the end. */
  video: { state: "play" | "half" | "end" };
}

/** A count in a coarse bucket, for events. */
export const bucket = (n: number): "0" | "1-9" | "10-99" | "100+" => (n === 0 ? "0" : n < 10 ? "1-9" : n < 100 ? "10-99" : "100+");

let ph: PostHog | null = null;
let started = false;
const queue: ((p: PostHog) => void)[] = [];

const OFF = "gnoradio.noStats";
let off = false;
/** Whether the visitor objected to the measurement. */
export const optedOut = (): boolean => {
  try {
    return off || localStorage.getItem(OFF) === "1";
  } catch {
    return off;
  }
};
/** Whether measurement can run in this build at all (a key is set). */
export const measured = (): boolean => KEY !== "";

/** The visitor objects: nothing more goes, now or later, and PostHog's id and cookies go. */
export function optOut(): void {
  off = true;
  try { localStorage.setItem(OFF, "1"); } catch { /* storage blocked: this page only */ }
  queue.length = 0;
  if (ph) { ph.opt_out_capturing(); ph.reset(true); }
  try {
    for (const c of document.cookie.split(";")) {
      const name = (c.split("=")[0] ?? "").trim();
      if (/^(ph_|__ph_opt_in_out_)/.test(name)) document.cookie = `${name}=; Max-Age=0; path=/; SameSite=Lax`;
    }
  } catch { /* no cookie access */ }
}

// (a page where it never loads, blocked: the first 200 wait, the rest are dropped)
function run(f: (p: PostHog) => void): void {
  if (!KEY || optedOut()) return;
  if (ph) f(ph);
  else if (queue.length < 200) queue.push(f);
}

/** One of GnoRadio's events. */
export const track = <E extends keyof Events>(event: E, props: Events[E]): void => { run((p) => void p.capture(event, props)); };
/** Said with every event from now on (wallet state, chain…). */
export const register = (props: Props): void => { run((p) => { p.register(props); }); };

// ----------------------------------------------------------------- scrubbing

const G1 = /g1[0-9a-z]{38}/g;
/** A string as it may leave: addresses, gno.land names (nym-…) and a key's hex go; a URL loses its query. */
export function scrub(v: string): string {
  if (/^https?:\/\//.test(v)) {
    try {
      const u = new URL(v);
      u.search = ""; // ?ref= carries an address
      v = u.href;
    } catch { /* not a URL after all */ }
  }
  // A listener page's path, its title (@name, a nickname) and gno.land names: r/sys/users maps a name back to its address.
  return v.replace(/\/listener\/[^/?#\s]+/g, "/listener/…").replace(G1, "g1…").replace(/nym-[a-z0-9._-]+/gi, "nym-…")
    .replace(/@[a-z0-9._-]+/gi, "@…").replace(NICKNAMES, "nickname…").replace(/\b(?:0x)?[0-9a-f]{64,}\b/gi, "hex…");
}
const deep = (v: unknown): unknown =>
  typeof v === "string" ? scrub(v)
  : Array.isArray(v) ? v.map(deep)
  : v && typeof v === "object" ? Object.fromEntries(Object.entries(v).map(([k, x]) => [k, deep(x)]))
  : v;
/** An event scrubbed, every string in it, and marked app=gnoradio (before_send): every event,
 *  the first pageview included, which PostHog sends before any super property is registered.
 *  The project is shared with gnogolf: app is what keeps the two apart. */
export const clean = (e: CaptureResult | null): CaptureResult | null =>
  e && ({ ...e, properties: { ...(deep(e.properties) as object), app: "gnoradio" }, $set: deep(e.$set), $set_once: deep(e.$set_once) } as CaptureResult);

// ------------------------------------------------------------------- loading

/** The init options (tested: what is on, what is off). */
const OPTIONS = {
  api_host: import.meta.env.PROD ? "/e" : "https://eu.i.posthog.com", // the site's own path (netlify.toml): a blocker sees no PostHog
  ui_host: "https://eu.posthog.com",
  person_profiles: "identified_only", // and nobody is identified: anonymous events only
  persistence: "cookie", // first-party, this host only, 13 months at most
  opt_out_persistence_by_default: true,
  cross_subdomain_cookie: false,
  cookie_expiration: MAX_DAYS,
  capture_pageview: "history_change", // the address bar follows the screens
  capture_pageleave: true,
  autocapture: true,
  mask_all_text: true, // names, addresses and dedications on screen
  mask_all_element_attributes: true,
  capture_exceptions: true,
  disable_session_recording: true,
  enable_heatmaps: false,
  disable_surveys: true,
  advanced_disable_flags: true,
  before_send: clean,
} as const;

const sizeOf = (w: number): string => (w < 600 ? "phone" : w < 1024 ? "tablet" : "desktop");

/** Loads PostHog once the page is idle, then sends what was said meanwhile. Nothing without a key or after an objection. */
export function start(chain: string, load: () => Promise<{ default: PostHog }> = () => import("posthog-js")): void {
  if (!KEY || started || optedOut()) return;
  started = true;
  register({ chain, viewport: sizeOf(innerWidth), touch: matchMedia("(pointer: coarse)").matches, locale: navigator.language });
  const go = () =>
    void load()
      .then(({ default: p }) => {
        if (optedOut()) return; // objected while it loaded
        p.init(KEY, {
          ...OPTIONS,
          loaded: (q) => {
            // an id older than 13 months starts again (the cookie is renewed at each visit)
            const day = Math.floor(Date.now() / 864e5);
            const since = Number(q.get_property("since_day"));
            if (since && day - since > MAX_DAYS) q.reset(true);
            q.register_once({ since_day: day });
          },
        });
        ph = p;
        for (const f of queue.splice(0)) f(p);
      })
      .catch(() => undefined); // blocked or offline: GnoRadio goes on without
  if (typeof requestIdleCallback === "function") requestIdleCallback(go, { timeout: 4000 });
  else setTimeout(go, 1000);
}
