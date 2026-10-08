// Listener incentives: what a pick and a shared link earn (radio/curators.gno,
// catalog/promo.gno). Every amount here mirrors the realm, which decides.
import { useEffect, useRef, useState } from "react";
import { REALMS, gnoAddress, qjson } from "./gno";
import { type Infer, arr, num, obj, opt, str } from "./guard";
import { gnot } from "./format";
import { hasChecksum, isAddress } from "./proof";
import { loadPicks, type RadioPick } from "./community";
import { isTrack } from "./schemas";
import type { Catalog } from "./types";

/** The cap of an artist's promo share (0% until they set one: catalog defaultPromoPct). */
export const MAX_PROMO = 20;

const REF_KEY = "gnoradio.ref";
/** REF_DAYS: how long a shared link's sharer is kept (a link opened in an in-app browser, then reopened, still counts). */
export const REF_DAYS = 7;

/** captureRef keeps a share link's ?ref=<address> in this browser for REF_DAYS, the last link winning (the app rewrites the URL on load). */
export function captureRef(search: string, now = Date.now()): void {
  const ref = new URLSearchParams(search).get("ref") ?? "";
  if (!hasChecksum(ref)) return; // the realm refuses a ref whose checksum fails: every tip would

  try { localStorage.setItem(REF_KEY, JSON.stringify({ ref, at: now })); } catch { /* private mode: no referrer */ }
}

/** sessionRef is the address whose link brought this browser here in the last REF_DAYS, "" if none. */
export function sessionRef(now = Date.now()): string {
  try {
    const v = JSON.parse(localStorage.getItem(REF_KEY) ?? "null") as { ref?: unknown; at?: unknown } | null;
    return v && typeof v.ref === "string" && hasChecksum(v.ref) && typeof v.at === "number" && now - v.at < REF_DAYS * 864e5 ? v.ref : "";
  } catch { return ""; }
}

/** withRef makes a link earn for me: tips made from it share the artist's promo share. */
export const withRef = (url: string, me: string): string => (isAddress(me) ? `${url}${url.includes("?") ? "&" : "?"}ref=${me}` : url);

/**
 * promoSplit is what a tip of artistUgnot (the artist side, after any GnoRadio
 * extra) sends to the picker and the referrer, as catalog.tip does: neither
 * the tipper nor the artist earns, nobody earns when the tipper picked the
 * track on air, a referrer who is the picker counts once, two of them split
 * the share and the odd ugnot goes to the picker.
 */
export function promoSplit(artistUgnot: number, pct: number, who: { picker: string; ref: string; tipper: string; owner: string }): { toPicker: number; toRef: number } {
  if (who.picker !== "" && who.picker === who.tipper) return { toPicker: 0, toRef: 0 };
  const picker = who.picker !== who.tipper && who.picker !== who.owner ? who.picker : "";
  const ref = isAddress(who.ref) && who.ref !== who.tipper && who.ref !== who.owner && who.ref !== picker ? who.ref : "";
  const share = Math.floor((artistUgnot * pct) / 100);
  if (picker && ref) return { toPicker: share - Math.floor(share / 2), toRef: Math.floor(share / 2) };
  return { toPicker: picker ? share : 0, toRef: ref ? share : 0 };
}

const isCurator = obj({
  address: str, picks: num, tips: num, earned: num, promo: opt(num),
  week: obj({ picks: num, tips: num, earned: num, rank: num }),
});
const isTopCurators = obj({ station: num, since: num, top: arr(obj({ address: str, picks: num, tips: num, earned: num })) });
export type Curator = Infer<typeof isCurator>;
export type TopCurators = Infer<typeof isTopCurators>;

/**
 * PICK_PAY: what an artist refunds per aired sponsored pick, in GNOT
 * (catalog sponsor.gno defaultPickPay, minPickPay, maxPickPay). The default
 * covers a pick's fee and deposit (a sponsored pick and its collect measured 0.189 GNOT).
 */
export const PICK_PAY = { def: 0.2, min: 0.01, max: 0.5 } as const;

/** An artist's sponsored-pick budget (catalog PromoJSON), in ugnot. */
const isPromo = obj({
  artist: num, funder: str, balance: num, reserved: num, free: num, pay: num, perDay: num, today: num,
  funded: num, paid: num, picks: num, offer: num,
});
export type Promo = Infer<typeof isPromo>;
export const loadPromo = (artist: number): Promise<Promo> => qjson(REALMS.catalog, `PromoJSON(${String(artist)})`, isPromo);

/** A wallet's sponsored picks not collected yet (radio SponsoredJSON); block says why it cannot take one, "" if it can. */
// status comes from radio.PickPayoutStatus: "ok" pays (an aired pick always does), "airing", "lapsed" or "none" do not (older realms omit it).
const isSponsored = obj({ block: str, open: arr(obj({ station: num, start: num, track: num, end: num, amount: num, status: opt(str) })) });
export type Sponsored = Infer<typeof isSponsored>;
const loadSponsored = (address: string): Promise<Sponsored> => qjson(REALMS.radio, `SponsoredJSON(${gnoAddress(address)})`, isSponsored);

/** collectable lists the open sponsored picks the realm says pay now (aired in full, not lapsed). */
export const collectable = (s: Sponsored | null): Sponsored["open"] =>
  (s?.open ?? []).filter((p) => p.status === "ok");

/** useSponsored reads me's open sponsored picks, again every minute and when reload changes. */
export function useSponsored(me: string, reload: unknown): Sponsored | null {
  const [s, setS] = useState<Sponsored | null>(null);
  useEffect(() => {
    setS(null);
    if (!me) return;
    let alive = true;
    const load = () => { void loadSponsored(me).then((x) => { if (alive) setS(x); }, () => undefined); };
    load();
    // Not while the tab is hidden: back on screen, it reads at once.
    const id = window.setInterval(() => { if (!document.hidden) load(); }, 60_000);
    const onShow = () => { if (!document.hidden) load(); };
    document.addEventListener("visibilitychange", onShow);
    return () => { alive = false; window.clearInterval(id); document.removeEventListener("visibilitychange", onShow); };
  }, [me, reload]);
  return s;
}

/** ALL_STATIONS reads the weekly top across every station. */
export const ALL_STATIONS = -1;

export const loadCurator = (address: string): Promise<Curator> => qjson(REALMS.radio, `CuratorJSON(${gnoAddress(address)})`, isCurator);

export const loadTopCurators = (station: number): Promise<TopCurators> =>
  qjson(REALMS.radio, `TopCuratorsJSON(${String(station)})`, isTopCurators);

/** A pick of mine on air: the radio's activity feed says where and when, the catalog how long. */
/** MAX_PICK_S: a pick's start plus this is past its end (radio.maxTrack: no track runs longer). */
const MAX_PICK_S = 1200;

export interface LivePick { readonly station: number; readonly track: number; readonly start: number; readonly end: number }

interface Snapshot { readonly pick: LivePick; readonly likes: number; readonly tips: number; readonly earned: number }

async function snapshot(pick: LivePick, me: string): Promise<Snapshot> {
  const [t, c] = await Promise.all([qjson(REALMS.catalog, `TrackJSON(${String(pick.track)})`, isTrack), loadCurator(me)]);
  return { pick, likes: t.likes, tips: t.tips, earned: c.earned };
}

/**
 * usePickOnAir follows the connected wallet's picks on every station. When one
 * starts it returns it (and the browser notifies, if the listener allowed it);
 * once it ends, say() gets what it earned on air: likes and tips the track
 * gained, and the picker's share. now is the chain clock.
 */
// ponytail: the radio feed keeps its last 64 picks, so a pick made long before a busy hour may be missed; an indexer lifts that.
export function usePickOnAir(me: string, cat: Catalog, now: number, say: (text: string) => void): LivePick | null {
  const [mine, setMine] = useState<readonly RadioPick[]>([]);
  useEffect(() => {
    setMine([]);
    if (!me) return;
    let alive = true;
    // Every 20 s while a pick of mine waits or airs (hidden tabs too: that is when the
    // notification matters); otherwise every 2 minutes, enough to see a pick made elsewhere.
    let busy = false;
    let ticks = 0;
    const load = () => {
      void loadPicks().then((ps) => {
        if (!alive) return;
        const own = ps.filter((p) => (p.kind === "queue" || p.kind === "sponsored") && p.by === me);
        busy = own.some((p) => p.start + MAX_PICK_S > Date.now() / 1000);
        setMine(own);
      });
    };
    load();
    const id = window.setInterval(() => { if (busy || ++ticks % 6 === 0) load(); }, 20_000);
    return () => { alive = false; window.clearInterval(id); };
  }, [me]);

  const live = mine
    .map((p) => ({ station: p.station, track: p.track, start: p.start, end: p.start + (cat.byId.get(p.track)?.duration ?? 0) }))
    .find((p) => p.start <= now && now < p.end) ?? null;
  const key = live ? `${String(live.station)}/${String(live.start)}` : "";

  // live is a new object on every render: the effect below runs once per pick (key), reading these.
  const ref = useRef({ live, cat, say });
  ref.current = { live, cat, say };
  useEffect(() => {
    const { live: pick, cat: c } = ref.current;
    if (!pick) return;
    const before = snapshot(pick, me).catch(() => null);
    const title = c.byId.get(pick.track)?.title ?? "Your pick";
    const station = c.stations.find((s) => s.id === pick.station)?.name ?? "the radio";
    if ("Notification" in window && Notification.permission === "granted") {
      new Notification("Your pick is on air", { body: `“${title}” is playing now on ${station}, for everyone tuned in.` });
    }
    return () => {
      // The pick ended (or the wallet changed): read the counts again and tell the result.
      void before.then(async (s) => {
        if (!s) return;
        const after = await snapshot(s.pick, me).catch(() => null);
        if (after) ref.current.say(pickResult(title, s, after));
      });
    };
  }, [key, me]);
  return live;
}

/** pickResult says what a pick earned on air, in one line. Listener counts are not on chain: none here. */
export function pickResult(title: string, before: Pick<Snapshot, "likes" | "tips" | "earned">, after: Pick<Snapshot, "likes" | "tips" | "earned">): string {
  const likes = after.likes - before.likes;
  const tips = after.tips - before.tips;
  const earned = after.earned - before.earned;
  const parts = [
    `${likes > 0 ? "+" : ""}${String(likes)} like${likes === 1 ? "" : "s"}`,
    tips > 0 ? `${gnot(tips)} in tips to the artist` : "no tip",
    earned > 0 ? `you earned ${gnot(earned)}` : "",
  ].filter(Boolean);
  return `Your pick “${title}” played: ${parts.join(" · ")}.`;
}
