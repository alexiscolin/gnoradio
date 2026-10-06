import { useEffect, useState } from "react";
import { ActivityFeed } from "../components/ActivityFeed";
import { Head, TrackRows } from "../components/common";
import { Composition, Shape } from "../components/Shapes";
import { loadTicketsOf, loadUser } from "../lib/community";
import { gnot, shortAddr } from "../lib/format";
import { GNOWEB } from "../lib/gno";
import type { Activity, Catalog, Navigate, SupportInfo, UserInfo } from "../lib/types";
import type { Actions } from "../player/useActions";
import type { Player } from "../player/usePlayer";

interface Base {
  readonly cat: Catalog;
  readonly go: Navigate;
}

/** Community is where the money and the people are visible. */
export function Community({ cat, go, support, activity, now, onSupport }: Base & {
  readonly support: SupportInfo;
  readonly activity: readonly Activity[];
  readonly now: number;
  readonly onSupport: () => void;
}) {
  const goal = support.goal > 0 ? support.goal : 50 * 1_000_000;
  const pct = Math.min(100, (support.monthTotal / goal) * 100);
  const artists = [...cat.artists.values()].filter((a) => a.owner).sort((a, b) => b.tips - a.tips).slice(0, 8);
  const maxTips = Math.max(1, ...artists.map((a) => a.tips));
  return (
    <section>
      <Head a="Community" b="on-chain" note="Every like, tip and queue below is a public transaction. Nothing is hidden, nothing is taken." />

      <div className="treasury">
        <div className="treasury-txt">
          <span className="lbl">GnoRadio treasury · {support.month || "this month"}</span>
          <span className="big">{gnot(support.monthTotal)}<span className="muted"> / {gnot(goal)}</span></span>
          <div className="bar" role="progressbar" aria-valuenow={Math.round(pct)} aria-valuemin={0} aria-valuemax={100} aria-label="Monthly running costs covered"><i style={{ width: `${String(pct)}%` }} /></div>
          <span className="muted small">{support.supporters} supporters · {gnot(support.total)} since launch. Pays hosting, storage and the indexer.</span>
          <button className="cta yellow" onClick={onSupport}><Shape g="square" size={12} fill="var(--ink)" /> Support GnoRadio</button>
        </div>
        <Composition variant={1} />
      </div>

      <div className="cols">
        <div>
          <h3 className="sub">Live activity</h3>
          <ActivityFeed items={activity} cat={cat} go={go} now={now} />
        </div>
        <div>
          <h3 className="sub">Most supported artists</h3>
          {artists.length === 0 && <p className="muted">No claimed artist yet. Tips open when an artist claims their profile.</p>}
          <div className="bars">
            {artists.map((a) => (
              <button key={a.id} onClick={() => { go({ k: "artist", id: a.id }); }}>
                <span>{a.name}</span>
                <i style={{ width: `${String(Math.max(4, (a.tips / maxTips) * 100))}%` }} />
                <b className="mono">{gnot(a.tips)}</b>
              </button>
            ))}
          </div>
          <h3 className="sub">Top supporters of GnoRadio</h3>
          {support.top.length === 0 && <p className="muted">Be the first.</p>}
          <ol className="top">
            {support.top.map((r, i) => (
              <li key={r.address}><span className="mono muted">{String(i + 1).padStart(2, "0")}</span><span className="mono">{shortAddr(r.address)}</span><b className="mono">{gnot(r.amount)}</b></li>
            ))}
          </ol>
        </div>
      </div>
    </section>
  );
}

/** Me shows what the connected listener did on-chain. */
export function Me({ cat, go, player, actions }: Base & { readonly player: Player; readonly actions: Actions }) {
  const s = actions.wallet.state;
  const address = s.status === "connected" || s.status === "wrong-network" ? s.address : "";
  const [user, setUser] = useState<UserInfo | null>(null);
  const [tickets, setTickets] = useState<{ id: number; event: number; serial: number; attended: boolean }[]>([]);
  useEffect(() => {
    if (!address) return;
    loadUser(address).then(setUser, () => { setUser(null); });
    loadTicketsOf(address).then(setTickets, () => { setTickets([]); });
  }, [address]);

  if (!address) {
    return (
      <section>
        <Head a="Me" note="Connect Adena to see your likes, playlists, tickets and support." />
        <button className="cta" onClick={() => void actions.wallet.connectWallet()}>Connect Adena</button>
      </section>
    );
  }
  const myArtist = user?.artist ? cat.artists.get(user.artist) : undefined;
  return (
    <section>
      <Head a="Me" b={shortAddr(address)} note="Your public footprint on GnoRadio." />
      <div className="stats">
        <div><Shape g="circle" size={14} /><b className="mono">{user?.likes ?? 0}</b><span>likes</span></div>
        <div><Shape g="square" size={14} /><b className="mono">{gnot(user?.tipped ?? 0)}</b><span>given to artists</span></div>
        <div><Shape g="quarter" size={14} /><b className="mono">{user?.follows ?? 0}</b><span>follows</span></div>
        <div><Shape g="triangle" size={14} /><b className="mono">{tickets.length}</b><span>tickets</span></div>
      </div>
      {myArtist && <p className="muted">You are also the artist <button className="link" onClick={() => { go({ k: "artist", id: myArtist.id }); }}>{myArtist.name}</button>.</p>}
      {user && user.playlists.length > 0 && (
        <>
          <h3 className="sub">My playlists</h3>
          {cat.playlists.filter((p) => user.playlists.includes(p.id)).map((p) => (
            <button key={p.id} className="line" onClick={() => { go({ k: "playlist", id: p.id }); }}>{p.title} <span className="muted">· {p.tracks.length} tracks</span></button>
          ))}
        </>
      )}
      <h3 className="sub">My tickets</h3>
      {tickets.length === 0 ? <p className="muted">No ticket yet.</p> : (
        <div className="tickets">
          {tickets.map((tk) => {
            const e = cat.events.find((x) => x.id === tk.event);
            return (
              <article key={tk.id} className="ticket">
                <div><span className="lbl light">Admit one · #{tk.serial}</span><b>{e?.title ?? `Concert ${String(tk.event)}`}</b><span className="muted small">{tk.attended ? "I was there" : "Valid"}</span></div>
                <div className="stub"><Shape g={tk.attended ? "circle" : "square"} size={26} /></div>
              </article>
            );
          })}
        </div>
      )}
      <h3 className="sub">Recently played here</h3>
      <TrackRows tracks={player.queue.flatMap((id) => cat.byId.get(id) ?? []).slice(0, 8)} player={player} />
    </section>
  );
}

/** Studio is the admin and curator desk. Only shown to the catalog admin. */
export function Studio({ cat, actions }: Base & { readonly actions: Actions }) {
  const [station, setStation] = useState(0);
  const [track, setTrack] = useState(cat.tracks[0]?.id ?? 0);
  const [goal, setGoal] = useState("50");
  const [fee, setFee] = useState("0.5");
  const [report, setReport] = useState("");
  const pending = cat.stations.reduce((n, s) => (s.id === 0 ? s.tracks : n), 0);
  return (
    <section>
      <Head a="Studio" note="Program the stations, keep the catalog clean, set the economics. Every action is a public transaction." />
      <div className="studio">
        <div className="panel">
          <h3><Shape g="quarter" size={14} /> Stations</h3>
          <p className="muted small">{cat.tracks.length} tracks in the catalog · {pending} in Main rotation.</p>
          <button className="cta" onClick={actions.sync}>Sync new tracks into the stations</button>
          <label>Station
            <select value={station} onChange={(e) => { setStation(Number(e.target.value)); }}>
              {cat.stations.map((s) => <option key={s.id} value={s.id}>{s.name}</option>)}
            </select>
          </label>
          <label>Track
            <select value={track} onChange={(e) => { setTrack(Number(e.target.value)); }}>
              {cat.tracks.map((t) => <option key={t.id} value={t.id}>{t.title} · {t.artistName}</option>)}
            </select>
          </label>
          <button className="cta" onClick={() => { actions.curatorQueue(station, track); }}>Program next on this station</button>
          <div className="row2">
            <button className="cta" onClick={() => { actions.unqueue(station, track); }}>Unqueue</button>
            <button className="cta red" onClick={() => { actions.dropSlot(station, track); }}>Drop from rotation</button>
          </div>
        </div>
        <div className="panel">
          <h3><Shape g="circle" size={14} /> Moderation</h3>
          <label>Track
            <select value={track} onChange={(e) => { setTrack(Number(e.target.value)); }}>
              {cat.tracks.map((t) => <option key={t.id} value={t.id}>#{t.id} {t.title}</option>)}
            </select>
          </label>
          <div className="row2">
            <button className="cta red" onClick={() => { actions.hideTrack(track, true); }}>Hide</button>
            <button className="cta" onClick={() => { actions.hideTrack(track, false); }}>Restore</button>
          </div>
          <p className="muted small">Hidden tracks leave the stations on the next Sync. They stay on-chain: hidden, not erased.</p>
          <label>Report #<input inputMode="numeric" value={report} onChange={(e) => { setReport(e.target.value.replace(/\D/g, "")); }} /></label>
          <button className="cta" disabled={!report} onClick={() => { actions.resolveReport(Number(report)); setReport(""); }}>Resolve report</button>
          <p className="muted small"><a href={`${GNOWEB}/r/gnoradio/home/v0:moderation`} target="_blank" rel="noreferrer">Open reports on gnoweb</a> · each listener can have 5 open reports.</p>
        </div>
        <div className="panel">
          <h3><Shape g="square" size={14} /> Economics</h3>
          <label>Monthly goal (GNOT)<input inputMode="decimal" value={goal} onChange={(e) => { setGoal(e.target.value); }} /></label>
          <button className="cta" onClick={() => { actions.setGoal(Math.round(Number(goal) * 1_000_000)); }}>Set goal</button>
          <label>Ticket service fee (GNOT, paid by the buyer)<input inputMode="decimal" value={fee} onChange={(e) => { setFee(e.target.value); }} /></label>
          <button className="cta" onClick={() => { actions.setFee(Math.round(Number(fee) * 1_000_000)); }}>Set fee</button>
        </div>
      </div>
    </section>
  );
}
