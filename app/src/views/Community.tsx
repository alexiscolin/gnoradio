import { type ReactNode, useEffect, useMemo, useRef, useState } from "react";
import { SearchPick } from "../components/SearchPick";
import { hhmm } from "../components/PickNext";
import { useNames } from "../lib/names";
import { ActivityFeed, FeedItem, ago } from "../components/ActivityFeed";
import { Empty, Head, Proof, Stats, Who, jumpTo } from "../components/common";
import { CancelConcert } from "./Detail";
import { CHECK_IN } from "../lib/concerts";
import { giftProblem } from "../lib/rules";
import { ProofMark } from "../components/Verify";
import { codeURL, gnowebOf, realmPage, ticketPage, txURL } from "../lib/links";
import { Icon } from "../components/Icons";
import { Shape } from "../components/Shapes";
import { Qr } from "../components/Qr";
import { MineLinks } from "./Collection";
import { viewToPath } from "../lib/router";
import { DOOR_CODE, OPENS_BEFORE, type RadioPick, loadPicks, loadTicketsOf, loadUser, useEvents } from "../lib/community";
import { ALL_STATIONS, type Curator, MAX_PROMO, PICK_PAY, type Promo, type TopCurators, collectable, loadCurator, loadPromo, loadTopCurators, useSponsored } from "../lib/incentives";
import { DEFAULT_GOAL, UGNOT, gnot, plural } from "../lib/format";
import { COSTS } from "../lib/legal";
import { PROMO_ASK } from "../lib/features";
import type { Activity, Catalog, Navigate, SupportInfo, UserInfo } from "../lib/types";
import type { Actions, HideKind } from "../player/useActions";
import type { Saved } from "../lib/saved";

const REFRESH_BATCH = 50; // radio.maxRefreshBatch

interface Base {
  readonly cat: Catalog;
  readonly go: Navigate;
}

/** Community is where the money and the people are visible: who programs the radio, who pays for it. */
export function Community({ cat, go, support, activity, now, onSupport, openPick }: Base & {
  readonly support: SupportInfo;
  readonly activity: readonly Activity[];
  readonly now: number;
  readonly onSupport: () => void;
  readonly openPick: (station: number) => void;
}) {
  const [picks, setPicks] = useState<readonly RadioPick[]>([]);
  const [curators, setCurators] = useState<TopCurators["top"]>([]);
  useEffect(() => { // now ticks with the app's pulse
    void loadPicks().then(setPicks);
    loadTopCurators(ALL_STATIONS).then((r) => { setCurators(r.top); }, () => undefined);
  }, [now]);
  const recent = picks.filter((p) => p.kind === "queue").slice(0, 8);
  const goal = support.goal > 0 ? support.goal : DEFAULT_GOAL;
  const who = useNames([...support.top.map((r) => r.address), ...picks.map((p) => p.by), ...curators.map((c) => c.address)]);
  const pct = Math.min(100, (support.monthTotal / goal) * 100);
  const artists = [...cat.artists.values()].filter((a) => a.owner && a.verified && a.tips > 0).sort((a, b) => b.tips - a.tips).slice(0, 8);
  const maxTips = Math.max(1, ...artists.map((a) => a.tips));
  return (
    <section>
      <Head a="Community" note="Listeners program the radio and support it. Every pick, like and tip below is a public transaction." />
      <Proof page={gnowebOf({ k: "community" })} code={codeURL("support")} />

      <div className="program">
        <Shape g="quarter" size={22} />
        <div><b>The radio is programmed by its listeners</b><span className="muted small">Pick a track and it airs for everyone tuned in. One pick per station per hour.</span></div>
        <button className="cta blue" onClick={() => { openPick(0); }}>Pick next</button>
      </div>
      <div className="cols">
        <div>
          <h3 className="sub">Recent picks</h3>
          {recent.length === 0 && <p className="muted">No pick yet. Yours could be the first thing everyone hears.</p>}
          <ol className="feed lines">
            {recent.map((p) => {
              const t = cat.byId.get(p.track);
              if (!t) return null; // hidden or not loaded: no line without its title
              const station = cat.stations.find((s) => s.id === p.station)?.name ?? "";
              return <FeedItem key={`${p.by}-${String(p.at)}-${String(p.station)}-${String(p.start)}`} g="quarter" line={{ title: t.title, verb: "Picked", station, target: { k: "track", id: t.id } }} by={p.by} shown={who} go={go} when={p.start > now ? `airs ${hhmm(p.start)}` : ago(p.start, now)} />;
            })}
          </ol>
        </div>
        <div>
          <h3 className="sub">Top curators · this week</h3>
          <p className="muted small">One point per pick, one per tip while it plays. When the artist set a promo share, the picker receives it on those tips.</p>
          {curators.length === 0 && <p className="muted">Nobody yet this week. Pick a track to top the chart.</p>}
          <ol className="top">
            {curators.map((c, i) => (
              <li key={c.address}><span className="mono muted">{String(i + 1).padStart(2, "0")}</span><Who address={c.address} shown={who} go={go} /><b className="mono">{plural(c.picks, "pick")} · {gnot(c.earned)}</b></li>
            ))}
          </ol>
        </div>
      </div>

      <div className="treasury">
        <div className="treasury-txt">
          <span className="lbl">GnoRadio treasury · {support.month || "this month"}</span>
          <span className="big">{support.monthTotal > 0 ? <>{gnot(support.monthTotal)}<span className="muted"> / {gnot(goal)}</span></> : <>{gnot(goal)}<span className="muted"> goal this month</span></>}</span>
          <div className="bar" role="progressbar" aria-valuenow={Math.round(pct)} aria-valuemin={0} aria-valuemax={100} aria-label="Share of the monthly goal reached"><i style={{ width: `${String(pct)}%` }} /></div>
          <span className="muted small">{support.supporters > 0 ? `${plural(support.supporters, "supporter")} · ${gnot(support.total)} since launch.` : "No supporter yet: be the first."} Funds the project's work. {COSTS}</span>
          <button className="cta" onClick={onSupport}><Shape g="square" size={12} /> Support GnoRadio</button>
        </div>
      </div>

      <div className="cols">
        <div>
          <h3 className="sub">Live activity</h3>
          <ActivityFeed items={activity} cat={cat} go={go} now={now} />
        </div>
        <div>
          <h3 className="sub">Most supported artists</h3>
          {artists.length === 0 && <p className="muted">No tip yet. Artists who verified their profile can be tipped from the player.</p>}
          <div className="bars">
            {artists.map((a) => (
              <button key={a.id} onClick={() => { go({ k: "artist", id: a.id }); }}>
                <span>{a.name}<ProofMark a={a} /></span>
                <i style={{ width: `${String(Math.max(4, (a.tips / maxTips) * 100))}%` }} />
                <b className="mono">{gnot(a.tips)}</b>
              </button>
            ))}
          </div>
          <h3 className="sub">Top supporters of GnoRadio</h3>
          {support.top.length === 0 && <p className="muted">Be the first.</p>}
          <ol className="top">
            {support.top.map((r, i) => (
              <li key={r.address}><span className="mono muted">{String(i + 1).padStart(2, "0")}</span><Who address={r.address} shown={who} go={go} /><b className="mono">{gnot(r.amount)}</b></li>
            ))}
          </ol>
        </div>
      </div>
    </section>
  );
}

/** PromoSetting lets an artist choose the share of each tip that goes to whoever brought the tipper (catalog SetPromoShare). */
function PromoSetting({ current, onSave }: { readonly current: number; readonly onSave: (pct: number) => void }) {
  const [pct, setPct] = useState(current);
  return (
    <div className={`program${current === 0 ? " promo-ask" : ""}`}>
      <Shape g="quarter" size={22} />
      {current === 0 ? (
        <div><b>Reward your curators?</b><span className="muted small">{PROMO_ASK}</span></div>
      ) : (
        <div>
          <b>Promo share for curators: {current}%</b>
          <span className="muted small">Of each tip on your tracks, this part goes to the listener who picked it on air and whoever shared the link. 0 to {MAX_PROMO}%, shown to tippers before they sign.</span>
        </div>
      )}
      <div className="row2">
        <label><span className="sr">Promo share</span>
          <select className="station-select" value={pct} onChange={(e) => { setPct(Number(e.target.value)); }}>
            {Array.from({ length: MAX_PROMO + 1 }, (_, i) => <option key={i} value={i}>{i}%</option>)}
          </select>
        </label>
        <button className="cta" disabled={pct === current} onClick={() => { onSave(pct); }}>Save</button>
      </div>
    </div>
  );
}

/**
 * PromoBudget lets an artist refund listeners' picks of their tracks (catalog
 * sponsor.gno): fund it, choose the refund per aired pick, withdraw what is
 * not reserved. Only the wallet that funded it can withdraw.
 */
function PromoBudget({ artist, me, actions }: { readonly artist: number; readonly me: string; readonly actions: Actions }) {
  const [b, setB] = useState<Promo | null>(null);
  const [amount, setAmount] = useState("5");
  const [pay, setPay] = useState("");
  useEffect(() => { loadPromo(artist).then(setB, () => { setB(null); }); }, [artist, actions.pending]);
  const refund = Number(pay || (b ? b.pay / UGNOT : PICK_PAY.def));
  // catalog.FundPromo refuses less than one refund (the default one on a new budget).
  const minFund = Math.max(0.1, (b?.pay ?? PICK_PAY.def * UGNOT) / UGNOT);
  return (
    <div className="program">
      <Shape g="square" size={22} />
      <div>
        <b>Promo budget: {gnot(b?.free ?? 0)}{b?.reserved ? ` · ${gnot(b.reserved)} reserved` : ""}</b>
        <span className="muted small">
          Refund listeners who pick your tracks: after a pick has played in full, you refund them {gnot(b?.pay ?? PICK_PAY.def * UGNOT)} ({gnot(PICK_PAY.def * UGNOT)} by default, enough that a sponsored pick costs the listener nothing).
          {b && b.picks > 0 ? ` ${plural(b.picks, "pick")} refunded so far, ${gnot(b.paid)}.` : ""} At most {plural(b?.perDay ?? 10, "sponsored pick")} a day, so no script drains it fast; several wallets of one person can still take that many: that is the cost of the promotion. Withdraw what is not reserved at any time.
        </span>
      </div>
      <div className="row2">
        <label><span className="sr">Amount to add, GNOT</span><input className="mono" inputMode="decimal" value={amount} onChange={(e) => { setAmount(e.target.value); }} size={5} /></label>
        <button className="cta" disabled={!(Number(amount) >= minFund)} title={`At least ${String(minFund)} GNOT: one refund`} onClick={() => { actions.fundPromo(Math.round(Number(amount) * UGNOT)); }}>Add GNOT</button>
      </div>
      <div className="row2">
        <label><span className="sr">Refund per pick, GNOT</span>
          <select className="station-select" value={refund} onChange={(e) => { setPay(e.target.value); }}>
            {[0, PICK_PAY.min, 0.05, 0.1, 0.15, PICK_PAY.def, 0.3, 0.4, PICK_PAY.max].map((v) => <option key={v} value={v}>{v === 0 ? "Paused" : `${String(v)} GNOT per pick`}</option>)}
          </select>
        </label>
        <button className="cta ghost" disabled={!b || Math.round(refund * UGNOT) === b.pay} onClick={() => { actions.setPromoPay(Math.round(refund * UGNOT), b?.perDay ?? 0); }}>Save</button>
        <button className="cta ghost" disabled={b?.funder !== me || b.free <= 0} onClick={() => { actions.withdrawPromo(artist); }}>Withdraw</button>
      </div>
    </div>
  );
}

/**
 * Me shows what the connected listener did on-chain. Without a wallet the same
 * sections show empty, so a visitor sees what connecting fills in.
 */
export function Me({ cat, go, actions, saved, openPick }: Base & { readonly actions: Actions; readonly saved: Saved & { readonly ids: readonly number[] }; readonly openPick: (station: number) => void }) {
  const s = actions.wallet.state;
  const address = s.status === "connected" || s.status === "wrong-network" ? s.address : "";
  const [user, setUser] = useState<UserInfo | null>(null);
  const [tickets, setTickets] = useState<{ id: number; event: number; serial: number; attended: boolean }[]>([]);
  // A ticket for a cancelled or past concert is not in the upcoming list: its own event is read.
  const ticketEvents = useEvents(cat, tickets.map((tk) => tk.event));
  const [curator, setCurator] = useState<Curator | null>(null);
  const [door, setDoor] = useState(0); // the ticket whose QR is shown big
  const [code, setCode] = useState(""); // the door code the staff's screen shows after scanning the QR
  const sponsored = useSponsored(address, actions.pending);
  const show = useNames(address ? [address] : []);
  useEffect(() => {
    if (!address) return;
    loadUser(address).then(setUser, () => { setUser(null); });
    loadCurator(address).then(setCurator, () => { setCurator(null); });
    loadTicketsOf(address).then(setTickets, () => { setTickets([]); });
  }, [address]);

  // Show at the door: the QR first; the staff scans it and their screen shows a door code, which
  // the wallet signs in tickets.Present (CheckIn needs it, with that code, from the last 10 minutes).
  const showAtDoor = (id: number) => { setCode(""); setDoor(id); };

  const connect = () => void actions.wallet.connectWallet();
  // A wallet-only section: its title, a Connect link and one greyed line while no wallet is on.
  const section = (title: string, empty: string, right?: ReactNode) => (
    <>
      <h3 className="sub sub-row" id={anchor(title)}>{title} {address ? right : <button className="link small" onClick={connect}>Connect</button>}</h3>
      {!address && <p className="me-empty">{empty}</p>}
    </>
  );
  const myArtist = user?.artist ? cat.artists.get(user.artist) : undefined;
  const week = curator?.week;
  const ready = collectable(sponsored);
  return (
    <section>
      {address
        ? <Head a="Me" b={show(address)} note="Your public footprint on GnoRadio." right={<button className="btn" onClick={() => { go({ k: "listener", address }); }}>Public page</button>} />
        : <Head a="Me" note="Your likes, picks, playlists, tickets and support, in one place." />}
      {!address && (
        <div className="program">
          <Shape g="circle" size={22} />
          <div><b>Connect to fill this page</b><span className="muted small">Everything below fills in from your wallet's public activity. Saved tracks work without one.</span></div>
          <button className="cta" onClick={connect}>{s.status === "missing" ? "Get a wallet" : "Connect Adena"}</button>
        </div>
      )}
      <div className="actions inline">
        <button className="cta blue" onClick={() => { openPick(0); }}><Icon name="on-air" size={16} /> Pick next</button>
        <button onClick={() => { go({ k: "contribute", path: "listener" }); }}>Make a playlist</button>
      </div>
      <nav className="chips me-nav" aria-label="Sections">
        {ME_SECTIONS.map((t) => <button key={t} className="chip" onClick={() => { jumpTo(anchor(t)); }}>{t.replace(/^My (.)/, (_, c: string) => c.toUpperCase())}</button>)}
      </nav>

      {/* Saves and likes can run into the thousands: they open in Your library, under Library. */}
      <h3 className="sub" id="me-library">My library</h3>
      <MineLinks go={go} saved={saved.ids.length} liked={actions.liked.size} />

      {section("My curator stats", "Your picks and what they earned show up here.")}
      {address && (
        <>
          <Stats empty="No pick on air yet." items={[
            { g: "quarter", value: curator?.picks ?? 0, shown: String(curator?.picks ?? 0), label: "picks on air" },
            { g: "square", value: curator?.earned ?? 0, shown: gnot(curator?.earned ?? 0), label: "earned as picker" },
            { g: "circle", value: week?.rank ?? 0, shown: `#${String(week?.rank ?? 0)}`, label: `this week · ${plural(week?.picks ?? 0, "pick")}` },
            { g: "triangle", value: curator?.promo ?? 0, shown: gnot(curator?.promo ?? 0), label: "refunded by artists" },
          ]} />
          {ready.map((p) => (
            <p key={`${String(p.station)}/${String(p.start)}`} className="pick-blocked" role="status">
              Your free pick “{cat.byId.get(p.track)?.title ?? "a track"}” played.{" "}
              <button className="cta" disabled={actions.pending !== ""} onClick={() => { actions.collect(p.station, p.start); }}>Collect {gnot(p.amount)}</button>
            </p>
          ))}
          <p className="muted small">While your pick plays, each tip to its artist sends you their promo share. Tips through links you share pay you the promo share too, when the artist set one, straight to your wallet (not counted here). Paid by tippers, never by GnoRadio.</p>
        </>
      )}

      {section("My playlists", "Your public playlists show up here.", <button className="cta small" onClick={() => { go({ k: "contribute", path: "listener" }); }}>New playlist</button>)}
      {address && (user && user.playlists.length > 0
        ? cat.playlists.filter((p) => user.playlists.includes(p.id)).map((p) => (
          <button key={p.id} className="line" onClick={() => { go({ k: "playlist", id: p.id }); }}>{p.title} <span className="muted">· {p.tracks.length} tracks</span></button>
        ))
        : <p className="muted small">No playlist yet. Make one from any tracks: it is public, and others can play it.</p>)}

      {section("My tickets", "Your concert tickets show up here.")}
      {address && myArtist && (
        <>
          <p className="more-links">
            <a href={txURL("tickets", "CreateEvent")} target="_blank" rel="noreferrer">Announce a concert (form on gno.land) <Icon name="external" size={12} /></a>
          </p>
          <p className="muted small">{CHECK_IN}</p>
          {cat.events.filter((e) => e.artist === myArtist.id && !e.cancelled).map((e) => (
            <div key={e.id} className="line my-concert">
              <span><b>{e.title}</b> <span className="muted">· {e.venue} · {e.sold}/{e.capacity} sold</span></span>
              <CancelConcert e={e} actions={actions} />
            </div>
          ))}
        </>
      )}
      {address && (tickets.length === 0 ? <Empty text="No ticket yet."><button className="link small" onClick={() => { go({ k: "concerts" }); }}>Find a concert <Icon name="arrow-right" size={14} className="nudge" /></button></Empty> : (
        <div className="tickets">
          {tickets.map((tk) => {
            const e = ticketEvents.get(tk.event) ?? undefined;
            return (
              <article key={tk.id} className="ticket">
                <div>
                  <span className="lbl light">Admit one · #{tk.serial}</span><b>{e?.title ?? `Concert ${String(tk.event)}`}</b>
                  {tk.attended || e?.cancelled
                    ? <span className="muted small">{tk.attended ? "I was there" : "Cancelled: ask the artist for a refund"}</span>
                    : <span className="ticket-row">
                      <button className="link small" disabled={actions.pending !== ""} onClick={() => { showAtDoor(tk.id); }}>Show at the door</button>
                      <GiveTicket ticket={tk.id} me={address} actions={actions} onGiven={() => { setTickets((l) => l.filter((x) => x.id !== tk.id)); }} />
                      <a className="small muted" href={ticketPage(tk.id)} target="_blank" rel="noreferrer" aria-label={`View ticket #${String(tk.serial)} on gno.land, opens a new tab`}>On gno.land <Icon name="external" size={12} className="nudge-out" /></a>
                    </span>}
                </div>
                {tk.attended || e?.cancelled
                  ? <div className="stub"><Shape g={tk.attended ? "circle" : "triangle"} size={26} /></div>
                  : <button className="stub" aria-label={`Show ticket #${String(tk.serial)} at the door`} disabled={actions.pending !== ""} onClick={() => { showAtDoor(tk.id); }}><Qr text={doorURL(tk.id, address)} size={64} label="" /></button>}
              </article>
            );
          })}
        </div>
      ))}

      {door !== 0 && (
        <DoorSheet door={door} start={ticketEvents.get(tickets.find((t) => t.id === door)?.event ?? 0)?.start ?? 0} address={address} code={code} setCode={setCode} actions={actions} onClose={() => { setDoor(0); }} />
      )}

      {section("My support", "What you give to artists and the artists you follow show up here.")}
      {address && (
        <Stats empty="Nothing yet: follow or tip an artist, it shows here." items={[
          { g: "square", value: user?.tipped ?? 0, shown: gnot(user?.tipped ?? 0), label: "given to artists" },
          { g: "quarter", value: user?.follows ?? 0, shown: String(user?.follows ?? 0), label: "follows" },
          { g: "circle", value: user?.likes ?? 0, shown: String(user?.likes ?? 0), label: "likes" },
        ]} />
      )}

      <h3 className="sub" id="me-make-music">Make music</h3>
      {myArtist ? (
        <div className="program">
          <Shape g="triangle" size={22} />
          <div><b>You are the artist {myArtist.name}</b><span className="muted small">{myArtist.tracks.length} tracks · {gnot(myArtist.tips)} received in tips</span></div>
          <div className="row2">
            <button className="cta ghost" onClick={() => { go({ k: "artist", id: myArtist.id }); }}>My page</button>
            <button className="cta" onClick={() => { go({ k: "contribute", path: "artist" }); }}>Publish a track</button>
          </div>
        </div>
      ) : (
        <div className="program">
          <Shape g="triangle" size={22} />
          <div><b>Make music?</b><span className="muted small">Create your artist profile with {address ? "this wallet" : "your wallet"} and publish your tracks. GnoRadio takes nothing from your tips.</span></div>
          <button className="cta" onClick={() => { go({ k: "contribute", path: "artist" }); }}>Become an artist</button>
        </div>
      )}
      {myArtist?.verified && <PromoSetting key={myArtist.promo} current={myArtist.promo} onSave={actions.setPromo} />}
      {myArtist?.verified && address && <PromoBudget artist={myArtist.id} me={address} actions={actions} />}

      <p className="more-links">
        <button className="link" onClick={() => { go({ k: "concerts" }); }}>Concerts</button>
        <button className="link" onClick={() => { go({ k: "contribute" }); }}>Contribute</button>
        <button className="link" onClick={() => { go({ k: "about" }); }}>About</button>
        <button className="link" onClick={() => { go({ k: "legal" }); }}>Legal · Privacy · Terms</button>
      </p>
    </section>
  );
}

/**
 * DoorSheet shows a ticket's QR big, in a modal dialog (top layer: above the
 * player and the tab bar); Esc, the close button or a tap outside close it.
 */
function DoorSheet({ door, start, address, code, setCode, actions, onClose }: {
  readonly door: number; readonly start: number; readonly address: string; readonly code: string; readonly setCode: (c: string) => void; readonly actions: Actions; readonly onClose: () => void;
}) {
  const ref = useRef<HTMLDialogElement>(null);
  useEffect(() => {
    const d = ref.current;
    if (d && !d.open && typeof d.showModal === "function") d.showModal();
    return () => { d?.close(); };
  }, []);
  return (
    <dialog ref={ref} className="qr-sheet" aria-label="Ticket QR code" onCancel={(e) => { e.preventDefault(); onClose(); }} onClick={(e) => { if (e.target === e.currentTarget) onClose(); }}>
      <button className="x qr-close" onClick={onClose} aria-label="Close"><Icon name="close" /></button>
      <Qr text={doorURL(door, address)} size={280} label={`QR code of ticket ${String(door)}`} />
      <b>Show this at the door</b>
      <span className="muted small">The artist scans it and their screen shows a door code. Enter it and sign: they check you in within 10 minutes.</span>
      {Date.now() / 1000 < start - OPENS_BEFORE
        ? <span className="small" role="status">Not yet: check-in opens 12 hours before the concert.</span>
        : <div className="row2">
        <label className="field">Door code<input className="mono" inputMode="numeric" maxLength={8} value={code} onChange={(e) => { setCode(e.target.value.replace(/\D/g, "")); }} /></label>
        <button className="cta" disabled={!DOOR_CODE.test(code) || actions.pending !== ""} onClick={() => { actions.present(door, code, () => { setCode(""); }); }}>
          {actions.pending === `present:${String(door)}` ? "Confirm in Adena…" : "Sign"}
        </button>
      </div>}
    </dialog>
  );
}

/** GiveTicket gives a ticket to another wallet (tickets.TransferTicket), after the realm's checks on the address. */
function GiveTicket({ ticket, me, actions, onGiven }: { readonly ticket: number; readonly me: string; readonly actions: Actions; readonly onGiven: () => void }) {
  const [open, setOpen] = useState(false);
  const [to, setTo] = useState("");
  if (!open) return <button className="link small" disabled={actions.pending !== ""} onClick={() => { setOpen(true); }}>Give</button>;
  const problem = giftProblem(to.trim(), me);
  return (
    <span className="give">
      <label className="field">Give to<input className="mono" value={to} placeholder="g1…" spellCheck={false} autoCapitalize="off" aria-invalid={to !== "" && problem !== ""} onChange={(e) => { setTo(e.target.value); }} /></label>
      {to !== "" && problem && <span className="small" role="alert">{problem}</span>}
      <span className="row2">
        <button className="cta yellow" disabled={problem !== "" || actions.pending !== ""} onClick={() => { actions.giveTicket(ticket, to, onGiven); }}>
          {actions.pending === `give:${String(ticket)}` ? "Confirm in Adena…" : "Give ticket"}
        </button>
        <button className="cta ghost" onClick={() => { setOpen(false); setTo(""); }}>Keep</button>
      </span>
    </span>
  );
}

// A ticket's QR opens its door page, for the holder it was shown by.
const doorURL = (ticket: number, holder: string) => location.origin + viewToPath({ k: "door", ticket, holder });

// The Me sections, in page order, for the jump links under the actions.
const ME_SECTIONS = ["My library", "My curator stats", "My playlists", "My tickets", "My support", "Make music"];
const anchor = (title: string) => `me-${title.replace("My ", "").toLowerCase().replace(/ /g, "-")}`;

/** NotFound stands in for a page that does not exist or is not for this wallet, with a way home. */
export function NotFound({ go, text }: { readonly go: Navigate; readonly text: string }) {
  return (
    <section className="not-found">
      <Head a="Not here" note={text} />
      <p className="row2">
        <button className="cta" onClick={() => { go({ k: "listen" }); }}>Back to Listen</button>
        <button className="cta ghost" onClick={() => { go({ k: "library", genre: 0 }); }}>Open the Library</button>
      </p>
    </section>
  );
}

/** Studio is the admin and curator desk. Only shown to the catalog admin. */
export function Studio({ cat, actions }: Base & { readonly actions: Actions }) {
  const [station, setStation] = useState(0);
  const [track, setTrack] = useState(0);
  const [modKind, setModKind] = useState<HideKind>("track");
  const [modId, setModId] = useState(0);
  const [modReason, setModReason] = useState("");
  const [refreshAt, setRefreshAt] = useState(0); // the next batch of an artist's tracks (radio.RefreshArtist, 50 a call)
  useEffect(() => { setRefreshAt(0); }, [modId, modKind]);
  const trackItems = useMemo(() => cat.tracks.map((t) => ({ id: t.id, label: t.title, sub: `#${String(t.id)} · ${t.artistName}` })), [cat.tracks]);
  const modItems = useMemo(() => {
    const sub = (id: number, by = "") => `#${String(id)}${by ? ` · ${by}` : ""}`;
    switch (modKind) {
      case "track": return trackItems;
      case "album": return cat.albums.map((al) => ({ id: al.id, label: al.title, sub: sub(al.id, cat.artists.get(al.artist)?.name) }));
      case "artist": return [...cat.artists.values()].map((a) => ({ id: a.id, label: a.name, sub: sub(a.id) }));
      case "playlist": return cat.playlists.map((pl) => ({ id: pl.id, label: pl.title, sub: sub(pl.id) }));
    }
  }, [modKind, trackItems, cat.albums, cat.artists, cat.playlists]);
  const [goal, setGoal] = useState("50");
  const [fee, setFee] = useState("0.5");
  const [report, setReport] = useState("");
  return (
    <section>
      <Head a="Studio" note="Program the stations, keep the catalog clean, set the economics. Every action is a public transaction." />
      <div className="studio">
        <div className="panel">
          <h3><Shape g="quarter" size={14} /> Stations</h3>
          <p className="muted small">{cat.tracks.length} tracks in the catalog. Publishing and imports put each track on its stations in the same transaction.</p>
          {cat.pending > 0
            ? <button className="cta" onClick={actions.sync}>Sync {cat.pending} tracks into the stations</button>
            : <p className="ok small"><Shape g="circle" size={8} fill="var(--blue)" /> Every track is in its stations.</p>}
          <label>Station
            <select value={station} onChange={(e) => { setStation(Number(e.target.value)); }}>
              {cat.stations.map((s) => <option key={s.id} value={s.id}>{s.name}</option>)}
            </select>
          </label>
          <SearchPick label="Track" items={trackItems} value={track} onChange={setTrack} placeholder="Search a track" />
          <button className="cta" disabled={!track} onClick={() => { actions.curatorQueue(station, track); }}>Program next on this station</button>
          <div className="row2">
            <button className="cta" disabled={!track} onClick={() => { actions.unqueue(station, track); }}>Unqueue</button>
            <button className="cta red" disabled={!track} onClick={() => { actions.dropSlot(station, track); }}>Drop from rotation</button>
          </div>
          <button className="cta" disabled={!track} onClick={() => { actions.restoreSlot(station, track); }}>Restore to rotation</button>
        </div>
        <div className="panel">
          <h3><Shape g="circle" size={14} /> Moderation</h3>
          <label>Type
            <select value={modKind} onChange={(e) => { setModKind(e.target.value as HideKind); setModId(0); }}>
              <option value="track">Track</option>
              <option value="album">Album</option>
              <option value="artist">Artist</option>
              <option value="playlist">Playlist</option>
            </select>
          </label>
          <SearchPick label="Find" items={modItems} value={modId} onChange={setModId} placeholder={`Search a ${modKind}`} />
          <label className="field">Number<input inputMode="numeric" placeholder="12" value={modId || ""} onChange={(e) => { setModId(Number(e.target.value.replace(/\D/g, ""))); }} /><span className="hint-line">Hidden items are not in the search: type their number to restore them.</span></label>
          <label className="field">Reason<input maxLength={200} placeholder="Copyright notice from the rights holder" value={modReason} onChange={(e) => { setModReason(e.target.value); }} /><span className="hint-line">Public and permanent: shown as "Removed by moderation: …".</span></label>
          <div className="row2">
            <button className="cta red" disabled={!modId || modReason.trim().length < 4} onClick={() => { actions.hide(modKind, modId, true, modReason); }}>Hide</button>
            <button className="cta" disabled={!modId} onClick={() => { actions.hide(modKind, modId, false, ""); }}>Restore</button>
          </div>
          {modKind === "track" && <button className="cta" disabled={!modId} onClick={() => { actions.refreshTrack(modId); }}>Refresh its station slots</button>}
          {modKind === "artist" && <button className="cta" disabled={!modId} onClick={() => { actions.refreshArtist(modId, refreshAt); setRefreshAt((o) => o + REFRESH_BATCH); }}>Refresh its tracks' station slots{refreshAt > 0 ? ` · next batch from ${String(refreshAt + 1)}` : ""}</button>}
          <p className="muted small">After hiding or restoring a track, Refresh updates its slots in the stations. Hidden content stays on-chain: hidden, not erased.</p>
          <label className="field">Report number<input inputMode="numeric" placeholder="12" value={report} onChange={(e) => { setReport(e.target.value.replace(/\D/g, "")); }} /></label>
          <div className="row2">
            <button className="cta" disabled={!report} onClick={() => { actions.resolveReport(Number(report)); setReport(""); }}>Resolve report</button>
            <button className="cta ghost" disabled={!report} onClick={() => { actions.resolveReports(Number(report), 50); setReport(""); }}>Resolve 50 from it</button>
          </div>
          <p className="muted small"><a href={realmPage("home", "moderation")} target="_blank" rel="noreferrer">Open reports on gnoweb</a> · each listener can have 5 open reports.</p>
        </div>
        <div className="panel">
          <h3><Shape g="square" size={14} /> Economics</h3>
          <label className="field">Monthly goal<span className="with-suffix"><input inputMode="decimal" value={goal} placeholder="50" onChange={(e) => { setGoal(e.target.value); }} /><span>GNOT</span></span></label>
          <button className="cta" onClick={() => { actions.setGoal(Math.round(Number(goal) * UGNOT)); }}>Set goal</button>
          <label className="field">Ticket service fee<span className="with-suffix"><input inputMode="decimal" value={fee} placeholder="0.5" onChange={(e) => { setFee(e.target.value); }} /><span>GNOT</span></span><span className="hint-line">Paid by the buyer, on top of the artist's price. At most 10 GNOT.</span></label>
          <button className="cta" onClick={() => { actions.setFee(Math.round(Number(fee) * UGNOT)); }}>Set fee</button>
        </div>
      </div>
    </section>
  );
}
