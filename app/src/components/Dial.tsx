import { type KeyboardEvent, type PointerEvent, useCallback, useEffect, useRef, useState } from "react";
import { clock } from "../lib/format";

interface DialProps {
  readonly frac: number;
  readonly seconds: number;
  readonly caption: string;
  readonly live: boolean;
  readonly onSeek?: ((frac: number) => void) | undefined;
  readonly buffering?: boolean;
  /** tuning: the station is still being read; the dial shows the Bauhaus shapes instead of 00:00. */
  readonly tuning?: boolean;
  /** chain: the track's page on gnoweb, a small link under the caption. */
  readonly chain?: { readonly href: string; readonly label: string } | undefined;
}

const TICKS = 60;
const GLIDE_MS = 700;
const STEADY_MS = 300; // a bit more than the ~250 ms between playback time reports

/**
 * useGlide follows frac without ever swinging back and forth:
 * - a jump (tuning in, another station, Lib/Live) glides straight there, forward or back,
 *   the short way round (a new track goes on past the top, not back around the dial);
 * - a 0 while the next station or track loads keeps the last position (up to 2 s)
 *   instead of falling to the top and climbing again;
 * - place(v) shows a seek at once and ignores stale positions until the player reaches it.
 */
function useGlide(frac: number): readonly [number, (v: number) => void] {
  const [shown, setShown] = useState(0);
  const from = useRef(0);
  const pin = useRef<{ v: number; until: number } | null>(null);
  useEffect(() => {
    const p = pin.current;
    if (p) {
      if (Math.abs(frac - p.v) > 0.03 && performance.now() < p.until) return; // the player has not caught up yet
      pin.current = null;
    }
    const snap = (v: number) => { from.current = v; setShown(v); };
    if (frac === 0 && from.current > 0) {
      const id = window.setTimeout(() => { snap(0); }, 2000);
      return () => { window.clearTimeout(id); };
    }
    const start = from.current;
    const reduce = window.matchMedia("(prefers-reduced-motion: reduce)").matches;
    // Playback reports its time about 4 times a second: between two reports the ring
    // moves on at a steady pace (linear, a little longer than the gap) instead of ticking.
    const steady = frac > start && frac - start < 0.02;
    if (reduce || (!steady && Math.abs(frac - start) < 0.02)) {
      snap(frac);
      return;
    }
    // The short way round: from the end of a track to the start of the next, it goes on past the top.
    const end = frac - start < -0.5 ? frac + 1 : frac;
    const t0 = performance.now();
    const span = steady ? STEADY_MS : GLIDE_MS;
    let id = 0;
    const step = (now: number) => {
      const k = Math.min(1, (now - t0) / span);
      snap((start + (end - start) * (steady ? k : 1 - (1 - k) ** 3)) % 1); // steady: linear; a jump: ease-out cubic
      if (k < 1) id = requestAnimationFrame(step);
      else snap(frac);
    };
    id = requestAnimationFrame(step);
    return () => { cancelAnimationFrame(id); };
  }, [frac]);
  const place = useCallback((v: number) => {
    pin.current = { v, until: performance.now() + 1500 };
    from.current = v;
    setShown(v);
  }, []);
  return [shown, place] as const;
}
const R = 100;

/** GnoMark is gno.land's gnome (hat and beard, from gnoweb's logo), in one colour. */
const GnoMark = () => (
  <svg viewBox="8 3 18 28" width="6" height="9" fill="currentColor" aria-hidden="true">
    <path d="M24.1944 17.4535C23.9204 15.2083 23.0928 12.9603 22.0882 10.935C21.1893 9.12255 21.4167 6.906 22.8612 5.48951V5.48951C23.4216 4.93994 23.0246 4 22.2318 4H16.9011C16.4897 4 16.0772 4.17774 15.7992 4.53212C13.9222 6.92776 10.2472 12.1988 9.60562 17.4535C9.5478 17.9322 10.1205 18.2255 10.4874 17.905C11.7684 16.7862 13.7665 15.9858 16.9 15.9858C20.0335 15.9858 22.0306 16.7873 23.3126 17.905C23.6796 18.2255 24.2522 17.9311 24.1944 17.4535Z" />
    <path d="M24.3981 21.4357C24.3981 21.4353 24.3981 21.435 24.398 21.4346C24.2011 20.7261 23.7808 20.1025 23.2105 19.6262C22.9904 19.4419 22.7502 19.2674 22.4878 19.1049C22.2654 18.9665 21.9852 19.1704 22.0497 19.4212L22.2076 20.034C22.4077 20.8125 21.556 21.4439 20.8465 21.0437L18.9395 19.9685C17.6864 19.262 16.1452 19.262 14.892 19.9685L12.985 21.0437C12.2756 21.4439 11.4239 20.8114 11.624 20.034L11.7864 19.4037C11.8509 19.154 11.5718 18.9501 11.3494 19.0875C11.058 19.2663 10.7934 19.4604 10.5532 19.6643C9.99168 20.1419 9.60138 20.7831 9.41902 21.4897L9.41235 21.5158C8.94867 23.3216 9.66921 25.22 11.2237 26.2897L16.0385 29.6013C16.5655 29.9633 17.2672 29.9633 17.7942 29.6013L22.609 26.2897C24.1867 25.2048 24.905 23.2652 24.3982 21.4368Z" />
  </svg>
);

/**
 * Dial is the player's Bauhaus clock: a full circle of ticks, an ink arc for
 * the elapsed time and a coloured marker on the rim (red when live).
 */
export function Dial({ frac, seconds, caption, live, onSeek, buffering = false, tuning = false, chain }: DialProps) {
  const target = Math.min(1, Math.max(0, Number.isFinite(frac) ? frac : 0));
  const [glided, place] = useGlide(target);
  // Library only: drag the ring (forwards or back); the time follows, the seek happens on release.
  const [drag, setDrag] = useState<number | null>(null);
  const f = drag ?? glided;
  const angle = f * 2 * Math.PI - Math.PI / 2;
  const mx = 120 + R * Math.cos(angle);
  const my = 120 + R * Math.sin(angle);
  const large = f > 0.5 ? 1 : 0;
  const arc = f <= 0 ? "" : f >= 1 ? `M120 20a100 100 0 1 1 -0.01 0` : `M120 20A100 100 0 ${String(large)} 1 ${mx.toFixed(2)} ${my.toFixed(2)}`;
  const shownSeconds = drag !== null && f > 0 && target > 0 ? (seconds / target) * drag : seconds;
  const t = `${shownSeconds < 600 ? "0" : ""}${clock(shownSeconds)}`;
  const lead = /^[0:]*/.exec(t)?.[0] ?? "";

  const at = (e: PointerEvent<SVGSVGElement>): number => {
    const r = e.currentTarget.getBoundingClientRect();
    let a = Math.atan2(e.clientY - r.top - r.height / 2, e.clientX - r.left - r.width / 2) + Math.PI / 2;
    if (a < 0) a += 2 * Math.PI;
    return a / (2 * Math.PI);
  };
  const down = (e: PointerEvent<SVGSVGElement>) => {
    if (!onSeek) return;
    e.currentTarget.setPointerCapture(e.pointerId);
    setDrag(at(e));
  };
  const move = (e: PointerEvent<SVGSVGElement>) => { if (drag !== null) setDrag(at(e)); };
  const up = () => {
    if (drag === null || !onSeek) return;
    place(drag); // the ring stays where it was let go, no flash back to the old time
    onSeek(drag);
    setDrag(null);
  };

  const key = (e: KeyboardEvent<SVGSVGElement>) => {
    if (!onSeek) return;
    const total = f > 0 ? seconds / f : 0;
    const stepFrac = total > 0 ? 5 / total : 0.02;
    const moves: Record<string, number> = { ArrowRight: f + stepFrac, ArrowUp: f + stepFrac, ArrowLeft: f - stepFrac, ArrowDown: f - stepFrac, Home: 0, End: 0.999 };
    const to = moves[e.key];
    if (to === undefined) return;
    e.preventDefault();
    place(Math.min(1, Math.max(0, to)));
    onSeek(Math.min(1, Math.max(0, to)));
  };

  return (
    <div className="dial">
      <svg
        viewBox="0 0 240 240"
        onPointerDown={down}
        onPointerMove={move}
        onPointerUp={up}
        onPointerCancel={() => { setDrag(null); }}
        onKeyDown={key}
        {...(onSeek
          ? { role: "slider", tabIndex: 0, "aria-label": "Position", "aria-valuemin": 0, "aria-valuemax": 100, "aria-valuenow": Math.round(f * 100), "aria-valuetext": `${clock(seconds)} · ${caption}` }
          : { role: "img", "aria-label": `${clock(seconds)} · ${caption}` })}
        className={onSeek ? "seekable" : ""}
      >
        {Array.from({ length: TICKS }, (_, i) => {
          const a = (i / TICKS) * 2 * Math.PI - Math.PI / 2;
          const long = i % 5 === 0;
          const r1 = long ? 110 : 113;
          const done = i / TICKS <= f;
          return (
            <line
              key={i}
              x1={120 + r1 * Math.cos(a)}
              y1={120 + r1 * Math.sin(a)}
              x2={120 + 118 * Math.cos(a)}
              y2={120 + 118 * Math.sin(a)}
              stroke={done ? "var(--ink)" : "var(--tick)"}
              strokeWidth={long ? 1.6 : 1}
              style={buffering ? { animationDelay: `${String((i / TICKS) * 1.2)}s` } : undefined}
            />
          );
        })}
        <circle cx="120" cy="120" r={R} fill="none" stroke="var(--line)" strokeWidth="6" />
        {arc && <path d={arc} fill="none" stroke="var(--ink)" strokeWidth="6" />}
        <circle cx={mx} cy={my} r="9" fill={live ? "var(--red)" : "var(--blue)"} stroke="var(--card)" strokeWidth="3" />
      </svg>
      <div className="dial-center">
        {tuning
          ? <span className="dial-tuning" role="status" aria-label="Tuning in"><i className="c" /><i className="q" /><i className="s" /><i className="t" /></span>
          : <span className="dial-time" aria-label={clock(seconds)}><span>{lead}</span>{t.slice(lead.length)}</span>}
        {tuning
          ? <span className="muted small">Tuning in…</span>
          : buffering
          ? <span className="dial-loading" role="status" aria-label="Buffering"><i className="c" /><i className="s" /><i className="t" /></span>
          : <span className="muted small">{caption}</span>}
        {chain && !tuning && <a className="dial-chain" href={chain.href} target="_blank" rel="noreferrer" aria-label={chain.label} title="On gno.land"><GnoMark /></a>}
      </div>
    </div>
  );
}
