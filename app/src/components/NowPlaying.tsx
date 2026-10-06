import { clock, firstNonEmpty, gnot, hostOf, licenseLabel } from "../lib/format";
import type { Catalog, Navigate } from "../lib/types";
import type { Actions } from "../player/useActions";
import { type Player, usePosition } from "../player/usePlayer";
import { Dial } from "./Dial";
import { Shape } from "./Shapes";
import type { SupportTarget } from "./SupportSheet";

interface Props {
  readonly cat: Catalog;
  readonly player: Player;
  readonly actions: Actions;
  readonly saved: { has: (id: number) => boolean; toggle: (id: number) => void };
  readonly open: boolean;
  readonly onClose: () => void;
  readonly go: Navigate;
  readonly openSupport: (t: SupportTarget) => void;
}

export function NowPlaying({ cat, player: p, actions, saved, open, onClose, go, openSupport }: Props) {
  const pos = usePosition(p.audio);
  const t = cat.byId.get(p.current);
  const artist = t ? cat.artists.get(t.artist) : undefined;
  const stationName = cat.stations.find((s) => s.id === p.station)?.name ?? "Main";
  const live = p.mode === "live";
  const upNext = p.entries.filter((e) => e.start > p.chainNow()).slice(0, 3);

  let attribution = "";
  if (t?.origin === "audius") attribution = "Audius · Open Music License";
  else if (t?.origin === "curated") attribution = `${licenseLabel(t.license)} · via ${hostOf(t.source)}`;
  else if (t) attribution = licenseLabel(t.license);

  return (
    <section className={`now${open ? " open" : ""}`} aria-label="Now playing">
      <button className="sheet-close" onClick={onClose} aria-label="Close player">⌄</button>
      <div className="now-top">
        <span className="chip"><Shape g={live ? "circle" : "triangle"} size={9} /> {live ? stationName : "Library"}</span>
        <div className="seg small" role="group" aria-label="Mode">
          <button className={live ? "" : "on"} aria-pressed={!live} onClick={p.toLibrary}>Lib</button>
          <button className={live ? "on live" : ""} aria-pressed={live} onClick={() => { p.goLive(p.station); }}>Live</button>
        </div>
      </div>

      <Dial
        frac={t && t.duration > 0 ? pos / t.duration : 0}
        seconds={pos}
        caption={t ? `of ${clock(t.duration)}${live ? " · live" : ""}` : "nothing playing"}
        live={live}
        onSeek={live ? undefined : p.seek}
      />

      <div className="now-meta">
        {t ? (
          <>
            <button className="title" onClick={() => { go({ k: "track", id: t.id }); }}>{t.title}</button>
            <button className="link muted" onClick={() => { go({ k: "artist", id: t.artist }); }}>{t.artistName}</button>
            <span className="muted small">{attribution}</span>
          </>
        ) : (
          <span className="muted">Pick a track or go live.</span>
        )}
        {p.error && <span className="error small" role="alert">{p.error}</span>}
      </div>

      <div className="controls">
        <button onClick={p.prev} disabled={live} aria-label="Previous track"><svg viewBox="0 0 24 24" width="16" height="16" aria-hidden="true"><path d="M6 5h2v14H6zM20 5v14L9 12z" /></svg></button>
        <button className="play" onClick={p.toggle}>{p.playing ? "Pause" : "Play"}</button>
        <button onClick={p.next} disabled={live} aria-label="Next track"><svg viewBox="0 0 24 24" width="16" height="16" aria-hidden="true"><path d="M16 5h2v14h-2zM4 5v14l11-7z" /></svg></button>
      </div>

      {t && (
        <>
          {artist?.owner ? (
            <button className="support" onClick={() => { openSupport({ kind: "tip", track: t, artist }); }}>
              <Shape g="square" size={14} fill="var(--ink)" />
              <span><b>Support {artist.name}</b><small>{gnot(artist.tips)} raised · 100% to the artist</small></span>
              <span aria-hidden="true">→</span>
            </button>
          ) : t.origin === "audius" ? (
            <a className="support muted-support" href={firstNonEmpty(artist?.source, t.source)} target="_blank" rel="noreferrer">
              <Shape g="square" size={14} fill="var(--ink)" />
              <span><b>Support on Audius</b><small>Tips here open when {t.artistName} claims the profile</small></span>
              <span aria-hidden="true">↗</span>
            </a>
          ) : (
            <div className="support muted-support" aria-disabled="true">
              <Shape g="square" size={14} fill="var(--ink)" />
              <span><b>Tips open soon</b><small>When {t.artistName} claims this profile</small></span>
            </div>
          )}
          <div className="quick">
            <button onClick={() => { actions.like(t); }} aria-label="Like on-chain"><Shape g="circle" size={12} /> Like <span className="mono muted">{t.likes}</span></button>
            <button onClick={() => { saved.toggle(t.id); }} aria-pressed={saved.has(t.id)}><Shape g="triangle" size={12} fill={saved.has(t.id) ? "var(--ink)" : "var(--tick)"} /> {saved.has(t.id) ? "Saved" : "Save"}</button>
            <button onClick={() => { actions.queue(t, live ? p.station : 0); }}><Shape g="quarter" size={12} /> Queue</button>
          </div>
        </>
      )}

      {live && upNext.length > 0 && (
        <div className="upnext">
          <span className="lbl">Up next on {stationName}</span>
          {upNext.map((e) => (
            <div key={`${String(e.track)}-${String(e.start)}`} className="row tiny">
              <span className="mono muted">{new Date(e.start * 1000).toLocaleTimeString([], { hour: "2-digit", minute: "2-digit" })}</span>
              <span>{e.title}</span>
              {e.queued && <span className="tag">by a listener</span>}
            </div>
          ))}
        </div>
      )}
      {!live && (
        <button className="golive" onClick={() => { p.goLive(0); }}><Shape g="circle" size={10} /> Go live on Main</button>
      )}
    </section>
  );
}
