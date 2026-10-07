import { useEffect, useRef, useState } from "react";

const MIN_MS = 2200; // the whole entrance (shapes, word, dot: about 1.7 s) plays even on a fast load
const EXIT_MS = 1350; // matches the .splash.out timeline in styles.css

interface SplashProps {
  readonly ready: boolean;
  readonly error: string;
  /** onLeave fires when the exit starts, so the app can rise in under the curtain. */
  readonly onLeave: () => void;
  readonly onDone: () => void;
  readonly onRetry: () => void;
}

/**
 * Splash is the loading poster. The shapes build the composition one by one,
 * keep a quiet beat while the chain answers, then the poster wipes away.
 */
export function Splash({ ready, error, onLeave, onDone, onRetry }: SplashProps) {
  const [leaving, setLeaving] = useState(false);
  // The poster comes with index.html and starts at the first paint, often before React mounts.
  const start = useRef(performance.getEntriesByName("first-contentful-paint")[0]?.startTime ?? performance.now());

  useEffect(() => {
    if (!ready || leaving) return;
    const wait = Math.max(0, MIN_MS - (performance.now() - start.current));
    const id = window.setTimeout(() => { setLeaving(true); onLeave(); }, wait);
    return () => { window.clearTimeout(id); };
  }, [ready, leaving, onLeave]);

  useEffect(() => {
    if (!leaving) return;
    const reduce = window.matchMedia("(prefers-reduced-motion: reduce)").matches;
    const id = window.setTimeout(onDone, reduce ? 0 : EXIT_MS);
    return () => { window.clearTimeout(id); };
  }, [leaving, onDone]);

  return (
    <div className={`splash${leaving ? " out" : ""}${error ? " err" : ""}`} aria-busy={!error && !leaving}>
      <div className="splash-poster" aria-hidden="true">
        <svg className="composition" viewBox="0 0 120 80" preserveAspectRatio="xMidYMid slice">
          <rect width="120" height="80" fill="var(--paper)" />
          <circle className="sp sp-circle" cx="30" cy="40" r="26" fill="var(--red)" />
          <path className="sp sp-quarter" d="M60 80V40a40 40 0 0 1 40 40z" fill="var(--ink)" />
          <rect className="sp sp-bar" x="74" y="6" width="38" height="20" fill="var(--blue)" />
          <path className="sp sp-tri" d="M104 40l12 22H92z" fill="var(--yellow)" />
        </svg>
      </div>
      <div className="splash-text">
        <p className="splash-kicker">Community radio · open music · on-chain</p>
        <p className="splash-word" aria-label="GnoRadio">
          <span className="ln"><span>Gno</span></span>
          <span className="ln"><span>Radio<i className="dot" /></span></span>
        </p>
        <p className="splash-state" role="status">{error ? "GnoRadio can't reach gno.land right now. Check your connection, or try again in a moment." : "Tuning in…"}</p>
        {error && (
          <div className="splash-retry">
            <button className="cta" onClick={onRetry}>Try again</button>
            <details><summary className="muted small">Details</summary><p className="muted small mono">{error}</p></details>
          </div>
        )}
      </div>
      <div className="splash-curtain" aria-hidden="true" />
    </div>
  );
}
