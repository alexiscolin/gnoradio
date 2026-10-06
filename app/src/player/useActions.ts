import { useCallback, useEffect, useMemo, useState } from "react";
import { REALMS, type TxResult, call, explorerURL, isCancel } from "../lib/gno";
import { errorMessage } from "../lib/format";
import type { ConcertEvent, Track } from "../lib/types";
import { useWallet } from "../wallet/useWallet";

/** useActions wraps every on-chain action (each needs the wallet) and its feedback. */
export interface Toast {
  readonly text: string;
  readonly link?: string | undefined;
}

export function useActions(onDone: () => void) {
  const [toast, setToastState] = useState<Toast | null>(null);
  const setToast = useCallback((text: string, link?: string) => { setToastState(text ? { text, link } : null); }, []);
  const wallet = useWallet(setToast);

  useEffect(() => {
    if (!toast) return;
    const id = window.setTimeout(() => { setToastState(null); }, 6000);
    return () => { window.clearTimeout(id); };
  }, [toast]);

  const { ensure } = wallet;
  const run = useCallback(
    async (label: string, fn: (address: string) => Promise<TxResult>) => {
      try {
        const address = await ensure();
        setToast(`${label}… confirm in Adena`);
        const tx = await fn(address);
        setToast(`${label} · in block ${tx.height}`, explorerURL(tx.hash));
        onDone();
      } catch (e) {
        if (isCancel(e)) setToast("Cancelled");
        else setToast(errorMessage(e));
      }
    },
    [ensure, onDone, setToast],
  );

  const id = (n: number) => String(n);

  const api = useMemo(() => ({
    // listeners
    like: (t: Track) => void run("Like", (a) => call(a, REALMS.catalog, "Like", [id(t.id)])),
    follow: (artist: number) => void run("Follow", (a) => call(a, REALMS.catalog, "Follow", [id(artist)])),
    tip: (t: Track, totalUgnot: number, supportPct: number) =>
      void run("Tip", (a) => call(a, REALMS.catalog, "TipWithSupport", [id(t.id), id(supportPct)], totalUgnot)),
    support: (ugnot: number) => void run("Support GnoRadio", (a) => call(a, REALMS.catalog, "SupportGnoRadio", [], ugnot)),
    queue: (t: Track, station: number) => void run("Queue", (a) => call(a, REALMS.radio, "Queue", [id(station), id(t.id)])),
    buyTicket: (e: ConcertEvent) =>
      void run("Ticket", (a) => call(a, REALMS.tickets, "BuyTicket", [id(e.id)], e.price > 0 ? e.price + (e.fee ?? 0) : 0)),
    // studio (admin)
    sync: () => void run("Sync stations", (a) => call(a, REALMS.radio, "Sync", ["20"])),
    curatorQueue: (station: number, trackID: number) => void run("Curator queue", (a) => call(a, REALMS.radio, "CuratorQueue", [id(station), id(trackID)])),
    unqueue: (station: number, trackID: number) => void run("Unqueue", (a) => call(a, REALMS.radio, "Unqueue", [id(station), id(trackID)])),
    dropSlot: (station: number, trackID: number) => void run("Drop from rotation", (a) => call(a, REALMS.radio, "DropSlot", [id(station), id(trackID)])),
    resolveReport: (reportID: number) => void run("Resolve report", (a) => call(a, REALMS.catalog, "ResolveReport", [id(reportID)])),
    hideTrack: (trackID: number, hidden: boolean) => void run(hidden ? "Hide track" : "Restore track", (a) => call(a, REALMS.catalog, "HideTrack", [id(trackID), String(hidden)])),
    setGoal: (ugnot: number) => void run("Monthly goal", (a) => call(a, REALMS.catalog, "SetMonthlyGoal", [id(ugnot)])),
    setFee: (ugnot: number) => void run("Ticket fee", (a) => call(a, REALMS.tickets, "SetServiceFee", [id(ugnot)])),
  }), [run]);
  return useMemo(() => ({ ...api, wallet, toast }), [api, wallet, toast]);
}

export type Actions = ReturnType<typeof useActions>;
