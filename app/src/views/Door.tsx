import { useCallback, useEffect, useState } from "react";
import { Crumbs, Who } from "../components/common";
import { Shape } from "../components/Shapes";
import { loadTicketOwner, loadTicketsOf } from "../lib/community";
import { useNames } from "../lib/names";
import type { Catalog, Navigate, OwnedTicket } from "../lib/types";
import type { Actions } from "../player/useActions";

/**
 * DoorView is what the artist sees after scanning a ticket's QR at the door:
 * whose ticket it is, whether it was used, and Check in (tickets.CheckIn, the
 * concert's artist only). The QR names the holder it was shown for, so a ticket
 * given away since reads as not theirs anymore.
 */
export function DoorView({ cat, go, ticket, holder, actions }: { readonly cat: Catalog; readonly go: Navigate; readonly ticket: number; readonly holder: string; readonly actions: Actions }) {
  const [owner, setOwner] = useState<string | null>(null);
  const [tk, setTk] = useState<OwnedTicket | null>(null);
  const show = useNames(owner ? [owner] : []);
  const load = useCallback(() => {
    void loadTicketOwner(ticket).then(async (o) => {
      setOwner(o);
      setTk(o ? (await loadTicketsOf(o)).find((x) => x.id === ticket) ?? null : null);
    }, () => { setOwner(""); });
  }, [ticket]);
  useEffect(load, [load]);

  const e = tk ? cat.events.find((x) => x.id === tk.event) : undefined;
  const [verdict, glyph] =
    owner === null ? ["Checking the ticket…", "quarter"] as const
    : !tk ? ["No such ticket.", "circle"] as const
    : owner !== holder ? ["Not valid: this ticket now belongs to someone else.", "circle"] as const
    : e?.cancelled ? ["Not valid: this concert is cancelled.", "circle"] as const
    : tk.attended ? ["Already checked in.", "circle"] as const
    : ["Valid ticket.", "square"] as const;
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
      <p className={ok ? "door-ok" : "pick-blocked"} role="status">{verdict}</p>
      {ok && (
        <button className="cta" disabled={actions.pending !== ""} onClick={() => { actions.checkIn(ticket, load); }}>
          {actions.pending === "Check in" ? "Checking in…" : "Check in"}
        </button>
      )}
      <p className="muted small">Only the concert's artist can check tickets in, from 12 hours before the start. It is a public transaction; the holder gets the "I was there" stamp.</p>
    </section>
  );
}
