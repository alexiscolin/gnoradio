import { type KeyboardEvent, type PointerEvent, useEffect, useRef, useState } from "react";
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
 * useGlide follows frac, but a jump (tuning in, a new track, a seek) glides
 * there instead of snapping; the steady second-by-second advance is followed as is.
 */
function useGlide(frac: number): number {
  const [shown, setShown] = useState(0);
  const from = useRef(0);
  useEffect(() => {
    const start = from.current;
    const reduce = window.matchMedia("(prefers-reduced-motion: reduce)").matches;
    if (reduce || Math.abs(frac - start) < 0.02) {
      from.current = frac;
      setShown(frac);
      return;
    }
    const t0 = performance.now();
    let id = 0;
    const step = (now: number) => {
      const k = Math.min(1, (now - t0) / GLIDE_MS);
      const v = start + (frac - start) * (1 - (1 - k) ** 3); // ease-out cubic
      from.current = v;
      setShown(v);
      if (k < 1) id = requestAnimationFrame(step);
    };
    id = requestAnimationFrame(step);
    return () => { cancelAnimationFrame(id); };
  }, [frac]);
  return shown;
}
const R = 100;

/**
 * Dial is the player's Bauhaus clock: a full circle of ticks, an ink arc for
 * the elapsed time and a coloured marker on the rim (red when live).
 */
export function Dial({ frac, seconds, caption, live, onSeek, buffering = false, tuning = false }: DialProps) {
  const target = Math.min(1, Math.max(0, Number.isFinite(frac) ? frac : 0));
  const glided = useGlide(target);
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
