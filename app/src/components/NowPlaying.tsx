import { Icon } from "./Icons";
import { useNames } from "../lib/names";
import { useEffect, useRef, useState } from "react";
import { clock, firstNonEmpty } from "../lib/format";
import type { Catalog, Navigate } from "../lib/types";
import type { Actions } from "../player/useActions";
import { type Player, usePosition } from "../player/usePlayer";
import { Help } from "./Help";
import { Dial } from "./Dial";
import { Shape } from "./Shapes";
import type { SupportTarget } from "./SupportSheet";
import { tippable } from "./Verify";

interface Props {
  readonly cat: Catalog;
  readonly player: Player;
  readonly actions: Actions;
  readonly saved: { has: (id: number) => boolean; toggle: (id: number) => void };
  readonly open: boolean;
  readonly onClose: () => void;
  readonly go: Navigate;
  readonly openPick: (station: number, track?: number) => void;
  readonly openSupport: (t: SupportTarget) => void;
}

export function NowPlaying({ cat, player: p, actions, saved, open, onClose, go, openSupport, openPick }: Props) {
  const pos = usePosition(p.audio);
  const closeRef = useRef<HTMLButtonElement>(null);
  // On mobile the open player is a modal: focus moves in, Escape closes it, the rest is inert.
  useEffect(() => {
    if (!open) return;
    const modal = window.matchMedia("(max-width: 900px)").matches;
    if (!modal) return;
    const back = document.activeElement instanceof HTMLElement ? document.activeElement : null;
    const others = [...document.querySelectorAll<HTMLElement>(".shell > :not(.now)")];
    for (const el of others) el.inert = true;
    closeRef.current?.focus();
    // A dialog opened from the sheet (PickNext, Support) handles its own Escape: close one layer at a time.
    const onKey = (e: KeyboardEvent) => { if (e.key === "Escape" && !document.querySelector("dialog[open]")) onClose(); };
    window.addEventListener("keydown", onKey);
    return () => {
      for (const el of others) el.inert = false;
      window.removeEventListener("keydown", onKey);
      back?.focus();
    };
  }, [open, onClose]);
  const t = cat.byId.get(p.current);
  const artist = t ? cat.artists.get(t.artist) : undefined;
  const stationName = cat.stations.find((s) => s.id === p.station)?.name ?? "Main";
  const live = p.mode === "live";
  const chainNow = p.chainNow();
  const upNext = p.entries.filter((e) => e.start > chainNow).slice(0, 2);
  // On the radio, the track on air may be a listener's pick: credit them.
  const onAir = live ? p.entries.find((e) => e.start <= chainNow && e.end > chainNow && e.track === p.current) : undefined;
  // Report is for listeners: not the author, and once per dedication (each report costs a fee).
  const [reported, setReported] = useState<ReadonlySet<string>>(new Set());
  const ws = actions.wallet.state;
  const me = ws.status === "connected" || ws.status === "wrong-network" ? ws.address : "";
  const noteKey = onAir ? `${String(p.station)}/${String(onAir.start)}` : "";
  const canReport = onAir !== undefined && (me === "" || onAir.by !== me) && !reported.has(noteKey);
  const who = useNames([...upNext, ...(onAir ? [onAir] : [])].map((e) => e.by));

  return (
    <section className={`now${open ? " open" : ""}`} aria-label="Now playing" {...(open ? { role: "dialog", "aria-modal": true } : {})}>
      <button ref={closeRef} className="sheet-close" onClick={onClose} aria-label="Close player"><Icon name="chevron-down" size={26} /></button>
      <div className="now-top">
        {live
          ? <button className="chip station-chip" onClick={() => { go({ k: "stations" }); }} title="Change station"><Shape g="circle" size={9} />{stationName}</button>
          : <span className="chip">Library</span>}
        <span className="seg small" role="group" aria-label="Mode">
          <button className={live ? "" : "on"} aria-pressed={!live} onClick={p.toLibrary} title="Library: play any track you choose, just for you">Lib</button>
          <button className={live ? "on live" : ""} aria-pressed={live} onClick={() => { p.goLive(p.station); }} title="Live: tune into a station, everyone hears the same second">Live</button>
        </span>
      </div>

      <Dial
        frac={t && t.duration > 0 ? pos / t.duration : 0}
        seconds={pos}
        buffering={p.buffering}
        caption={t ? `of ${clock(t.duration)}${live ? " · live" : ""}` : "nothing playing"}
        live={live}
        onSeek={live ? undefined : p.seek}
      />

      <div className="now-meta">
        <div className="now-titles">
          {t ? (
            <>
              <button className="title" onClick={() => { go({ k: "track", id: t.id }); }}>{t.title}</button>
              <span className="now-by">
                <button className="link muted" onClick={() => { go({ k: "artist", id: t.artist }); }}>{t.artistName}</button>
                {onAir?.queued && <span className="picked-by"><Shape g="quarter" size={9} fill="var(--blue)" /> {onAir.by ? `picked by ${who(onAir.by)}` : "curator pick"}</span>}
              </span>
              {onAir?.note && (
                <div className={`dedic${canReport ? "" : " solo"}`} role="note" aria-label={`Dedication: ${onAir.note}`}>
                  <span className="dedic-tag" aria-hidden="true">♥</span>
                  <span className="dedic-track" aria-hidden="true">
                    {/* Twice, so the ticker loops without a gap. */}
                    <span className="dedic-run">{onAir.note} · from {who(onAir.by)}<i /> {onAir.note} · from {who(onAir.by)}<i /></span>
                  </span>
                  {canReport && <button className="dedic-report" onClick={() => { actions.reportNote(p.station, onAir.start, () => { setReported((s) => new Set(s).add(noteKey)); }); }} title="Report this dedication · three reports hide it at once">Report</button>}
                </div>
              )}
            </>
          ) : (
            <span className="muted">Pick a track or go live.</span>
          )}
          {p.error && <span className="error small" role="alert">{p.error}</span>}
        </div>
      </div>

      {t && (
        <div className="actrow">
            <button
              className={`act like${actions.liked.has(t.id) ? " on" : ""}`}
              aria-pressed={actions.liked.has(t.id)}
              disabled={actions.pending === `like:${String(t.id)}`}
              aria-label={`${actions.liked.has(t.id) ? "Unlike" : "Like"} · on-chain · ${String(t.likes)} likes`}
              title={`${actions.liked.has(t.id) ? "Unlike" : "Like"} · on-chain · ${String(t.likes)} likes`}
              onClick={() => { if (actions.liked.has(t.id)) actions.unlike(t); else actions.like(t); }}
            >
              <Shape g="circle" size={12} fill={actions.liked.has(t.id) ? "#fff" : "var(--red)"} /><span>Like {t.likes}</span>
            </button>
            <button className={`act${saved.has(t.id) ? " on" : ""}`} aria-pressed={saved.has(t.id)} aria-label={saved.has(t.id) ? "Saved" : "Save"} title={saved.has(t.id) ? "Saved in this browser" : "Save in this browser"} onClick={() => { saved.toggle(t.id); }}>
              <Icon name={saved.has(t.id) ? "bookmark-on" : "bookmark"} size={15} /><span>{saved.has(t.id) ? "Saved" : "Save"}</span>
            </button>
            {artist && tippable(artist) ? (
              <button className="act support" aria-label={`Support ${artist.name} · 100% to the artist`} title={`Support ${artist.name} · 100% to the artist`} onClick={() => { openSupport({ kind: "tip", track: t, artist }); }}>
                <Shape g="square" size={12} fill="var(--ink)" /><span>Support</span>
              </button>
            ) : t.origin === "audius" ? (
              <a className="act support ext" href={firstNonEmpty(artist?.source, t.source)} target="_blank" rel="noreferrer" aria-label="Support on Audius" title={`Support on Audius · tips here open when ${t.artistName} claims the profile`}>
                <Shape g="square" size={12} fill="var(--ink)" /><span>Support</span><Icon name="external" size={12} />
              </a>
            ) : null}
          </div>
        )}


      <div className={`controls${live ? " with-pick solo" : ""}`}>
        {!live && <button onClick={p.prev} disabled={p.queue.length < 2} aria-label="Previous track" title={p.queue.length < 2 ? "Pick an album or playlist in the Library" : "Previous track"}><Icon name="prev" size={20} /></button>}
        <button className="play" onClick={p.toggle} aria-label={p.playing ? "Pause" : "Play"}><Icon name={p.playing ? "pause" : "play"} size={26} /><span className="play-txt">{p.playing ? "Pause" : live ? "Go live" : "Play"}</span></button>
        {!live && <button onClick={p.next} disabled={p.queue.length < 2} aria-label="Next track" title={p.queue.length < 2 ? "Pick an album or playlist in the Library" : "Next track"}><Icon name="next" size={20} /></button>}
        {/* On the radio only: pick what plays next, a compact blue button beside Go live. */}
        {live && (
          <button className="pickbtn" onClick={() => { openPick(p.station); }}
            aria-label={`Pick what plays next on ${stationName}`} title={`Pick what plays next on ${stationName} · public, on-chain`}>
            <Shape g="quarter" size={16} fill="#fff" /><span>Pick next</span>
          </button>
        )}
      </div>
      {!live && t && (
        <button className="golive" onClick={() => { openPick(0, t.id); }} title="Listeners program the radio together: your pick airs next on Main for everyone"><Shape g="quarter" size={10} /><span className="golive-txt"><span>Share it with everyone on the radio</span><small>Airs next on Main · one quick signature</small></span></button>
      )}

      <div className="volume">
        <button onClick={p.toggleMute} aria-pressed={p.muted} aria-label={p.muted ? "Unmute (M)" : "Mute (M)"} title={p.muted ? "Unmute · M" : "Mute · M"}>
          <Icon name={p.muted || p.volume === 0 ? "mute" : "volume"} />
        </button>
        <input type="range" min={0} max={1} step={0.05} value={p.muted ? 0 : p.volume} aria-label="Volume" onChange={(e) => { p.setVolume(Number(e.target.value)); }} />
      </div>

      {live && (
        <div className="upnext">
          <span className="lbl">Up next on {stationName} <Help text="Listeners program the radio: one pick per station per hour, up to 2 hours ahead. A pick locks about 0.1 GNOT as storage deposit." /></span>
          {upNext.map((e) => (
            <div key={`${String(e.track)}-${String(e.start)}`} className={`row tiny${e.queued ? " picked" : ""}`}>
              <span className="mono muted">{new Date(e.start * 1000).toLocaleTimeString("en", { hour: "2-digit", minute: "2-digit", hourCycle: "h23" })}</span>
              <span>{e.title}</span>
              {e.queued && <span className="tag blue"><Shape g="quarter" size={8} fill="currentColor" /> {e.by ? `picked by ${who(e.by)}` : "curator pick"}</span>}
            </div>
          ))}
          {upNext.length > 0 && !upNext.some((e) => e.queued) && (
            <button className="pick-cta" onClick={() => { openPick(p.station); }}>
              <Shape g="quarter" size={16} />
              <span>Next {upNext.length === 1 ? "track is" : `${String(upNext.length)} tracks are`} up for grabs<small>Pick one: it airs for everyone on {stationName}</small></span>
              <span aria-hidden="true">+</span>
            </button>
          )}
        </div>
      )}
    </section>
  );
}
