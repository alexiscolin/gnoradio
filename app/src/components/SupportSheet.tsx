import { useEffect, useRef, useState } from "react";
import { gnot, shortAddr } from "../lib/format";
import type { Artist, Track } from "../lib/types";
import { Shape } from "./Shapes";

const AMOUNTS = [1, 5, 20] as const;
const UGNOT = 1_000_000;
export const DEFAULT_SUPPORT_PCT = 10;

export type SupportTarget =
  | { readonly kind: "tip"; readonly track: Track; readonly artist: Artist }
  | { readonly kind: "platform" };

interface Props {
  readonly target: SupportTarget;
  readonly codeURL: string;
  readonly onClose: () => void;
  readonly onTip: (t: Track, totalUgnot: number, supportPct: number) => void;
  readonly onSupport: (ugnot: number) => void;
}

/** SupportSheet picks an amount and shows exactly where every GNOT goes. */
export function SupportSheet({ target, codeURL, onClose, onTip, onSupport }: Props) {
  const ref = useRef<HTMLDialogElement>(null);
  useEffect(() => {
    const d = ref.current;
    if (d && !d.open && typeof d.showModal === "function") d.showModal();
    return () => { d?.close(); };
  }, []);
  const [amount, setAmount] = useState<number>(5);
  const [custom, setCustom] = useState("");
  const [pct, setPct] = useState(DEFAULT_SUPPORT_PCT);
  const gnots = custom ? Number.parseFloat(custom.replace(",", ".")) : amount;
  const valid = Number.isFinite(gnots) && gnots >= 0.1 && gnots <= 1_000_000;
  const artistUgnot = Math.round((valid ? gnots : 0) * UGNOT);
  const isTip = target.kind === "tip";
  const platformUgnot = isTip ? Math.round((artistUgnot * pct) / 100) : artistUgnot;
  const total = isTip ? artistUgnot + platformUgnot : artistUgnot;

  const splits = isTip ? target.track.splits : [];
  const artistPct = 100 - splits.reduce((s, x) => s + x.pct, 0);

  return (
    <dialog
      ref={ref}
      className="sheet"
      aria-label={isTip ? "Support the artist" : "Support GnoRadio"}
      onCancel={(e) => { e.preventDefault(); onClose(); }}
      onClick={(e) => { if (e.target === e.currentTarget) onClose(); }}
    >
      <div className="sheet-body">
        <div className="sheet-head">
          <Shape g="square" size={18} />
          <span>{isTip ? <>Support <b>{target.artist.name}</b></> : <>Keep <b>GnoRadio</b> on air</>}</span>
          <button className="x" onClick={onClose} aria-label="Close">×</button>
        </div>
        {isTip && <p className="muted small">For “{target.track.title}”. Sent in one transaction, straight to their wallet.</p>}
        {!isTip && <p className="muted small">Pays for hosting, storage and the indexer. Goes to the public GnoRadio treasury.</p>}

        <div className="amounts" role="radiogroup" aria-label="Amount">
          {AMOUNTS.map((a) => (
            <button key={a} role="radio" aria-checked={!custom && amount === a} className={!custom && amount === a ? "on" : ""} onClick={() => { setAmount(a); setCustom(""); }}>
              {a}<small>GNOT</small>
            </button>
          ))}
          <label className={`custom${custom ? " on" : ""}`}>
            <span className="sr">Custom amount in GNOT</span>
            <input inputMode="decimal" placeholder="Other" value={custom} onChange={(e) => { setCustom(e.target.value); }} />
          </label>
        </div>

        {isTip && (
          <label className="toggle">
            <input type="checkbox" checked={pct > 0} onChange={(e) => { setPct(e.target.checked ? DEFAULT_SUPPORT_PCT : 0); }} />
            <span>Add {DEFAULT_SUPPORT_PCT}% to keep GnoRadio running</span>
          </label>
        )}

        <div className="flow">
          {isTip && (
            <>
              <div><span>{target.artist.name} <span className="muted">artist</span></span><b className="mono">{gnot((artistUgnot * artistPct) / 100)}</b></div>
              {splits.map((s) => (
                <div key={s.to}><span>{shortAddr(s.to)} <span className="muted">collaborator · {s.pct}%</span></span><b className="mono">{gnot((artistUgnot * s.pct) / 100)}</b></div>
              ))}
            </>
          )}
          {platformUgnot > 0 && <div><span>GnoRadio <span className="muted">treasury</span></span><b className="mono">{gnot(platformUgnot)}</b></div>}
          <div className="total"><span>Total</span><b className="mono">{gnot(total)}</b></div>
        </div>

        <button
          className="send"
          disabled={!valid}
          onClick={() => {
            if (isTip) onTip(target.track, total, pct);
            else onSupport(total);
            onClose();
          }}
        >
          Send {gnot(total)} with Adena
        </button>
        <p className="fine">
          <Shape g="quarter" size={10} /> {isTip ? "0% taken from the artist." : "Every GNOT is visible on-chain."} <a href={codeURL} target="_blank" rel="noreferrer">Read the code</a>
        </p>
      </div>
    </dialog>
  );
}
