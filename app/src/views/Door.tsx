import { useCallback, useEffect, useState } from "react";
import { Crumbs, Who } from "../components/common";
import { Shape } from "../components/Shapes";
import { OPENS_BEFORE, PRESENT_WINDOW, doorCode, loadPresentedAt, loadTicket, loadTicketOwner, useEvents } from "../lib/community";
import { useNames } from "../lib/names";
import type { Catalog, Navigate, OwnedTicket } from "../lib/types";
import type { Actions } from "../player/useActions";

/** OVER_AFTER: a concert is over this long after its start; its tickets no longer read as valid. */
const OVER_AFTER = 12 * 3600;

/**
 * DoorView is what the artist sees after scanning a ticket's QR at the door:
 * whose ticket it is, whether it was used, whether its holder presented it, and
 * Check in (tickets.CheckIn, the concert's artist only). The QR is built from
 * public data, so anyone could make one: what proves the person at the door
 * holds the ticket is tickets.Present, signed by the holder's wallet within the
 * last 10 minutes with the door code this page shows after the scan (Show at
 * the door, in Me), which CheckIn requires too. Someone with a copied QR is
 * shown another code, so the holder's own Present does not admit them. The QR
 * names the holder it was shown for, so a ticket given away since reads as not
 * theirs anymore.
 */
export function DoorView({ cat, go, ticket, holder, actions }: { readonly cat: Catalog; readonly go: Navigate; readonly ticket: number; readonly holder: string; readonly actions: Actions }) {
  const [owner, setOwner] = useState<string | null>(null);
  const [tk, setTk] = useState<OwnedTicket | null>(null);
  const [presented, setPresented] = useState(0); // tickets.PresentedAt with this page's code, unix seconds (0: not yet)
  const [code] = useState(doorCode); // a fresh code per scan: the holder signs it in their Present
  const show = useNames(owner ? [owner] : []);
  const load = useCallback(() => {
    void loadTicketOwner(ticket).then(async (o) => {
      const [t, at] = await Promise.all([o ? loadTicket(ticket) : null, loadPresentedAt(ticket, code).catch(() => 0)]);
      setPresented(at);
      setTk(t);
      setOwner(o);
    }, () => { setOwner(""); });
  }, [ticket, code]);
  useEffect(load, [load]);
  // The verdict changes with time alone: re-read and re-draw each minute ("N min ago") and the
  // second the Present's 10 minutes run out, so "Valid ticket" never outlives its window.
  const [tick, setTick] = useState(0);
  useEffect(() => {
    const left = presented + PRESENT_WINDOW - Date.now() / 1000;
    if (presented === 0 || left < 0) return;
    const id = window.setTimeout(() => { setTick((n) => n + 1); load(); }, Math.min(left + 1, 60) * 1000);
    return () => { window.clearTimeout(id); };
  }, [presented, load, tick]);

  // The ticket's own concert, read when it is not in the upcoming list (cancelled, past): until then nothing reads as valid.
  const e = useEvents(cat, tk ? [tk.event] : []).get(tk?.event ?? 0);
  const now = Date.now() / 1000;
  const ago = Math.floor((now - presented) / 60);
  const who = owner ? show(owner) : "";
  const [verdict, glyph] =
    owner === null ? ["Checking the ticket…", "quarter"] as const
    : !tk ? ["No such ticket.", "circle"] as const
    : e === undefined ? ["Checking the ticket…", "quarter"] as const
    : e === null ? ["Not valid: this concert can't be found.", "circle"] as const
    : owner !== holder ? ["Not valid: this ticket now belongs to someone else.", "circle"] as const
    : e.cancelled ? ["Not valid: this concert is cancelled.", "circle"] as const
    : tk.attended ? ["Already checked in.", "circle"] as const
    : now > e.start + OVER_AFTER ? ["Not valid: this concert is over.", "circle"] as const
    : now < e.start - OPENS_BEFORE ? ["Not yet: check-in opens 12 hours before the concert.", "circle"] as const
    : presented === 0 || now - presented > PRESENT_WINDOW ? [`Not presented: ask the holder to tap Show at the door and enter the code ${code}.`, "quarter"] as const
    : [`Valid ticket. Presented ${ago < 1 ? "just now" : `${String(ago)} min ago`} by ${who}.`, "square"] as const;
  const waiting = glyph === "quarter" && owner !== null;
  const ok = glyph === "square";
  return (
    <section className="door">
      <Crumbs go={go} trail={[{ label: "Concerts", to: { k: "concerts" } }, { label: `Ticket #${String(ticket)}` }]} />
      <div className={`ticket door-ticket${ok ? "" : " void"}`}>
        <div>
          <span className="lbl light">Admit one{tk ? ` · #${String(tk.serial)}` : ""}</span>
          <b>{e?.title ?? (tk ? `Concert ${String(tk.event)}` : `Ticket #${String(ticket)}`)}</b>
          {e && <span className="muted small">{e.venue} · {new Date(e.start * 1000).toLocaleString("en-GB", { dateStyle: "medium", timeStyle: "short" })}</span>}
          {owner && <span className="muted small">Held by <Who address={owner} shown={show} go={go} /></span>}
        </div>
        <div className="stub"><Shape g={glyph} size={26} /></div>
      </div>
      {!ok && glyph === "quarter" && owner !== null && <p className="door-code" aria-label={`Door code ${code}`}>Door code <b className="mono">{code}</b></p>}
      <p className={ok ? "door-ok" : "pick-blocked"} role="status">{verdict}</p>
      {ok && (
        <button className="cta" disabled={actions.pending !== ""} onClick={() => { actions.checkIn(ticket, code, load); }}>
          {actions.pending === "Check in" ? "Checking in…" : "Check in"}
        </button>
      )}
      {waiting && <button className="cta ghost" onClick={load}>Check again</button>}
      <p className="muted small">The holder taps Show at the door on their phone, enters the door code shown here and signs it: that proves the wallet is theirs, for 10 minutes. A copied QR gets another code, so it cannot use their signature. Match the name shown here. Only the concert's artist can check tickets in, from 12 hours before the start. It is a public transaction; the holder gets the "I was there" stamp.</p>
    </section>
  );
}
