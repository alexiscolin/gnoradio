import { useEffect, useState } from "react";
import { Icon } from "../components/Icons";
import { track } from "../lib/analytics";
import { ago } from "../components/ActivityFeed";
import { Crumbs, Proof, ShareButton, Stats } from "../components/common";
import { hhmm } from "../components/PickNext";
import { Shape } from "../components/Shapes";
import { loadSchedule } from "../lib/catalog";
import { type RadioPick, loadPicks } from "../lib/community";
import { gnot, plural } from "../lib/format";
import { type Curator, loadCurator } from "../lib/incentives";
import { codeURL, gnowebOf } from "../lib/links";
import { useNames } from "../lib/names";
import type { Catalog, Navigate } from "../lib/types";

/** ListenerView is a listener's public page: what they programmed on the radio and what it earned them. */
export function ListenerView({ cat, go, address, me, openPick }: { readonly cat: Catalog; readonly go: Navigate; readonly address: string; readonly me: string; readonly openPick: (station: number) => void }) {
  const name = useNames([address])(address);
  const [curator, setCurator] = useState<Curator | null>(null);
  const [picks, setPicks] = useState<readonly RadioPick[]>([]);
  const [notes, setNotes] = useState<ReadonlyMap<string, string>>(new Map());
  useEffect(() => {
    setCurator(null);
    setPicks([]);
    let alive = true;
    loadCurator(address).then((c) => { if (alive) setCurator(c); }, () => undefined);
    void loadPicks().then((ps) => { if (alive) setPicks(ps.filter((p) => p.by === address)); });
    return () => { alive = false; };
  }, [address]);

  // Dedications live in the schedule only: read it for the stations where a pick of theirs is on air or ahead.
  // ponytail: past dedications are not on chain in any feed; an indexer would keep them.
  const now = Date.now() / 1000;
  const live = [...new Set(picks.filter((p) => p.start + (cat.byId.get(p.track)?.duration ?? 0) > now).map((p) => p.station))].join(",");
  useEffect(() => {
    if (!live) return;
    let alive = true;
    void Promise.all(live.split(",").map((s) => loadSchedule(Number(s), 7200).catch(() => null))).then((scheds) => {
      if (!alive) return;
      const m = new Map<string, string>();
      for (const sc of scheds) for (const e of sc?.entries ?? []) if (e.by === address && e.note) m.set(`${String(sc?.station)}/${String(e.start)}`, e.note);
      setNotes(m);
    });
    return () => { alive = false; };
  }, [live, address]);

  const playlists = cat.playlists.filter((p) => p.owner === address);
  const week = curator?.week;
  return (
    <section>
      <Crumbs trail={[{ label: "Community", to: { k: "community" } }, { label: name }]} go={go} />
      <div className="artist-head">
        <h1>{name}<i className="dot" /></h1>
      </div>
      <a className="mono muted small addr-link" href={gnowebOf({ k: "listener", address })} target="_blank" rel="noreferrer" title="This listener on gno.land">{address} ↗</a>
      <div className="actions inline">
        <ShareButton title={name} refBy={me} {...(curator?.picks ? { text: `${plural(curator.picks, "pick")} on air on GnoRadio. Tune in, it's free.` } : {})} />
        {address === me && <button className="btn" onClick={() => { go({ k: "me" }); }}>Me</button>}
      </div>
      {address !== me && (
        <div className="feat-ctas listener-ctas">
          <button className="cta red" onClick={() => { track("cta", { page: "listener", at: "head", to: "stations" }); go({ k: "stations", live: 0 }); }}>Tune in <Icon name="arrow-right" size={16} className="nudge" /></button>
          <button className="cta blue" onClick={() => { track("cta", { page: "listener", at: "head", to: "pick" }); openPick(0); }}>Pick a track too <Icon name="arrow-right" size={16} className="nudge" /></button>
        </div>
      )}

      <h3 className="sub">Curator</h3>
      <Stats empty="No pick on air yet." items={[
        { g: "quarter", value: curator?.picks ?? 0, shown: String(curator?.picks ?? 0), label: "picks on air" },
        { g: "square", value: curator?.earned ?? 0, shown: gnot(curator?.earned ?? 0), label: "earned as picker" },
        { g: "circle", value: week?.rank ?? 0, shown: `#${String(week?.rank ?? 0)}`, label: `this week · ${plural(week?.picks ?? 0, "pick")}` },
        { g: "triangle", value: curator?.promo ?? 0, shown: gnot(curator?.promo ?? 0), label: "refunded by artists" },
      ]} />

      <h3 className="sub">Recent picks</h3>
      {picks.length === 0 ? <p className="muted">No recent pick.</p> : (
        <ol className="feed">
          {picks.map((p) => {
            const t = cat.byId.get(p.track);
            const station = cat.stations.find((s) => s.id === p.station)?.name ?? "the radio";
            const note = notes.get(`${String(p.station)}/${String(p.start)}`);
            return (
              <li key={`${String(p.station)}-${String(p.start)}-${String(p.at)}`}>
                <Shape g="quarter" size={12} />
                <span className="feed-txt">
                  {t ? <button className="link" onClick={() => { go({ k: "track", id: t.id }); }}>{t.title}</button> : "a track"} on {station}
                  {note && <span className="muted"> · “{note}”</span>}
                </span>
                <span className="mono muted">{p.start > now ? `airs ${hhmm(p.start)}` : ago(p.start, now)}</span>
              </li>
            );
          })}
        </ol>
      )}

      {playlists.length > 0 && (
        <>
          <h3 className="sub">Playlists</h3>
          {playlists.map((p) => (
            <button key={p.id} className="line" onClick={() => { go({ k: "playlist", id: p.id }); }}>{p.title} <span className="muted">· {plural(p.tracks.length, "track")}</span></button>
          ))}
        </>
      )}
      <Proof page={gnowebOf({ k: "listener", address })} code={codeURL("radio")} />
    </section>
  );
}
