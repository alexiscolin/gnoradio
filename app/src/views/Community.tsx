import { useEffect, useMemo, useState } from "react";
import { SearchPick } from "../components/SearchPick";
import { hhmm } from "../components/PickNext";
import { useNames } from "../lib/names";
import { ActivityFeed, ago } from "../components/ActivityFeed";
import { Head, Proof, TrackRows } from "../components/common";
import { codeURL, gnowebOf, realmPage } from "../lib/links";
import { Shape } from "../components/Shapes";
import { type RadioPick, listenerPage, loadPicks, loadTicketsOf, loadUser, topProgrammers } from "../lib/community";
import { DEFAULT_GOAL, UGNOT, gnot, plural, shortAddr } from "../lib/format";
import { tracksOf } from "../lib/catalog";
import type { Activity, Catalog, Navigate, SupportInfo, UserInfo } from "../lib/types";
import type { Actions } from "../player/useActions";
import type { Player } from "../player/usePlayer";

interface Base {
  readonly cat: Catalog;
  readonly go: Navigate;
}

/** Listener names a wallet and links to its public page on gnoweb. */
function Listener({ address, shown }: { readonly address: string; readonly shown: (a: string) => string }) {
  return <a className="mono who" href={listenerPage(address)} target="_blank" rel="noreferrer" title="Listener page on gno.land">{shown(address)}</a>;
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
  useEffect(() => { void loadPicks().then(setPicks); }, [now]); // now ticks with the app's pulse
  const programmers = topProgrammers(picks, now);
  const recent = picks.filter((p) => p.kind === "queue").slice(0, 8);
  const goal = support.goal > 0 ? support.goal : DEFAULT_GOAL;
  const who = useNames([...support.top.map((r) => r.address), ...picks.map((p) => p.by)]);
  const pct = Math.min(100, (support.monthTotal / goal) * 100);
  const artists = [...cat.artists.values()].filter((a) => a.owner && a.verified).sort((a, b) => b.tips - a.tips).slice(0, 8);
  const maxTips = Math.max(1, ...artists.map((a) => a.tips));
  return (
    <section>
      <Head a="Community" b="on-chain" note="Listeners program the radio and keep it on air. Every pick, like and tip below is a public transaction." />
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
          <ol className="feed">
            {recent.map((p) => {
              const t = cat.byId.get(p.track);
              const station = cat.stations.find((s) => s.id === p.station)?.name ?? "the radio";
              return (
                <li key={`${p.by}-${String(p.at)}`}>
                  <Shape g="quarter" size={12} />
                  <span className="feed-txt">
                    <Listener address={p.by} shown={who} /> put{" "}
                    {t ? <button className="link" onClick={() => { go({ k: "track", id: t.id }); }}>{t.title}</button> : "a track"} on {station}
                  </span>
                  <span className="mono muted">{p.start > now ? `airs ${hhmm(p.start)}` : ago(p.start, now)}</span>
                </li>
              );
            })}
          </ol>
        </div>
        <div>
          <h3 className="sub">Top programmers · this week</h3>
          {programmers.length === 0 && <p className="muted">Nobody yet this week. Pick a track to top the chart.</p>}
          <ol className="top">
            {programmers.map((r, i) => (
              <li key={r.by}><span className="mono muted">{String(i + 1).padStart(2, "0")}</span><Listener address={r.by} shown={who} /><b className="mono">{plural(r.picks, "pick")}</b></li>
            ))}
          </ol>
        </div>
      </div>

      <div className="treasury">
        <div className="treasury-txt">
          <span className="lbl">GnoRadio treasury · {support.month || "this month"}</span>
          <span className="big">{gnot(support.monthTotal)}<span className="muted"> / {gnot(goal)}</span></span>
          <div className="bar" role="progressbar" aria-valuenow={Math.round(pct)} aria-valuemin={0} aria-valuemax={100} aria-label="Monthly running costs covered"><i style={{ width: `${String(pct)}%` }} /></div>
          <span className="muted small">{plural(support.supporters, "supporter")} · {gnot(support.total)} since launch. Pays hosting, storage and the indexer.</span>
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
              <li key={r.address}><span className="mono muted">{String(i + 1).padStart(2, "0")}</span><Listener address={r.address} shown={who} /><b className="mono">{gnot(r.amount)}</b></li>
            ))}
          </ol>
        </div>
      </div>
    </section>
  );
}

/** Me shows what the connected listener did on-chain. */
export function Me({ cat, go, player, actions, savedIds }: Base & { readonly player: Player; readonly actions: Actions; readonly savedIds: readonly number[] }) {
  const s = actions.wallet.state;
  const address = s.status === "connected" || s.status === "wrong-network" ? s.address : "";
  const [user, setUser] = useState<UserInfo | null>(null);
  const [tickets, setTickets] = useState<{ id: number; event: number; serial: number; attended: boolean }[]>([]);
  useEffect(() => {
    if (!address) return;
    loadUser(address).then(setUser, () => { setUser(null); });
    loadTicketsOf(address).then(setTickets, () => { setTickets([]); });
  }, [address]);

  // Saved tracks live in this browser: shown with or without a wallet.
  const savedBlock = (
    <>
      <h3 className="sub">Saved</h3>
      {savedIds.length === 0 ? <p className="muted">Save a track with the bookmark in the player. Stored in this browser only.</p> : <TrackRows tracks={tracksOf(cat, savedIds)} player={player} />}
      <p className="more-links">
        <button className="link" onClick={() => { go({ k: "concerts" }); }}>Concerts</button>
        <button className="link" onClick={() => { go({ k: "contribute" }); }}>Contribute</button>
        <button className="link" onClick={() => { go({ k: "about" }); }}>About</button>
      </p>
    </>
  );
  if (!address) {
    return (
      <section>
        <Head a="Me" note="Connect Adena to see your likes, playlists, tickets and support." />
        <button className="cta" onClick={() => void actions.wallet.connectWallet()}>Connect Adena</button>
        {savedBlock}
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
        <div><Shape g="square" size={14} /><b className="mono">{tickets.length}</b><span>tickets</span></div>
      </div>
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
          <div><b>Make music?</b><span className="muted small">Create your artist profile with this wallet and publish your tracks. Tips go 100% to you.</span></div>
          <button className="cta" onClick={() => { go({ k: "contribute", path: "artist" }); }}>Become an artist</button>
        </div>
      )}
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
      {savedBlock}
    </section>
  );
}

/** Studio is the admin and curator desk. Only shown to the catalog admin. */
export function Studio({ cat, actions }: Base & { readonly actions: Actions }) {
  const [station, setStation] = useState(0);
  const [track, setTrack] = useState(0);
  const [modTrack, setModTrack] = useState(0);
  const trackItems = useMemo(() => cat.tracks.map((t) => ({ id: t.id, label: t.title, sub: `#${String(t.id)} · ${t.artistName}` })), [cat.tracks]);
  const [goal, setGoal] = useState("50");
  const [fee, setFee] = useState("0.5");
  const [report, setReport] = useState("");
  return (
    <section>
      <Head a="Studio" note="Program the stations, keep the catalog clean, set the economics. Every action is a public transaction." />
      <div className="studio">
        <div className="panel">
          <h3><Shape g="quarter" size={14} /> Stations</h3>
          <p className="muted small">{cat.tracks.length} tracks in the catalog · {cat.pending} waiting to be synced into the stations.</p>
          {cat.pending > 0
            ? <button className="cta" onClick={actions.sync}>Sync new tracks into the stations</button>
            : <p className="ok small"><Shape g="circle" size={8} fill="var(--blue)" /> Every track is in its stations.</p>}
          <p className="muted small">Each Sync adds up to 20 tracks, so one transaction stays cheap; run it again while tracks are waiting.</p>
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
          <SearchPick label="Track" items={trackItems} value={modTrack} onChange={setModTrack} placeholder="Search a track" />
          <div className="row2">
            <button className="cta red" disabled={!modTrack} onClick={() => { actions.hideTrack(modTrack, true); }}>Hide</button>
            <button className="cta" disabled={!modTrack} onClick={() => { actions.hideTrack(modTrack, false); }}>Restore</button>
          </div>
          <button className="cta" disabled={!modTrack} onClick={() => { actions.refreshTrack(modTrack); }}>Refresh its station slots</button>
          <p className="muted small">After hiding or restoring, Refresh updates the track's slots in the stations. Hidden tracks stay on-chain: hidden, not erased.</p>
          <label className="field">Report number<input inputMode="numeric" placeholder="12" value={report} onChange={(e) => { setReport(e.target.value.replace(/\D/g, "")); }} /></label>
          <button className="cta" disabled={!report} onClick={() => { actions.resolveReport(Number(report)); setReport(""); }}>Resolve report</button>
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
