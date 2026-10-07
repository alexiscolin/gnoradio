import { Help } from "./Help";
import { Icon } from "./Icons";
import { useEffect, useRef, useState } from "react";
import { UGNOT, gnot, shortAddr } from "../lib/format";
import { CHAIN_ID } from "../lib/gno";
import { promoSplit } from "../lib/incentives";
import { useNames } from "../lib/names";
import type { Artist, Track } from "../lib/types";
import { Shape } from "./Shapes";

const AMOUNTS = [1, 5, 20] as const;
// What each amount feels like, in words: no fiat conversion.
const HINTS = ["a coffee", "an album", "a concert"] as const;
const DEFAULT_SUPPORT_PCT = 10;
const MAX_GNOT = 1_000_000;

/** A tip made on the radio names its station and who picked the track on air (the radio checks both). */
export type SupportTarget =
  | { readonly kind: "tip"; readonly track: Track; readonly artist: Artist; readonly station?: number | undefined; readonly picker?: string | undefined }
  | { readonly kind: "platform" };

interface Props {
  readonly target: SupportTarget;
  readonly codeURL: string;
  /** me is the connected wallet, referrer the address whose shared link opened this session. */
  readonly me?: string | undefined;
  readonly referrer?: string | undefined;
  readonly onClose: () => void;
  readonly onTip: (t: Track, totalUgnot: number, supportPct: number, station?: number, ref?: string) => void;
  readonly onSupport: (ugnot: number) => void;
}

/** SupportSheet picks an amount and shows exactly where every GNOT goes. */
export function SupportSheet({ target, codeURL, me = "", referrer = "", onClose, onTip, onSupport }: Props) {
  const ref = useRef<HTMLDialogElement>(null);
  useEffect(() => {
    const d = ref.current;
    if (d && !d.open && typeof d.showModal === "function") d.showModal();
    return () => { d?.close(); };
  }, []);
  const [amount, setAmount] = useState<number>(5);
  const [custom, setCustom] = useState("");
  const [pct, setPct] = useState(0);
  const gnots = custom ? Number.parseFloat(custom.replace(",", ".")) : amount;
  const valid = Number.isFinite(gnots) && gnots >= 0.1 && gnots <= MAX_GNOT;
  const artistUgnot = Math.round((valid ? gnots : 0) * UGNOT);
  const isTip = target.kind === "tip";
  const platformUgnot = isTip ? Math.round((artistUgnot * pct) / 100) : artistUgnot;
  const total = isTip ? artistUgnot + platformUgnot : artistUgnot;

  const splits = isTip ? target.track.splits : [];
  const artistPct = 100 - splits.reduce((s, x) => s + x.pct, 0);
  // The realm's own arithmetic: the artist side is total*100/(100+pct), the promo share comes out of it.
  const artistSide = isTip ? Math.floor((total * 100) / (100 + pct)) : 0;
  const promo = isTip ? target.artist.promo : 0;
  const picker = isTip ? target.picker ?? "" : "";
  const { toPicker, toRef } = promoSplit(artistSide, promo, { picker, ref: referrer, tipper: me, owner: isTip ? target.artist.owner : "" });
  const toArtists = artistSide - toPicker - toRef;
  const who = useNames([picker, referrer].filter(Boolean));
  // The realm refuses a tip to yourself (social.gno).
  const own = isTip && me !== "" && target.artist.owner === me;

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
          <button className="x" onClick={onClose} aria-label="Close"><Icon name="close" /></button>
        </div>
        {isTip && <p className="muted small">For “{target.track.title}”. Sent in one transaction, straight to their wallet.</p>}
        {!isTip && <p className="muted small">Pays for hosting, storage and the indexer. Goes to the public GnoRadio treasury.</p>}

        <div className="amounts" role="radiogroup" aria-label="Amount">
          {AMOUNTS.map((a, i) => (
            <button key={a} role="radio" aria-checked={!custom && amount === a} className={!custom && amount === a ? "on" : ""} onClick={() => { setAmount(a); setCustom(""); }}>
              {a}<small>GNOT</small><span className="hint">{HINTS[i]}</span>
            </button>
          ))}
          <label className={`custom${custom ? " on" : ""}`}>
            <span className="sr">Custom amount in GNOT</span>
            <input inputMode="decimal" autoComplete="off" placeholder="Other" value={custom} onChange={(e) => { setCustom(e.target.value); }} />
          </label>
        </div>

        {isTip && (
          <label className="toggle">
            <input type="checkbox" checked={pct > 0} onChange={(e) => { setPct(e.target.checked ? DEFAULT_SUPPORT_PCT : 0); }} />
            <span>Add {DEFAULT_SUPPORT_PCT}% to keep GnoRadio running</span>
            <Help text="Your tip goes to the artist in the same transaction; GnoRadio takes nothing from it. The optional 10% is added on top and goes to the GnoRadio treasury: hosting, storage, indexer." />
          </label>
        )}

        <div className="flow">
          {isTip && (
            <>
              <div><span>{target.artist.name} <span className="muted">artist</span></span><b className="mono">{gnot((toArtists * artistPct) / 100)}</b></div>
              {splits.map((s) => (
                <div key={s.to}><span>{shortAddr(s.to)} <span className="muted">collaborator · {s.pct}%</span></span><b className="mono">{gnot((toArtists * s.pct) / 100)}</b></div>
              ))}
              {toPicker > 0 && <div className="promo"><span>{who(picker)} <span className="muted">picked it on air</span></span><b className="mono">{gnot(toPicker)}</b></div>}
              {toRef > 0 && <div className="promo"><span>{who(referrer)} <span className="muted">shared the link</span></span><b className="mono">{gnot(toRef)}</b></div>}
            </>
          )}
          {platformUgnot > 0 && <div><span>GnoRadio <span className="muted">treasury</span></span><b className="mono">{gnot(platformUgnot)}</b></div>}
          <div className="total"><span>Total</span><b className="mono">{gnot(total)}</b></div>
        </div>

        {(toPicker > 0 || toRef > 0) && (
          <p className="promo-note small">
            {promo}% {toPicker > 0 && toRef > 0 ? "is split between" : "goes to"} {[toPicker > 0 ? `${who(picker)} who played this` : "", toRef > 0 ? `${who(referrer)} who shared it` : ""].filter(Boolean).join(" and ")}: the artist's promo share. The radio checks who picked it.
          </p>
        )}

        <button
          className="send"
          disabled={!valid || own}
          onClick={() => {
            if (isTip) onTip(target.track, total, pct, target.station, toRef > 0 ? referrer : undefined);
            else onSupport(total);
            onClose();
          }}
        >
          {own ? "You can't tip your own track" : valid ? `Send ${gnot(total)} with Adena` : "Enter between 0.1 and 1,000,000 GNOT"}
        </button>
        <p className="fine">
          A gift, not a purchase: final once sent, GnoRadio cannot refund it.
          {CHAIN_ID !== "gnoland-1" && <> Test GNOT on {CHAIN_ID === "dev" ? "the local devnet" : "onyx"}: no real value.</>}
        </p>
        <p className="fine">
          <Shape g="quarter" size={10} /> {isTip ? "GnoRadio takes nothing from the artist." : "Every GNOT is visible on-chain."} <a href={codeURL} target="_blank" rel="noreferrer">Read the code</a>
        </p>
      </div>
    </dialog>
  );
}
