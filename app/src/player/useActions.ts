import { useCallback, useEffect, useMemo, useRef, useState } from "react";
import { forgetName, nameReg } from "../lib/names";
import { arr, num } from "../lib/guard";
import { type Call, REALMS, call, explorerURL, gnoAddress, hasAdena, isCancel, qeval, qjson } from "../lib/gno";
import { inSession, savedSession, sessionCall } from "../lib/session";
import { isFees } from "../lib/schemas";
import { errorMessage } from "../lib/format";
import { type TrackDraft, formatSplits } from "../lib/rules";
import type { ConcertEvent, Track } from "../lib/types";
import { useWallet } from "../wallet/useWallet";

/** useActions wraps every on-chain action (signed with Adena, a session or gnokey) and its feedback. */
export interface Toast {
  readonly text: string;
  readonly link?: string | undefined;
  readonly pending?: boolean | undefined;
}

/**
 * Storage deposit (GNOT) each action locks, measured on a v1.5.0 devnet. Gno charges
 * 100 ugnot per byte stored, which is most of what a listener pays, so we say it
 * before Adena opens. It is returned if the data is later freed (e.g. Unlike).
 */
export const DEPOSIT: Readonly<Record<string, number>> = {
  Like: 0.3,
  Follow: 0.15,
  Queue: 0.1,
  Ticket: 0.95,
  Tip: 0.05,
  "Support GnoRadio": 0.05,
  "Register artist": 0.8,
  "Publish track": 0.4,
  "Publish playlist": 0.3,
  Report: 0.25,
  "Turn on tips": 0.05,
};

/** playlistDeposit: a playlist locks about 0.3 GNOT plus 0.01 per track. */
export const playlistDeposit = (tracks: number): number => Math.round((0.3 + 0.01 * tracks) * 100) / 100;

/** allPages reads 100-id pages until a short one (at most 5,000 ids). */
async function allPages(page: (offset: number) => Promise<number[]>): Promise<number[]> {
  const out: number[] = [];
  for (let o = 0; o < 5000; o += 100) {
    const ids = await page(o);
    out.push(...ids);
    if (ids.length < 100) break;
  }
  return out;
}

const c = (pkg: Call["pkg"], func: string, args: readonly string[], send?: number): Call => ({ pkg, func, args, send });

export function useActions(onDone: () => void) {
  const [toast, setToastState] = useState<Toast | null>(null);
  const setToast = useCallback((text: string, link?: string) => { setToastState(text ? { text, link } : null); }, []);
  const [pending, setPending] = useState("");
  const wallet = useWallet(setToast);

  // What this wallet already likes and follows, so buttons show it (aria-pressed) and don't re-sign.
  const ws = wallet.state;
  const me = ws.status === "connected" || ws.status === "wrong-network" ? ws.address : "";
  const [liked, setLiked] = useState<ReadonlySet<number>>(new Set());
  const [following, setFollowing] = useState<ReadonlySet<number>>(new Set());
  useEffect(() => {
    setLiked(new Set());
    setFollowing(new Set());
    if (!me) return;
    let alive = true;
    const who = gnoAddress(me);
    // The realm serves 100 ids per page; read every page so older likes still show as liked.
    void allPages((o) => qjson(REALMS.catalog, `LikesJSON(${who}, ${String(o)}, 100)`, arr(num)))
      .then((ids) => { if (alive) setLiked(new Set(ids)); }, () => undefined);
    void allPages((o) => qeval(REALMS.catalog, `FollowsPage(${who}, ${String(o)}, 100)`)
      .then((raw) => [...raw.matchAll(/\((\d+) int\)/g)].map((m) => Number(m[1]))))
      .then((ids) => { if (alive) setFollowing(new Set(ids)); }, () => undefined);
    return () => { alive = false; };
  }, [me]);

  useEffect(() => {
    // A pending "confirm in Adena" stays up until the transaction settles; results stay 10s.
    if (!toast || toast.pending) return;
    const id = window.setTimeout(() => { setToastState(null); }, 10_000);
    return () => { window.clearTimeout(id); };
  }, [toast]);

  const { ensure, signer } = wallet;
  // With gnokey (chosen, or no Adena in this browser), an action opens its command to copy instead.
  const [gnokey, setGnokey] = useState<{ readonly label: string; readonly call: Call } | null>(null);
  const closeGnokey = useCallback(() => { setGnokey(null); onDone(); }, [onDone]);
  // One transaction at a time: a double tap must not open two Adena prompts (or pay twice).
  const busy = useRef(false);
  const run = useCallback(
    async (label: string, make: () => Call | Promise<Call>, opts: { readonly deposit?: number; readonly key?: string; readonly after?: (address: string) => void } = {}) => {
      if (signer === "gnokey" || !hasAdena()) {
        try { setGnokey({ label, call: await make() }); } catch (e) { setToast(errorMessage(e)); }
        return;
      }
      if (busy.current) {
        setToast("Finish the transaction waiting in Adena first.");
        return;
      }
      busy.current = true;
      setPending(opts.key ?? label);
      try {
        const address = await ensure();
        const c = await make();
        // A no-send call to a GnoRadio realm goes through the session when one is on: no prompt.
        const quick = inSession(c) && savedSession(address) !== undefined;
        const deposit = opts.deposit ?? DEPOSIT[label];
        const lock = deposit === undefined ? "" : ` · about ${String(deposit)} GNOT locked as storage deposit`;
        setToastState({ text: quick ? `${label}…${lock}` : `${label}… confirm in Adena${lock}`, pending: true });
        const tx = quick ? await sessionCall(address, c) : await call(address, c);
        opts.after?.(address);
        setToast(`${label} · in block ${tx.height}`, explorerURL(tx.hash));
        onDone();
      } catch (e) {
        if (isCancel(e)) setToast("Cancelled");
        else setToast(errorMessage(e));
      } finally {
        busy.current = false;
        setPending("");
      }
    },
    [ensure, signer, onDone, setToast],
  );

  const id = (n: number) => String(n);

  const api = useMemo(() => ({
    // listeners
    like: (t: Track) =>
      void run("Like", () => c(REALMS.catalog, "Like", [id(t.id)]), { key: `like:${id(t.id)}`, after: () => { setLiked((x) => new Set([...x, t.id])); } }),
    unlike: (t: Track) =>
      void run("Unlike", () => c(REALMS.catalog, "Unlike", [id(t.id)]), { key: `like:${id(t.id)}`, after: () => { setLiked((x) => new Set([...x].filter((v) => v !== t.id))); } }),
    follow: (artist: number) =>
      void run("Follow", () => c(REALMS.catalog, "Follow", [id(artist)]), { key: `follow:${id(artist)}`, after: () => { setFollowing((x) => new Set([...x, artist])); } }),
    unfollow: (artist: number) =>
      void run("Unfollow", () => c(REALMS.catalog, "Unfollow", [id(artist)]), { key: `follow:${id(artist)}`, after: () => { setFollowing((x) => new Set([...x].filter((v) => v !== artist))); } }),
    tip: (t: Track, totalUgnot: number, supportPct: number) =>
      void run("Tip", () => c(REALMS.catalog, "TipWithSupport", [id(t.id), id(supportPct)], totalUgnot)),
    support: (ugnot: number) => void run("Support GnoRadio", () => c(REALMS.catalog, "SupportGnoRadio", [], ugnot)),
    queue: (t: Track, station: number, note = "") =>
      void run("Queue", () => (note ? c(REALMS.radio, "QueueWithNote", [id(station), id(t.id), note]) : c(REALMS.radio, "Queue", [id(station), id(t.id)])),
        // A dedication waits 90 s on-chain for the moderation robot: wake it now so
        // it is judged in seconds (the robot's schedule also checks every minute).
        note ? { after: () => { void fetch("/api/moderate", { method: "POST" }).catch(() => undefined); } } : undefined),
    reportNote: (station: number, start: number, after: () => void) => void run("Report", () => c(REALMS.radio, "ReportNote", [id(station), id(start)]), { after }),
    buyTicket: (e: ConcertEvent) =>
      void run("Ticket", async () => {
        // The realm wants exactly price + the current fee: re-read the fee, never trust a cached one.
        const fee = e.price > 0 ? (await qjson(REALMS.tickets, "FeesJSON()", isFees)).serviceFee : 0;
        return c(REALMS.tickets, "BuyTicket", [id(e.id)], e.price > 0 ? e.price + fee : 0);
      }),
    // a gno.land name (r/sys/users), registered through the chain's registrar; no fee on onyx or mainnet
    registerName: (name: string) =>
      void run("Register name", async () => {
        const reg = await nameReg();
        if (!reg) throw new Error("This chain has no name registrar.");
        return c(reg, "Register", [name]);
      }, { after: forgetName }),
    // contributors
    registerArtist: (name: string, bio: string) => void run("Register artist", () => c(REALMS.catalog, "RegisterArtist", [name.trim(), bio.trim()])),
    publishTrack: (d: TrackDraft) =>
      void run("Publish track", () =>
        c(REALMS.catalog, "PublishTrack", [
          d.title.trim(), id(d.genre), d.duration.trim(), d.license, d.cmo || "none", d.credits.trim(),
          d.audio.trim(), d.audioSha.trim().toLowerCase(), d.cover.trim(), d.coverSha.trim().toLowerCase(),
          formatSplits(d.splits), d.rights ? "yes" : "no",
        ])),
    publishPlaylist: (title: string, ids: readonly number[]) =>
      void run("Publish playlist", () => c(REALMS.catalog, "PublishPlaylist", [title.trim(), ids.join(",")]), { deposit: playlistDeposit(ids.length) }),
    report: (kind: "track" | "album" | "artist" | "playlist", target: number, reason: string) =>
      void run("Report", () => c(REALMS.catalog, "Report", [kind, id(target), reason.trim()])),
    claim: (artist: number, proof: string, expires: number, sig: string, after: () => void) =>
      void run("Verify", () => c(REALMS.catalog, "Claim", [id(artist), proof, id(expires), sig]), { after }),
    finalizeClaim: (artist: number) => void run("Turn on tips", () => c(REALMS.catalog, "FinalizeClaim", [id(artist)])),
    // studio (admin)
    sync: () => void run("Sync stations", () => c(REALMS.radio, "Sync", ["20"])),
    curatorQueue: (station: number, trackID: number) => void run("Curator queue", () => c(REALMS.radio, "CuratorQueue", [id(station), id(trackID)])),
    refreshTrack: (trackID: number) => void run("Refresh stations", () => c(REALMS.radio, "Refresh", [id(trackID)])),
    unqueue: (station: number, trackID: number) => void run("Unqueue", () => c(REALMS.radio, "Unqueue", [id(station), id(trackID)])),
    dropSlot: (station: number, trackID: number) => void run("Drop from rotation", () => c(REALMS.radio, "DropSlot", [id(station), id(trackID)])),
    restoreSlot: (station: number, trackID: number) => void run("Restore to rotation", () => c(REALMS.radio, "RestoreSlot", [id(station), id(trackID)])),
    resolveReport: (reportID: number) => void run("Resolve report", () => c(REALMS.catalog, "ResolveReport", [id(reportID)])),
    hideTrack: (trackID: number, hidden: boolean) => void run(hidden ? "Hide track" : "Restore track", () => c(REALMS.catalog, "HideTrack", [id(trackID), String(hidden)])),
    setGoal: (ugnot: number) => void run("Monthly goal", () => c(REALMS.catalog, "SetMonthlyGoal", [id(ugnot)])),
    setFee: (ugnot: number) => void run("Ticket fee", () => c(REALMS.tickets, "SetServiceFee", [id(ugnot)])),
  }), [run]);
  return useMemo(() => ({ ...api, wallet, toast, pending, liked, following, gnokey, closeGnokey }), [api, wallet, toast, pending, liked, following, gnokey, closeGnokey]);
}

export type Actions = ReturnType<typeof useActions>;
