import { Icon } from "./Icons";
import { useNames } from "../lib/names";
import { useEffect, useMemo, useRef, useState } from "react";
import { clock, firstNonEmpty } from "../lib/format";
import type { Catalog, Navigate } from "../lib/types";
import type { Actions } from "../player/useActions";
import { NOT_RESPONDING, type Player, usePosition } from "../player/usePlayer";
import { Help } from "./Help";
import { Cover } from "./Cover";
import { Dial } from "./Dial";
import { Shape } from "./Shapes";
import type { SupportTarget } from "./SupportSheet";
import { tippable } from "./Verify";
import { favouriteMin, inMinutes, type Note, nextSet, pickNote, setName, shortBio, stationLine, why } from "../lib/onair";
import { collectable, usePickOnAir, useSponsored } from "../lib/incentives";
import { gnot } from "../lib/format";
import { ShareButton, Who } from "./common";

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
  const live = p.mode === "live";
  const chainNow = p.chainNow();
  // Live but not listening: the radio goes on, so the dial shows what is on air now and keeps turning.
  const [, setTick] = useState(0);
  useEffect(() => {
    // Not while the sheet is closed on a phone (opening it renders anyway); the desktop column is always on screen.
    if (!live || p.playing || (!open && window.matchMedia("(max-width: 900px)").matches)) return;
    const id = window.setInterval(() => { setTick((n) => n + 1); }, 1000);
    return () => { window.clearInterval(id); };
  }, [live, p.playing, open]);
  const airing = live && !p.playing ? p.entries.find((e) => e.start <= chainNow && e.end > chainNow) : undefined;
  const t = cat.byId.get(airing?.track ?? p.current);
  const artist = t ? cat.artists.get(t.artist) : undefined;
  const st = cat.stations.find((s) => s.id === p.station);
  const stationName = st?.name ?? "Main";
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
  // The listener's own pick on air, here or on another station: their moment, then its result.
  const myPick = usePickOnAir(me, cat, chainNow, actions.say);
  const mine = me !== "" && onAir?.queued === true && onAir.by === me;
  const elsewhere = myPick && !(live && myPick.station === p.station) ? myPick : null;
  // A tip during a listener's pick shares the artist's promo share with them (radio.TipOnAir); the admin's picks earn nothing.
  const picker = onAir?.queued && onAir.by !== cat.admin ? onAir.by : undefined;
  // Free (sponsored) picks of mine that have played in full: one signature collects the artist's refund.
  const toCollect = collectable(useSponsored(me, actions.pending))[0];

  // One quiet line under the artist, timed from the last tune-in or track change.
  const markKey = `${p.mode}/${String(p.station)}/${String(p.current)}`;
  const [mark, setMark] = useState({ key: markKey, at: Date.now() });
  if (mark.key !== markKey) setMark({ key: markKey, at: Date.now() });
  const favMin = useMemo(() => favouriteMin(cat.tracks), [cat.tracks]);
  const genreName = (id: number) => cat.genres.find((g) => g.id === id)?.name ?? "";
  const genreOf = (track: number) => cat.byId.get(track)?.genre ?? 0;
  const isMain = live && p.station === 0;
  const coming = isMain ? nextSet(p.entries, chainNow, genreOf) : null;
  const note: Note | null = t ? pickNote((Date.now() - mark.at) / 1000, {
    why: why(t, onAir, chainNow, favMin, who),
    next: coming ? { kind: "next", text: `Next: ${genreName(coming.genre)} ${inMinutes(coming.at - chainNow)}` } : null,
    nextIn: coming ? coming.at - chainNow : 0,
    intro: !live ? null : { kind: "intro", text: isMain ? setName(genreName(t.genre), chainNow) : stationLine(stationName, st?.genre) },
    artist: artist?.bio ? { kind: "artist", text: shortBio(artist.bio) } : null,
  }) : null;

  return (
    <section className={`now${open ? " open" : ""}${mine ? " mine" : ""}`} aria-label="Now playing" {...(open ? { role: "dialog", "aria-modal": true } : {})}>
      <button ref={closeRef} className="sheet-close" onClick={onClose} aria-label="Close player"><Icon name="chevron-down" size={26} /></button>
      <div className="now-top">
        {live
          ? <button className="chip station-chip" onClick={() => { go({ k: "stations" }); }} title={`${stationLine(stationName, st?.genre)} · change station`}><Shape g="circle" size={9} />{stationName}</button>
          : <button className="chip station-chip" onClick={() => { go({ k: "library", genre: 0 }); }} title="Open the Library"><Shape g="quarter" size={9} />Library</button>}
        <span className="seg small" role="group" aria-label="Mode">
          <button className={live ? "" : "on"} aria-pressed={!live} onClick={p.toLibrary} title="Library: play any track you choose, just for you">Lib</button>
          <button className={live ? "on live" : ""} aria-pressed={live} onClick={() => { p.goLive(p.station); }} title="Live: tune into a station, everyone hears the same second">Live</button>
        </span>
      </div>

      <Dial
        frac={t && t.duration > 0 ? (airing ? chainNow - airing.start : pos) / t.duration : 0}
        seconds={airing ? chainNow - airing.start : pos}
        buffering={p.buffering}
        tuning={live && !t && !p.error}
        caption={t ? `of ${clock(t.duration)}${live ? " · live" : ""}` : live ? "Nothing on air yet" : "Choose a track"}
        live={live}
        onSeek={live ? undefined : p.seek}
      />

      <div className="now-meta">
        <div className="now-titles">
          {t ? (
            <>
              <div className="now-head">
                <Cover t={t} size="56px" />
                <div className="now-head-txt">
                  <button className="title" onClick={() => { go({ k: "track", id: t.id }); }}>{t.title}</button>
                  <span className="now-by">
                    <button className="link muted" onClick={() => { go({ k: "artist", id: t.artist }); }}>{t.artistName}</button>
                    {mine ? (
                      <span className="mypick" role="status">Your pick · on air</span>
                    ) : note && (note.kind === "pick" || note.kind === "curator" ? (
                      <span key={note.text} className="picked-by"><Shape g="quarter" size={9} fill="var(--blue)" /> {note.kind === "pick" && onAir?.by && !onAir.sponsored ? <>picked by <Who address={onAir.by} shown={who} go={go} /></> : note.text}</span>
                    ) : note.kind === "artist" ? (
                      <span key="artist" className="onair-note bio">
                        <span className="bio-txt">{note.text}</span>
                      </span>
                    ) : (
                      <span key={note.text} className={`onair-note ${note.kind}`}><Shape g={note.kind === "next" ? "triangle" : "circle"} size={7} fill="currentColor" /> {note.text}</span>
                    ))}
                  </span>
                </div>
              </div>
              {onAir?.note && (
                <div className={`dedic${canReport ? "" : " solo"}`} role="note" aria-label={`Dedication: ${onAir.note}`}>
                  <span className="dedic-tag" aria-hidden="true"><Shape g="quarter" size={12} fill="var(--red)" /></span>
                  <span className="dedic-track" aria-hidden="true">
                    {/* Twice, so the ticker loops without a gap. */}
                    <span className="dedic-run">{onAir.note} · from <Who address={onAir.by} shown={who} go={go} tabIndex={-1} /><i /> {onAir.note} · from <Who address={onAir.by} shown={who} go={go} tabIndex={-1} /><i /></span>
                  </span>
                  {canReport && <button className="dedic-report" onClick={() => { actions.reportNote(p.station, onAir.start, () => { setReported((s) => new Set(s).add(noteKey)); }); }} title="Report this dedication · open to listeners who picked a track; three reports hide it">Report</button>}
                </div>
              )}
            </>
          ) : (
            <span className="muted">Pick a track or go live.</span>
          )}
          {p.error && (
            <span className="error small" role="alert">
              {p.error}
              {!live && p.error === NOT_RESPONDING && p.queue.length > 1 && <> <button className="link" onClick={p.next}>Next</button></>}
            </span>
          )}
        </div>
      </div>

      {(mine || elsewhere) && (
        <div className="mypick-card" role="status">
          <span className="lbl">Your pick · on air{elsewhere ? ` on ${cat.stations.find((x) => x.id === elsewhere.station)?.name ?? "the radio"}` : ""}</span>
          <span>
            {elsewhere ? <>“{cat.byId.get(elsewhere.track)?.title ?? "Your track"}” is playing for everyone tuned in.</>
              : onAir?.sponsored ? <>Free pick: {artist?.name ?? "the artist"} refunds you {gnot(onAir.sponsored)} once it has played in full. Collect it here then.</>
              : artist && tippable(artist) ? <>Tips sent from the radio while it plays share {artist.promo}% with you (half if they came through someone's link).</>
                : <>It plays for everyone tuned in. Share it.</>}
          </span>
          <span className="head-actions">
            {elsewhere
              ? <button className="cta" onClick={() => { p.goLive(elsewhere.station); }}>Tune in</button>
              : <ShareButton title={t?.title ?? "GnoRadio"} to={{ k: "stations", live: p.station }} refBy={me} text={`My pick "${t?.title ?? ""}" is on air on GnoRadio ${stationName}. Tune in.`} />}
          </span>
        </div>
      )}

      {toCollect && (
        <div className="mypick-card" role="status">
          <span className="lbl">Your free pick played</span>
          <span>“{cat.byId.get(toCollect.track)?.title ?? "Your track"}”: {cat.byId.get(toCollect.track)?.artistName ?? "the artist"} refunds it.</span>
          <span className="head-actions"><button className="cta" disabled={actions.pending !== ""} onClick={() => { actions.collect(toCollect.station, toCollect.start); }}>Collect {gnot(toCollect.amount)}</button></span>
        </div>
      )}

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
              <Icon name={actions.liked.has(t.id) ? "heart-on" : "heart"} size={16} /><span>Like{t.likes > 0 && ` ${String(t.likes)}`}</span>
            </button>
            <button className={`act${saved.has(t.id) ? " on" : ""}`} aria-pressed={saved.has(t.id)} aria-label={saved.has(t.id) ? "Saved" : "Save"} title={saved.has(t.id) ? "Saved in this browser" : "Save in this browser"} onClick={() => { saved.toggle(t.id); }}>
              <Icon name={saved.has(t.id) ? "bookmark-on" : "bookmark"} size={15} /><span>{saved.has(t.id) ? "Saved" : "Save"}</span>
            </button>
            {/* The realm refuses a tip to yourself: an artist hears their own track without the button. */}
            {artist && tippable(artist) ? artist.owner === me ? null : (
              <button className="act support" aria-label={`Support ${artist.name}`} title={`Support ${artist.name} · GnoRadio takes nothing`} onClick={() => { openSupport({ kind: "tip", track: t, artist, station: live ? p.station : undefined, picker }); }}>
                <Shape g="square" size={12} fill="var(--ink)" /><span>Support</span>
              </button>
            ) : t.origin === "audius" ? (
              <a className="act support ext" href={firstNonEmpty(artist?.source, t.source)} target="_blank" rel="noreferrer" aria-label="Support on Audius" title={`Support on Audius · tips here open when ${t.artistName} verifies their profile`}>
                <Shape g="square" size={12} fill="var(--ink)" /><span>Support</span><Icon name="external" size={12} />
              </a>
            ) : null}
          </div>
        )}


      <div className={`controls${live ? " with-pick solo" : ""}`}>
        {!live && <button onClick={p.prev} disabled={p.queue.length < 2} aria-label="Previous track" title={p.queue.length < 2 ? "Pick an album or playlist in the Library" : "Previous track"}><Icon name="prev" size={20} /></button>}
        <button className="play" onClick={p.toggle} aria-label={live ? (p.playing ? "Stop listening" : "Listen live") : p.playing ? "Pause" : "Play"}><Icon name={p.playing ? (live ? "stop" : "pause") : "play"} size={26} /><span className="play-txt">{live ? (p.playing ? "Stop" : "Listen") : p.playing ? "Pause" : "Play"}</span></button>
        {!live && <button onClick={p.next} disabled={p.queue.length < 2} aria-label="Next track" title={p.queue.length < 2 ? "Pick an album or playlist in the Library" : "Next track"}><Icon name="next" size={20} /></button>}
        {/* On the radio only: pick what plays next, a compact blue button beside Go live. */}
        {live && (
          <button className="pickbtn" onClick={() => { openPick(p.station); }}
            aria-label={`Pick what plays next on ${stationName}`} title={`Pick what plays next on ${stationName} · public, on-chain`}>
            <Icon name="on-air" size={18} /><span>Pick next</span>
          </button>
        )}
      </div>
      {!live && t && (
        <button className="golive" onClick={() => { openPick(0, t.id); }} title="Listeners program the radio together: your pick airs next on Main for everyone"><Icon name="on-air" size={14} /><span className="golive-txt"><span>Share it with everyone on the radio</span><small>Airs next on Main · one quick signature</small></span></button>
      )}

      <div className="volume">
        <button onClick={p.toggleMute} aria-pressed={p.muted} aria-label={p.muted ? "Unmute (M)" : "Mute (M)"} title={p.muted ? "Unmute · M" : "Mute · M"}>
          <Icon name={p.muted || p.volume === 0 ? "mute" : "volume"} />
        </button>
        <input type="range" min={0} max={1} step={0.05} value={p.muted ? 0 : p.volume} aria-label="Volume" onChange={(e) => { p.setVolume(Number(e.target.value)); }} />
      </div>

      {live && (
        <div className="upnext">
          <span className="lbl">Up next on {stationName} <Help text="Listeners program the radio: one pick per station per hour, up to 2 hours ahead. A pick costs about 0.08 GNOT and locks about 0.3 GNOT as storage deposit (up to 0.9 for your first)." /></span>
          {upNext.map((e) => (
            <div key={`${String(e.track)}-${String(e.start)}`} className={`row tiny${e.queued ? " picked" : ""}`}>
              <span className="mono muted">{new Date(e.start * 1000).toLocaleTimeString("en", { hour: "2-digit", minute: "2-digit", hourCycle: "h23" })}</span>
              <span>{e.title}</span>
              {e.queued && <span className="tag blue"><Shape g="quarter" size={8} fill="currentColor" /> {e.by ? <>picked by <Who address={e.by} shown={who} go={go} /></> : "curator pick"}</span>}
            </div>
          ))}
          {upNext.length > 0 && !upNext.some((e) => e.queued) && (
            <button className="pick-cta" onClick={() => { openPick(p.station); }}>
              <Icon name="on-air" size={18} />
              <span>Next {upNext.length === 1 ? "track is" : `${String(upNext.length)} tracks are`} up for grabs<small>Pick one: your name on air, a share of its tips</small></span>
              <span aria-hidden="true">+</span>
            </button>
          )}
        </div>
      )}
    </section>
  );
}
