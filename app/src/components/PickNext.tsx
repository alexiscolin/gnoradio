import { Icon } from "./Icons";
import { useEffect, useRef, useState } from "react";
import { loadSchedule } from "../lib/catalog";
import { loadPicks, type RadioPick } from "../lib/community";
import { clock, errorMessage, gnot } from "../lib/format";
import { PICK_DEPOSIT, PICK_DEPOSIT_FIRST, PICK_FEE, useSponsored } from "../lib/incentives";
import { MAX_NOTE, noteProblem } from "../lib/gno";
import type { Booked, Catalog, Schedule, Track } from "../lib/types";
import { Cover } from "./Cover";
import { Loader } from "./Loader";
import { Shape } from "./Shapes";
import { ShareButton } from "./common";
import { tippable } from "./Verify";
import type { Toast } from "../player/useActions";

interface Props {
  readonly cat: Catalog;
  readonly station: number;
  /** suggest puts a track first, e.g. the one whose page the listener came from. */
  readonly suggest?: number | undefined;
  /** me is the connected wallet, to say when it can pick again. */
  readonly me?: string | undefined;
  /** pending is the action waiting in Adena ("" when none): the pick is read back once it settles. */
  readonly pending?: string | undefined;
  /** notice is the last action's feedback (the page toast is hidden under this modal). */
  readonly notice?: Toast | null | undefined;
  /** sponsored: the artist refunds the pick once it has aired (radio.QueueSponsored), no dedication; at: the unix time it is booked for (radio.QueueAt), 0 for now. */
  readonly onPick: (t: Track, station: number, note: string, sponsored: boolean, at: number) => void;
  readonly onClose: () => void;
}

/** hhmm is a unix time as a 24 h clock in the listener's time zone. */
export const hhmm = (unix: number) => new Date(unix * 1000).toLocaleTimeString("en", { hour: "2-digit", minute: "2-digit", hourCycle: "h23" });

/** gmt is the listener's UTC offset at a unix time: "GMT+2", "GMT-3:30". */
export function gmt(unix: number): string {
  const m = -new Date(unix * 1000).getTimezoneOffset();
  const a = Math.abs(m);
  return `GMT${m < 0 ? "-" : "+"}${String(Math.floor(a / 60))}${a % 60 ? `:${String(a % 60).padStart(2, "0")}` : ""}`;
}

// The realm's limits on listener picks (radio.gno: queueCooldown, maxAheadAir, maxQueue, replayGap, maxPerArtistQ).
const PICK_COOLDOWN = 3600;
const REPLAY_GAP = 3 * 3600;
const PICK_AHEAD = 7200;
const PICK_MAX = 30;
const PER_ARTIST = 2;
// A pick booked for a time (radio.QueueAt: bookMin, bookMax, maxBookedHour): 15 min to 24 h ahead, 4 per station and UTC hour.
const BOOK_MIN = 15 * 60;
const BOOK_MAX = 24 * 3600;
const BOOKED_PER_HOUR = 4;
const STEP = 15 * 60;

/**
 * bookAt turns a clock time typed by the listener ("21:00", their time zone)
 * into the next quarter hour it names at least BOOK_MIN from now: today, or
 * tomorrow once today's has passed. 0 when it falls outside the 24 h window.
 */
export function bookAt(clock: string, now: number): number {
  const m = /^(\d{1,2}):(\d{2})$/.exec(clock);
  if (!m) return 0;
  const d = new Date(now * 1000);
  d.setHours(Number(m[1]), Number(m[2]), 0, 0);
  let t = Math.ceil(d.getTime() / 1000 / STEP) * STEP;
  if (t < now + BOOK_MIN) t += 86400;
  return t <= now + BOOK_MAX ? t : 0;
}

/** hourFull: BOOKED_PER_HOUR picks are already booked in at's UTC hour. */
const hourFull = (booked: readonly Pick<Booked, "at">[], at: number): boolean =>
  booked.filter((b) => Math.floor(b.at / 3600) === Math.floor(at / 3600)).length >= BOOKED_PER_HOUR;
// radio.StationName: New this week only takes tracks above Catalog.newFloor.
const NEW_STATION = "New this week";

/**
 * pickBlock says why a wallet cannot pick on a station, as radio.Queue / QueueAt
 * would: its own pick waiting (booked ones included), its last pick (lastAt,
 * the time it was queued) less than an hour ago, a full queue; for now (at 0)
 * no room in the 2 h of listener airtime for a track of dur seconds (0: none
 * chosen yet), booked picks aside; for a time, 15 min to 24 h ahead and 4
 * booked per hour. "" when it can pick.
 */
export function pickBlock(entries: readonly { start: number; end: number; queued: boolean; by: string; at?: number | undefined }[], now: number, me: string, lastAt = 0, dur = 0, at = 0, booked: readonly Booked[] = []): string {
  const later = booked.filter((b) => b.end > now);
  const ahead = entries.filter((e) => e.queued && e.by !== "" && e.end > now && !e.at);
  if ([...ahead, ...later].some((e) => me !== "" && e.by === me && e.start > now)) return "Your pick is already waiting on this station.";
  if (lastAt > 0 && now - lastAt < PICK_COOLDOWN) return `You can pick again at ${hhmm(lastAt + PICK_COOLDOWN)}.`;
  if (ahead.length + later.length >= PICK_MAX) return "Queue full for now. Try again later.";
  if (at > 0) {
    if (at < now + BOOK_MIN || at > now + BOOK_MAX) return "Choose a time 15 minutes to 24 hours ahead.";
    return hourFull(later, at) ? `${String(BOOKED_PER_HOUR)} picks are already booked for that hour here. Choose another time.` : "";
  }
  const air = ahead.reduce((n, e) => n + (e.end - Math.max(e.start, now)), 0);
  if (air >= PICK_AHEAD) {
    const free = Math.min(...ahead.map((e) => e.end));
    return `Queue full until ${hhmm(free)}: listeners have programmed the next 2 hours.`;
  }
  if (air + dur > PICK_AHEAD) return `Too long for the time left: choose a track under ${String(Math.floor((PICK_AHEAD - air) / 60))} min.`;
  return "";
}

/** lastPickAt is when me last picked on station (radio activity feed), 0 if not lately. */
const lastPickAt = (picks: readonly Pick<RadioPick, "kind" | "by" | "station" | "at">[], station: number, me: string): number =>
  Math.max(0, ...picks.filter((p) => (p.kind === "queue" || p.kind === "sponsored") && me !== "" && p.by === me && p.station === station).map((p) => p.at));

/**
 * replayedAt maps the tracks picked on a station less than 3 hours ago (by
 * anyone, curator included) to when: radio.Queue refuses them until then.
 */
function replayedAt(picks: readonly Pick<RadioPick, "station" | "track" | "at" | "start">[], station: number, now: number, booked: readonly Pick<Booked, "track" | "start">[] = []): Map<number, number> {
  const out = new Map<number, number>();
  const mark = (track: number, t: number) => { out.set(track, Math.max(t, out.get(track) ?? 0)); };
  // A pick for now counts from when it was queued; a booked one (aired later than any
  // pick for now could) counts around its airing, as radio.Queue does.
  for (const p of picks) if (p.station === station && p.start - p.at <= PICK_AHEAD && now - p.at < REPLAY_GAP) mark(p.track, p.at);
  for (const b of booked) if (Math.abs(now - b.start) < REPLAY_GAP) mark(b.track, b.start);
  return out;
}

/**
 * PickNext lets a listener program the radio: select a track, push it on air
 * with one signature, and it airs for everyone: at once over a suggested
 * track, else after the picks already waiting. The rules mirror radio.Queue.
 */
export function PickNext({ cat, station: initial, suggest, me = "", pending = "", notice, onPick, onClose }: Props) {
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
  const [free, setFree] = useState(true); // take the artist's free pick when there is one
  const [when, setWhen] = useState(0); // 0: right away; else the unix time (UTC) the pick is booked for
  // The realm screens dedications (p/gnoradio/safe); ask it before anyone signs.
  useEffect(() => {
    setNoteWhy("");
    if (!note) return;
    const id = window.setTimeout(() => {
      noteProblem(note.trim()).then(setNoteWhy, () => { setNoteWhy(""); });
    }, 350);
    return () => { window.clearTimeout(id); };
  }, [note]);
  // selected is the track chosen in the list; sent the one pushed, waiting for Adena. Once that settles, the schedule is read again.
  // Opened from a track (suggest), the sheet starts on that track's step 2.
  const [selected, setSelected] = useState(suggest ?? 0);
  const [step, setStep] = useState<1 | 2>(suggest === undefined ? 1 : 2);
  const [sent, setSent] = useState(0);
  const [asked, setAsked] = useState(false); // show the action's feedback once this sheet sent one
  const [reads, setReads] = useState(0);
  useEffect(() => {
    if (sent && pending === "") { setSent(0); setReads((n) => n + 1); }
  }, [sent, pending]);
  useEffect(() => {
    let alive = true;
    // Listener picks fill up to 2 h ahead: read all of it to find yours.
    loadSchedule(station, PICK_AHEAD).then(
      (s) => { if (alive) setSched(s); },
      (e: unknown) => { if (alive) setError(errorMessage(e)); },
    );
    return () => { alive = false; };
  }, [station, reads]);
  // Who picked what here lately: a track picked less than 3 h ago cannot be picked again.
  const [recent, setRecent] = useState<readonly RadioPick[]>([]);
  useEffect(() => { void loadPicks().then(setRecent); }, [reads]);

  const now = sched?.now ?? Date.now() / 1000;
  const ahead = (sched?.entries ?? []).filter((e) => e.end > now);
  const onAir = ahead.find((e) => e.start <= now);
  const picks = ahead.filter((e) => e.queued && e.start > now);
  // A new pick starts after the current track and every pick already waiting.
  // Over Main's suggested (flow) track the pick airs at once, crossfading (radio.Queue);
  // over a listener's pick or the rotation it waits for the end. ScheduleJSON gives a
  // flow slot offset 0 and the rotation track on air its offset into it.
  const takeover = onAir !== undefined && !onAir.queued && onAir.offset === 0 && st?.id === 0;
  const airsAt = Math.max(takeover ? now : onAir?.end ?? now, ...picks.map((e) => e.end));
  const taken = new Set(ahead.filter((e) => e.queued).map((e) => e.track));
  if (onAir) taken.add(onAir.track);

  // Two tracks per artist may wait on a station (radio.Queue counts the one on air too).
  // Booked picks beyond the schedule read count too.
  const perArtist = new Map<number, number>();
  const later = (sched?.booked ?? []).filter((b) => b.end > now && !ahead.some((e) => e.start === b.start));
  for (const e of [...ahead, ...later]) {
    const a = e.by !== "" ? cat.byId.get(e.track)?.artist : undefined;
    if (a !== undefined) perArtist.set(a, (perArtist.get(a) ?? 0) + 1);
  }

  const s = q.trim().toLowerCase();
  const isNew = st?.name === NEW_STATION;
  const eligible = cat.tracks.filter((t) => (!st || st.genre === 0 || t.genre === st.genre) && (!isNew || t.id > cat.newFloor) && !taken.has(t.id));
  const matches = s ? eligible.filter((t) => `${t.title} ${t.artistName}`.toLowerCase().includes(s)) : eligible;
  const first = suggest === undefined ? undefined : matches.find((t) => t.id === suggest);
  const list = (first ? [first, ...matches.filter((t) => t !== first)] : matches).slice(0, 40);
  const chosen = cat.byId.get(selected);
  const booked = sched?.booked ?? [];
  const replayed = replayedAt(recent, station, now, booked);
  // A booked pick also keeps 3 h from any pick of the same track (radio.Queue's replay gap, around its time).
  const clash = chosen !== undefined && when > 0 && ((replayed.get(chosen.id) ?? -Infinity) > when - REPLAY_GAP ||
    [...ahead.filter((e) => e.queued), ...booked].some((e) => e.track === chosen.id && Math.abs(e.start - when) < REPLAY_GAP));
  // The suggested track may be on air, waiting or just played: step 2 says so.
  const gone = chosen !== undefined && (!eligible.some((t) => t.id === chosen.id) || replayed.has(chosen.id) || (perArtist.get(chosen.artist) ?? 0) >= PER_ARTIST);
  const blocked = !sched ? "" : gone ? `This track can't be picked here right now.${step === 2 ? " Go back and choose another." : ""}` : pickBlock(sched.entries, now, me, lastPickAt(recent, station, me), chosen?.duration ?? 0, when, booked) ||
    (clash ? "This track plays here within 3 hours of that time. Choose another time." : "");
  const chosenArtist = chosen ? cat.artists.get(chosen.artist) : undefined;
  // A free (sponsored) pick: the artist refunds it once it has aired in full; the wallet needs some pick history.
  const sponsoredInfo = useSponsored(me, reads);
  const refund = chosenArtist?.sponsor ?? 0;
  const freeBlock = sponsoredInfo?.block ?? "";
  const sponsoredPick = free && refund > 0 && freeBlock === "";
  const push = () => {
    if (!chosen || blocked || sent || (noteWhy && !sponsoredPick)) return;
    // Ask once, at the first pick: the browser can then say when it airs.
    if ("Notification" in window && Notification.permission === "default") void Notification.requestPermission();
    setSent(chosen.id);
    setAsked(true);
    onPick(chosen, station, sponsoredPick ? "" : note.trim(), sponsoredPick, when);
  };
  const timing = picks.length === 0 ? (takeover ? "right away" : "plays next") : `after ${String(picks.length)} pick${picks.length > 1 ? "s" : ""}`;
  const earn = !chosen ? `Picks earn the artist's promo share of tips made while they play (set by the artist).`
    : tippable(chosenArtist) ? `You earn up to ${String(chosenArtist?.promo ?? 0)}% of the tips ${chosen.artistName} gets on the radio while it plays.`
    : "";
  const name = st?.name ?? "Main";
  const mineBooked = me ? booked.find((b) => b.by === me && b.end > now) : undefined;
  const mine = me ? ahead.find((e) => e.queued && e.by === me) ?? (mineBooked && { ...mineBooked, title: "", note: "" }) : undefined;
  const mineTitle = mine ? cat.byId.get(mine.track)?.title ?? mine.title : "";
  const mineAt = mine?.at ?? 0; // booked: say the time asked, in the listener's time zone
  // The first quarter hour that can still be booked, for "At a time".
  let firstFree = Math.ceil((now + BOOK_MIN) / STEP) * STEP;
  while (hourFull(booked, firstFree) && firstFree + STEP <= now + BOOK_MAX) firstFree += STEP;
  const sponsors = (t: Track) => (cat.artists.get(t.artist)?.sponsor ?? 0) > 0;

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
          {step === 2 && !mine && <button className="x back" onClick={() => { setStep(1); }} aria-label="Back to tracks"><Icon name="arrow-left" size={18} /></button>}
          <h2 className="pick-title">{mine ? "On air" : "Pick next"}</h2>
          {!mine && <span className="pick-step mono muted">{step}/2</span>}
          <button className="x" onClick={onClose} aria-label="Close"><Icon name="close" /></button>
        </div>

        {mine ? (
          <div className="pick-done" role="status">
            <span className="lbl">{mine.start <= now ? `On air now on ${name}` : mineAt ? `Booked · airs at ${hhmm(mineAt)} your time on ${name}` : `Airs at ${hhmm(mine.start)} on ${name}`}</span>
            <b>{mineTitle}</b>
            <span className="muted small">Your pick plays for everyone tuned in.</span>
            <div className="pick-share">
              <ShareButton title={mineTitle} to={{ k: "stations", live: station }} refBy={me}
                text={`I put "${mineTitle}" on air on GnoRadio ${name}${mine.note ? ` (${mine.note})` : ""}${mine.start <= now ? "" : mineAt ? `. On air at ${hhmm(mineAt)} (${gmt(mineAt)})` : ` at ${hhmm(mine.start)}`}. Tune in.`} />
              <span className="small">Your link earns too: tips sent through it pay you a share.</span>
            </div>
            <button className="cta" onClick={onClose}>Done</button>
          </div>
        ) : step === 1 ? (<>
          <p className="pick-perks"><i className="dot" aria-hidden="true" /> Your name and dedication on air, and a share of its tips{(chosen ? sponsors(chosen) : list.some(sponsors)) ? " · free when sponsored" : ""}.</p>
          <div className="pick-filters">
            <label>
              <span className="sr">Station</span>
              <select className="station-select" value={station} onChange={(e) => { setStation(Number(e.target.value)); setSelected(0); }}>
                {cat.stations.filter((x) => x.tracks > 0).map((x) => <option key={x.id} value={x.id}>{x.name}</option>)}
              </select>
            </label>
            <label className="pick-search">
              <span className="sr">Search tracks</span>
              <input placeholder="Search" value={q} onChange={(e) => { setQ(e.target.value); }} />
            </label>
          </div>
          {error && <p className="error small" role="alert">{error}</p>}
          {blocked && <p className="pick-blocked" role="status"><Shape g="square" size={10} /> {blocked}</p>}
          <div className="pick-list">
            {list.map((t) => {
              const again = replayed.get(t.id);
              const full = (perArtist.get(t.artist) ?? 0) >= PER_ARTIST;
              return (
                <button key={t.id} className={`pick-row${t.id === selected ? " on" : t.id === suggest ? " suggested" : ""}`} aria-pressed={t.id === selected}
                  disabled={again !== undefined || full}
                  onClick={() => { setSelected(t.id === selected ? 0 : t.id); }}
                  onKeyDown={(e) => { if (e.key === "Enter" && t.id === selected) { e.preventDefault(); setStep(2); } }}>
                  <Cover t={t} size="36px" />
                  <span className="tt"><b>{t.title}</b><span className="muted">{again !== undefined ? `Picked here at ${hhmm(again)} · again at ${hhmm(again + REPLAY_GAP)}` : full ? `${t.artistName} · 2 tracks already waiting` : (cat.artists.get(t.artist)?.sponsor ?? 0) > 0 ? `${t.artistName} · free pick` : t.artistName}</span></span>
                  <span className="mono muted">{clock(t.duration)}</span>
                </button>
              );
            })}
            {list.length === 0 && <p className="muted small">No track matches.</p>}
          </div>
          <div className="pick-push">
            <button className="push" disabled={!chosen || blocked !== ""} onClick={() => { setStep(2); }}>
              {chosen ? `Next · ${chosen.title}` : "Choose a track"}
            </button>
          </div>
        </>) : (<>
          {chosen && (
            <div className="pick-chosen">
              <Cover t={chosen} size="56px" />
              <span className="tt"><b>{chosen.title}</b><span className="muted">{chosen.artistName}</span></span>
            </div>
          )}
          {chosen && (
            <label className="pick-on">On:
              <select value={station} onChange={(e) => { setStation(Number(e.target.value)); }}>
                {/* Only the stations that can play this track (radio.Queue checks the genre). */}
                {cat.stations.filter((x) => x.id === station || (x.tracks > 0 && (x.genre === 0 || x.genre === chosen.genre) && (x.name !== NEW_STATION || chosen.id > cat.newFloor)))
                  .map((x) => <option key={x.id} value={x.id}>{x.name}</option>)}
              </select>
            </label>
          )}
          <div className="pick-time">
            <div className="seg" role="group" aria-label="When">
              <button className={when === 0 ? "on" : ""} aria-pressed={when === 0} onClick={() => { setWhen(0); }}>Right away</button>
              <button className={when > 0 ? "on" : ""} aria-pressed={when > 0} onClick={() => { setWhen(firstFree); }}>At a time</button>
            </div>
            {when > 0 && (
              <div className="pick-clock">
                <input type="time" step={STEP} className="time-input" aria-label="Time, in your time zone" value={hhmm(when)} onChange={(e) => { const t = bookAt(e.target.value, now); if (t) setWhen(t); }} />
                <span className="muted small">{new Date(when * 1000).toDateString() === new Date(now * 1000).toDateString() ? "today" : "tomorrow"} · {gmt(when)}</span>
              </div>
            )}
          </div>
          <p className="pick-when">{!sched ? <Loader label="Reading the schedule" /> : <>Would air at <span className="mono">{hhmm(when > 0 ? when : airsAt)}</span>{when > 0 ? "" : ` · ${timing}`}</>}</p>
          {blocked && <p className="pick-blocked" role="status"><Shape g="square" size={10} /> {blocked}</p>}
          {refund > 0 && chosen && (
            <label className="pick-free">
              <input type="checkbox" checked={sponsoredPick} disabled={freeBlock !== ""} onChange={(e) => { setFree(e.target.checked); }} />
              <span>Free pick: {chosen.artistName} refunds it ({gnot(refund)}) after it has played in full.
                <span className="muted small"> {freeBlock ? `Not yet: ${freeBlock}.` : "Collect it in Me or the player within 7 days. No dedication, no curator point."}</span>
              </span>
            </label>
          )}
          {!sponsoredPick && <label className="pick-note">
            <span>Dedication <span className="muted">optional</span></span>
            <input maxLength={MAX_NOTE} placeholder="to the night shift" value={note} onChange={(e) => { setNote(e.target.value); }} aria-invalid={noteWhy !== ""} />
            <span className={noteWhy ? "error small" : "muted small"}>{noteWhy ? `Dedication: ${noteWhy}` : `Public and permanent · auto-checked · no full names · ${String(MAX_NOTE - note.length)} left`}</span>
          </label>}
          <div className="pick-push">
            {sponsoredPick && chosen && <b className="pick-freeline">Free pick: {chosen.artistName} refunds it</b>}
            {earn && <span className="pick-earn">{earn}</span>}
            <button className="push" disabled={!chosen || blocked !== "" || sent !== 0 || (noteWhy !== "" && !sponsoredPick)} onClick={push}>
              {sent ? "Signing…" : <><Icon name="on-air" size={18} /> Push on air</>}
            </button>
            <span className="fine pick-cost">Costs about {PICK_FEE} GNOT<br />+ about {PICK_DEPOSIT} GNOT locked for storage (up to {PICK_DEPOSIT_FIRST} the first time)</span>
            {asked && notice && (
              // A sent pick comes back with its explorer link; without one, it is a failure to read.
              <span className={notice.pending ? "pick-notice" : notice.link ? "pick-notice ok" : "pick-notice bad"} role={notice.pending || notice.link ? "status" : "alert"}>
                {notice.text}
                {notice.link && <> · <a href={notice.link} target="_blank" rel="noreferrer">View on gnoscan</a></>}
              </span>
            )}
          </div>
        </>)}
      </div>
    </dialog>
  );
}
