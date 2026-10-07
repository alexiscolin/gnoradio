import { Help } from "./Help";
import { useNames } from "../lib/names";
import { Icon } from "./Icons";
import { useEffect, useRef, useState } from "react";
import { loadSchedule } from "../lib/catalog";
import { clock, errorMessage } from "../lib/format";
import { MAX_NOTE, noteProblem } from "../lib/gno";
import type { Catalog, Schedule, Track } from "../lib/types";
import { Cover } from "./Cover";
import { Loader } from "./Loader";
import { Shape } from "./Shapes";
import { ShareButton } from "./common";

interface Props {
  readonly cat: Catalog;
  readonly station: number;
  /** suggest puts a track first, e.g. the one whose page the listener came from. */
  readonly suggest?: number | undefined;
  /** me is the connected wallet, to say when it can pick again. */
  readonly me?: string | undefined;
  /** pending is the action waiting in Adena ("" when none): the pick is read back once it settles. */
  readonly pending?: string | undefined;
  readonly onPick: (t: Track, station: number, note: string) => void;
  readonly onClose: () => void;
}

/** hhmm is a unix time as a 24 h clock in the listener's time zone. */
export const hhmm = (unix: number) => new Date(unix * 1000).toLocaleTimeString("en", { hour: "2-digit", minute: "2-digit", hourCycle: "h23" });

// The realm's limits on listener picks (radio.gno: queueCooldown, maxAheadAir, maxQueue).
export const PICK_COOLDOWN = 3600;
export const PICK_AHEAD = 7200;
export const PICK_MAX = 30;

/**
 * pickBlock says why a wallet cannot pick on a station right now, from the
 * public schedule: its own pick waiting or made within the hour, the 2 h of
 * listener airtime ahead, or a full queue. "" when it can pick.
 */
export function pickBlock(entries: readonly { start: number; end: number; queued: boolean; by: string }[], now: number, me: string): string {
  const mine = entries.filter((e) => e.queued && me !== "" && e.by === me);
  if (mine.some((e) => e.start > now)) return "Your pick is already waiting on this station.";
  const last = Math.max(0, ...mine.map((e) => e.start));
  if (last > 0 && now - last < PICK_COOLDOWN) return `You can pick again at ${hhmm(last + PICK_COOLDOWN)}.`;
  const ahead = entries.filter((e) => e.queued && e.by !== "" && e.end > now);
  if (ahead.length >= PICK_MAX) return "Queue full for now. Try again later.";
  const air = ahead.reduce((n, e) => n + (e.end - Math.max(e.start, now)), 0);
  if (air >= PICK_AHEAD) {
    const free = Math.min(...ahead.map((e) => e.end));
    return `Queue full until ${hhmm(free)}: listeners have programmed the next 2 hours.`;
  }
  return "";
}

/**
 * PickNext lets a listener program the radio: choose a track, sign once, and it
 * airs for everyone: at once over a suggested track, else after the picks already waiting. The rules mirror radio.Queue.
 */
export function PickNext({ cat, station: initial, suggest, me = "", pending = "", onPick, onClose }: Props) {
  const [station, setStation] = useState(initial);
  const ref = useRef<HTMLDialogElement>(null);
  useEffect(() => {
    const d = ref.current;
    if (d && !d.open && typeof d.showModal === "function") d.showModal();
    return () => { d?.close(); };
  }, []);

  const st = cat.stations.find((s) => s.id === station);
  const [sched, setSched] = useState<Schedule | null>(null);
  const [error, setError] = useState("");
  const [q, setQ] = useState("");
  const [note, setNote] = useState("");
  const [noteWhy, setNoteWhy] = useState("");
  // The realm screens dedications (p/gnoradio/safe); ask it before anyone signs.
  useEffect(() => {
    setNoteWhy("");
    if (!note) return;
    const id = window.setTimeout(() => {
      noteProblem(note.trim()).then(setNoteWhy, () => { setNoteWhy(""); });
    }, 350);
    return () => { window.clearTimeout(id); };
  }, [note]);
  // sent is the track just picked, waiting for Adena; once that settles, the schedule is read again.
  const [sent, setSent] = useState(0);
  const [reads, setReads] = useState(0);
  useEffect(() => {
    if (sent && pending === "") { setSent(0); setReads((n) => n + 1); }
  }, [sent, pending]);
  useEffect(() => {
    let alive = true;
    loadSchedule(station).then(
      (s) => { if (alive) setSched(s); },
      (e: unknown) => { if (alive) setError(errorMessage(e)); },
    );
    return () => { alive = false; };
  }, [station, reads]);

  const now = sched?.now ?? Date.now() / 1000;
  const who = useNames((sched?.entries ?? []).map((e) => e.by));
  const ahead = (sched?.entries ?? []).filter((e) => e.end > now);
  const onAir = ahead.find((e) => e.start <= now);
  const picks = ahead.filter((e) => e.queued && e.start > now);
  // A new pick starts after the current track and every pick already waiting.
  // Over a suggested (flow) track the pick airs at once, crossfading (radio.Queue);
  // over a listener's pick or the plain rotation it waits for the end.
  const takeover = onAir !== undefined && !onAir.queued && st?.id === 0;
  const airsAt = Math.max(takeover ? now : onAir?.end ?? now, ...picks.map((e) => e.end));
  const taken = new Set(ahead.filter((e) => e.queued).map((e) => e.track));
  if (onAir) taken.add(onAir.track);

  const s = q.trim().toLowerCase();
  const eligible = cat.tracks.filter((t) => (!st || st.genre === 0 || t.genre === st.genre) && !taken.has(t.id));
  const matches = s ? eligible.filter((t) => `${t.title} ${t.artistName}`.toLowerCase().includes(s)) : eligible;
  const first = suggest === undefined ? undefined : matches.find((t) => t.id === suggest);
  const list = (first ? [first, ...matches.filter((t) => t !== first)] : matches).slice(0, 40);
  const blocked = sched ? pickBlock(sched.entries, now, me) : "";
  const name = st?.name ?? "Main";
  const mine = me ? ahead.find((e) => e.queued && e.by === me) : undefined;
  const mineTitle = mine ? cat.byId.get(mine.track)?.title ?? mine.title : "";

  return (
    <dialog
      ref={ref}
      className="sheet pick"
      aria-label={`Pick what plays next on ${name}`}
      onCancel={(e) => { e.preventDefault(); onClose(); }}
      onClick={(e) => { if (e.target === e.currentTarget) onClose(); }}
    >
      <div className="sheet-body">
        <div className="sheet-head">
          <Shape g="quarter" size={18} />
          <span>Pick what plays next on{" "}
            <select className="station-select" aria-label="Station" value={station} onChange={(e) => { setStation(Number(e.target.value)); }}>
              {cat.stations.filter((x) => x.tracks > 0).map((x) => <option key={x.id} value={x.id}>{x.name}</option>)}
            </select>
          </span>
          <Help text="Your pick airs right away, crossfading over the station's own selection; after any listener picks already waiting. One per station per hour; listener picks fill at most 2 hours ahead; about 0.1 GNOT deposit." />
          <button className="x" onClick={onClose} aria-label="Close"><Icon name="close" /></button>
        </div>
        {mine ? (
          <div className="pick-done" role="status">
            <Shape g="quarter" size={30} />
            <div>
              <span className="lbl">{mine.start <= now ? `On air now on ${name}` : `On air at ${hhmm(mine.start)} on ${name}`}</span>
              <b>{mineTitle}</b>
              <span className="muted small">Your pick plays for everyone tuned in. Bring your friends.</span>
            </div>
            <div className="head-actions">
              <ShareButton title={mineTitle} to={{ k: "stations", live: station }}
                text={`I put "${mineTitle}" on air on GnoRadio ${name}${mine.note ? ` (${mine.note})` : ""}${mine.start > now ? ` at ${hhmm(mine.start)}` : ""}. Tune in.`} />
              <button className="cta" onClick={onClose}>Done</button>
            </div>
          </div>
        ) : (
          <>
            {suggest !== undefined && <p className="muted small">Everyone will hear it next on {name}.</p>}
            <ol className="how">
              <li><b>1</b><span>Choose a track{st && st.genre !== 0 ? ` from ${name}` : ""}.</span></li>
              <li><b>2</b><span>Sign once. Your pick is public, on-chain.</span></li>
              <li><b>3</b><span>It airs for everyone, right away or right after the picks already waiting.</span></li>
            </ol>
          </>
        )}

        <div className="pick-queue">
          <div className="pick-line">
            <span className="mono muted">now</span>
            <span>{onAir?.title ?? "…"}</span>
            {onAir && <span className="muted small">ends {hhmm(onAir.end)}</span>}
          </div>
          {picks.map((e) => (
            <div key={`${String(e.track)}-${String(e.start)}`} className="pick-line">
              <span className="mono muted">{hhmm(e.start)}</span>
              <span>{e.title}</span>
              <span className="tag blue"><Shape g="quarter" size={8} fill="currentColor" /> {e.by ? (e.by === me ? "you" : who(e.by)) : "curator"}</span>
            </div>
          ))}
          {!mine && (
            <div className="pick-line yours">
              <span className="mono">{sched ? hhmm(airsAt) : <Loader label="Reading the schedule" />}</span>
              <span>Your pick</span>
              <span className="muted small">{picks.length === 0 ? (takeover ? "airs right away" : "plays next · nobody picked yet") : `after ${String(picks.length)} pick${picks.length > 1 ? "s" : ""}`}</span>
            </div>
          )}
        </div>
        {error && <p className="error small" role="alert">{error}</p>}
        {blocked && !mine && <p className="pick-blocked" role="status"><Shape g="square" size={10} /> {blocked}</p>}

        {!mine && (<>
        <label className="pick-note">
          <span>Dedication <span className="muted">optional</span></span>
          <input maxLength={MAX_NOTE} placeholder="for Marie, happy birthday!" value={note} onChange={(e) => { setNote(e.target.value); }} aria-invalid={noteWhy !== ""} />
          <span className={noteWhy ? "error small" : "muted small"}>{noteWhy ? `Dedication: ${noteWhy}` : `Shown on air with your pick · ${String(MAX_NOTE - note.length)} left`}</span>
        </label>
        <label className="pick-search">
          <span className="sr">Search tracks</span>
          <input placeholder={`Search ${String(eligible.length)} tracks`} value={q} onChange={(e) => { setQ(e.target.value); }} />
        </label>
        <div className="pick-list">
          {list.map((t) => (
            <button key={t.id} className={`pick-row${t.id === suggest || t.id === sent ? " suggested" : ""}`} disabled={blocked !== "" || sent !== 0 || noteWhy !== ""}
              onClick={() => { setSent(t.id); onPick(t, station, note.trim()); }}>
              <Cover t={t} size="36px" />
              <span className="tt"><b>{t.title}</b><span className="muted">{t.artistName}</span></span>
              <span className="mono muted">{clock(t.duration)}</span>
              <span className="pick-go">{t.id === sent ? "Signing…" : "Pick"}</span>
            </button>
          ))}
          {list.length === 0 && <p className="muted small">No track matches.</p>}
        </div>
        </>)}

        <p className="fine">One pick per station per hour · listener picks fill up to 2 h ahead · about 0.1 GNOT locked as storage deposit.</p>
      </div>
    </dialog>
  );
}
