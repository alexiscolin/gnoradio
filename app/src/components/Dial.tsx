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
}

const TICKS = 60;
const GLIDE_MS = 700;

/**
 * useGlide follows frac without ever swinging back and forth:
 * - forward jumps (tuning in, a seek ahead) glide there; backward ones snap;
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
    if (window.matchMedia("(prefers-reduced-motion: reduce)").matches || frac < start || frac - start < 0.02) {
      snap(frac);
      return;
    }
    const t0 = performance.now();
    let id = 0;
    const step = (now: number) => {
      const k = Math.min(1, (now - t0) / GLIDE_MS);
      snap(start + (frac - start) * (1 - (1 - k) ** 3)); // ease-out cubic
      if (k < 1) id = requestAnimationFrame(step);
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

/**
 * Dial is the player's Bauhaus clock: a full circle of ticks, an ink arc for
 * the elapsed time and a coloured marker on the rim (red when live).
 */
export function Dial({ frac, seconds, caption, live, onSeek, buffering = false, tuning = false }: DialProps) {
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
      </div>
    </div>
  );
}
