import { track } from "../lib/analytics";
import { useCallback, useEffect, useMemo, useRef, useState } from "react";
import { forgetName, nameReg } from "../lib/names";
import { arr, num } from "../lib/guard";
import { type Call, REALMS, call, explorerURL, gnoAddress, hasAdena, isCancel, qeval, qjson } from "../lib/gno";
import { inSession, sessionCall, usableSession } from "../lib/session";
import { isFees } from "../lib/schemas";
import { errorMessage } from "../lib/format";
import { type TrackDraft, type TrackEdit, formatSplits } from "../lib/rules";
import { dedicationCertificate } from "../lib/moderation";
import { gnokeyAddress } from "../lib/gnokey";
import { isAddress } from "../lib/proof";
import type { ConcertEvent, Track } from "../lib/types";
import { useWallet } from "../wallet/useWallet";

/** useActions wraps every on-chain action (signed with Adena, a session or gnokey) and its feedback. */
export interface Toast {
  readonly text: string;
  readonly link?: string | undefined;
  readonly pending?: boolean | undefined;
}

/**
 * Storage deposit (GNOT) each action locks, measured on the v1 devnet (2026-10-08, 5,000
 * tracks; a listener's first action of a kind costs the most). Gno charges 100 ugnot per
 * byte stored, which is most of what a listener pays, so we say it before Adena opens. It
 * is returned if the data is later freed (e.g. Unlike).
 */
export const DEPOSIT: Readonly<Record<string, number>> = {
  Like: 0.1,
  Follow: 0.05,
  Pick: 0.07,
  // a listener's first pick also creates their curator record (0.22 measured on the v1 devnet)
  "First pick": 0.25,
  "Free pick": 0.15,
  "Fund promo": 0.55,
  Ticket: 0.4, // a listener's first ticket; the next ones less
  Tip: 0.15,
  "Support GnoRadio": 0.15,
  "Register artist": 0.15,
  "Publish track": 0.1, // 730 B with its stations, 1,212 B every 16th (a new homes key): radio z_gas_publish filetests
  "Publish playlist": 0.06,
  Report: 0.05,
  "Turn on tips": 0.05,
};

/** PICK_FEE is a pick's network fee, in GNOT. */
export const PICK_FEE = 0.08;

/** PICK_COST says what a pick costs, from PICK_FEE and DEPOSIT, wherever the app explains it. */
export const PICK_COST = `about ${String(PICK_FEE)} GNOT, plus about ${String(DEPOSIT["Pick"])} GNOT locked as storage deposit (up to ${String(DEPOSIT["First pick"])} for your first)`;

/** playlistDeposit: a playlist locks about 0.06 GNOT plus 0.002 per track. */
export const playlistDeposit = (tracks: number): number => Math.round((0.06 + 0.002 * tracks) * 1000) / 1000;

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

/** The admin's hide function for each kind of content; hiding takes a public reason. */
const HIDE = { track: "HideTrack", album: "HideAlbum", artist: "HideArtist", playlist: "HidePlaylist" } as const;
export type HideKind = keyof typeof HIDE;

const c = (pkg: Call["pkg"], func: string, args: readonly string[], send?: number): Call => ({ pkg, func, args, send });

export function useActions(onDone: (c?: Call) => void) {
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

  const { ensure, signer, ask } = wallet;
  // With gnokey (only when chosen), an action opens its command to copy instead.
  const [gnokey, setGnokey] = useState<{ readonly label: string; readonly call: Call } | null>(null);
  const closeGnokey = useCallback(() => { setGnokey(null); onDone(gnokey?.call); }, [onDone, gnokey]);
  // One transaction at a time: a double tap must not open two Adena prompts (or pay twice).
  const busy = useRef(false);
  const run = useCallback(
    async (label: string, make: (address: string) => Call | Promise<Call>, opts: { readonly deposit?: number; readonly key?: string; readonly after?: (address: string) => void } = {}) => {
      if (signer !== "gnokey" && !hasAdena()) {
        track("wallet_needed", { label });
        ask(); // no wallet here: say what is needed, never a terminal command unasked
        return;
      }
      if (signer === "gnokey") {
        // A dedication is certified for the signing key: the gnokey key's address when given.
        try {
          setGnokey({ label, call: await make(isAddress(gnokeyAddress()) ? gnokeyAddress() : me) });
          track("action", { label, stage: "sent", via: "gnokey" });
        } catch (e) { setToast(errorMessage(e)); }
        return;
      }
      if (busy.current) {
        setToast("Finish the transaction waiting in Adena first.");
        return;
      }
      busy.current = true;
      setPending(opts.key ?? label);
      let via: "adena" | "session" = "adena";
      try {
        const address = await ensure();
        const c = await make(address);
        // A no-send call to catalog or radio goes through the session when one is on (never for a GnoRadio role): no prompt.
        const quick = inSession(c) && await usableSession(address);
        const deposit = opts.deposit ?? DEPOSIT[label];
        const lock = deposit === undefined ? "" : ` · about ${String(deposit)} GNOT locked as storage deposit`;
        setToastState({ text: quick ? `${label}…${lock}` : `${label}… confirm in Adena${lock}`, pending: true });
        via = quick ? "session" : "adena";
        track("action", { label, stage: "sent", via });
        const tx = quick ? await sessionCall(address, c) : await call(address, c);
        track("action", { label, stage: "ok", via });
        opts.after?.(address);
        setToast(`${label} · in block ${tx.height}`, explorerURL(tx.hash));
        onDone(c);
      } catch (e) {
        track("action", { label, stage: isCancel(e) ? "cancelled" : "failed", via });
        if (isCancel(e)) setToast("Cancelled");
        else setToast(errorMessage(e));
      } finally {
        busy.current = false;
        setPending("");
      }
    },
    [ensure, signer, ask, onDone, setToast, me],
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
    // On the radio, or from a shared link, the tip goes through radio.TipOnAir: the radio
    // finds who picked the track on air and the artist's promo share goes to them and to ref.
    tip: (t: Track, totalUgnot: number, supportPct: number, station?: number, ref = "") =>
      void run("Tip", () => station === undefined && ref === ""
        ? c(REALMS.catalog, "TipWithSupport", [id(t.id), id(supportPct)], totalUgnot)
        : c(REALMS.radio, "TipOnAir", [id(station ?? 0), id(t.id), id(supportPct), ref], totalUgnot)),
    setPromo: (pct: number) => void run("Promo share", () => c(REALMS.catalog, "SetPromoShare", [id(pct)])),
    support: (ugnot: number) => void run("Support GnoRadio", () => c(REALMS.catalog, "SupportGnoRadio", [], ugnot)),
    // at > 0 books the pick for that unix time (radio QueueAt and its variants), 0 airs it as soon as possible.
    queue: (t: Track, station: number, note = "", sponsored = false, at = 0) =>
      void run(sponsored ? "Free pick" : "Pick", async (author: string) => {
        const When = at > 0 ? "At" : "";
        const when = at > 0 ? [String(at)] : [];
        // A sponsored pick: the artist refunds it once it has aired (radio sponsor.gno). No dedication.
        if (sponsored) return c(REALMS.radio, `QueueSponsored${When}`, [id(station), id(t.id), ...when]);
        if (!note) return c(REALMS.radio, `Queue${When}`, [id(station), id(t.id), ...when]);
        // The robot judges the dedication before the transaction and signs it (netlify/functions/dedication.mts).
        if (!author) throw new Error("To send a dedication, connect your wallet, or with gnokey give your key's address in the gnokey sheet.");
        const cert = await dedicationCertificate(note, author, station);
        return c(REALMS.radio, `QueueWithNote${When}`, [id(station), id(t.id), ...when, note, String(cert.expires), cert.sig]);
      }),
    collect: (station: number, start: number) => void run("Collect", () => c(REALMS.radio, "ClaimPickPayout", [id(station), id(start)])),
    fundPromo: (ugnot: number) => void run("Fund promo", () => c(REALMS.catalog, "FundPromo", [], ugnot)),
    setPromoPay: (ugnot: number, perDay: number) => void run("Promo payout", () => c(REALMS.catalog, "SetPromoPay", [id(ugnot), id(perDay)])),
    // The budget sits in the data realm's vault, account "catalog/<8-digit artist id>" (catalog sponsor.gno acct).
    withdrawPromo: (artist: number) => void run("Withdraw promo", () => c(REALMS.data, "VaultWithdraw", [`catalog/${id(artist).padStart(8, "0")}`])),
    reportNote: (station: number, start: number, after: () => void) => void run("Report", () => c(REALMS.radio, "ReportNote", [id(station), id(start)]), { after }),
    buyTicket: (e: ConcertEvent) =>
      void run("Ticket", async () => {
        // The realm wants exactly price + the current fee: re-read the fee, never trust a cached one.
        const fee = e.price > 0 ? (await qjson(REALMS.tickets, "FeesJSON()", isFees)).serviceFee : 0;
        return c(REALMS.tickets, "BuyTicket", [id(e.id)], e.price > 0 ? e.price + fee : 0);
      }),
    // The artist cancels their own concert (tickets.CancelEvent): sales stop, refunds are the artist's to make.
    cancelEvent: (e: ConcertEvent) => void run("Cancel concert", () => c(REALMS.tickets, "CancelEvent", [id(e.id)]), { key: `cancel:${id(e.id)}` }),
    // The holder gives a ticket to another wallet (tickets.TransferTicket); a checked-in ticket cannot be given.
    giveTicket: (ticket: number, to: string, after: () => void) =>
      void run("Give ticket", () => c(REALMS.tickets, "TransferTicket", [to.trim(), id(ticket)]), { key: `give:${id(ticket)}`, after }),
    checkIn: (ticket: number, code: string, after: () => void) => void run("Check in", () => c(REALMS.tickets, "CheckIn", [id(ticket), code]), { after }),
    // The holder proves, at the door, that they hold the wallet, with the code the door showed them:
    // CheckIn needs it from the last 10 minutes, with the same code.
    present: (ticket: number, code: string, after: () => void) => void run("Show at the door", () => c(REALMS.tickets, "Present", [id(ticket), code]), { key: `present:${id(ticket)}`, after }),
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
        // radio.PublishTrack publishes through the catalog and puts the track on its stations in one transaction.
        c(REALMS.radio, "PublishTrack", [
          d.title.trim(), id(d.genre), d.duration.trim(), d.license, d.cmo || "none", d.credits.trim(),
          d.audio.trim(), d.audioSha.trim().toLowerCase(), d.cover.trim(), d.coverSha.trim().toLowerCase(),
          formatSplits(d.splits), d.rights ? "yes" : "no",
        ])),
    // The artist edits a track's info and media (radio.EditTrack: a new genre or duration moves it on the
    // stations in the same transaction); license, splits and rights stay as published.
    editTrack: (t: Track, d: TrackEdit, after: () => void) =>
      void run("Edit track", () =>
        c(REALMS.radio, "EditTrack", [
          id(t.id), d.title.trim(), id(d.genre), d.duration.trim(), d.credits.trim(),
          d.audio.trim(), d.audioSha.trim().toLowerCase(), d.cover.trim(), d.coverSha.trim().toLowerCase(),
        ]), { key: `edit:${id(t.id)}`, after }),
    updatePlaylist: (playlist: number, title: string, ids: readonly number[], after: () => void) =>
      void run("Update playlist", () => c(REALMS.catalog, "UpdatePlaylist", [id(playlist), title.trim(), ids.join(",")]), { key: `playlist:${id(playlist)}`, after }),
    // An artist hides or shows again their own track or album (catalog.HideOwn); what the moderator hid stays hidden.
    // A track's station slots then follow (radio.Refresh, a second signature): silent once hidden, back once shown.
    hideOwn: (kind: "track" | "album", target: number, hidden: boolean) =>
      void run(`${hidden ? "Hide" : "Show"} ${kind}`, () => c(REALMS.catalog, "HideOwn", [kind, id(target), String(hidden)]), {
        key: `hide:${kind}:${id(target)}`,
        ...(kind === "track" ? { after: () => { window.setTimeout(() => { void run("Refresh stations", () => c(REALMS.radio, "Refresh", [id(target)])); }, 0); } } : {}),
      }),
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
    // A run of spam reports, 1 to 50 from one id, in one transaction (catalog.ResolveReports).
    resolveReports: (from: number, count: number) => void run("Resolve reports", () => c(REALMS.catalog, "ResolveReports", [id(from), id(count)])),
    // After hiding or restoring an artist: their tracks' station slots follow, a batch per call from offset (radio.RefreshArtist).
    refreshArtist: (artist: number, offset = 0) => void run("Refresh stations", () => c(REALMS.radio, "RefreshArtist", [id(artist), id(offset)])),
    hide: (kind: HideKind, target: number, hidden: boolean, reason: string) =>
      void run(`${hidden ? "Hide" : "Restore"} ${kind}`, () => c(REALMS.catalog, HIDE[kind], [id(target), String(hidden), hidden ? reason.trim() : ""])),
    setGoal: (ugnot: number) => void run("Monthly goal", () => c(REALMS.catalog, "SetMonthlyGoal", [id(ugnot)])),
    setFee: (ugnot: number) => void run("Ticket fee", () => c(REALMS.tickets, "SetServiceFee", [id(ugnot)])),
  }), [run]);
  return useMemo(() => ({ ...api, say: setToast, wallet, toast, pending, liked, following, gnokey, closeGnokey }), [api, setToast, wallet, toast, pending, liked, following, gnokey, closeGnokey]);
}

export type Actions = ReturnType<typeof useActions>;
