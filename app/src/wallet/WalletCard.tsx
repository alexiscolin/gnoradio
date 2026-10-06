import { useState } from "react";
import { CHAIN_ID } from "../lib/gno";
import { shortAddr } from "../lib/format";
import type { Wallet } from "./useWallet";
import { Composition } from "../components/Shapes";

const Arrow = () => (
  <svg viewBox="0 0 24 24" width="18" height="18" fill="none" stroke="currentColor" strokeWidth="2" strokeLinecap="round" aria-hidden="true">
    <path d="M5 12h14M13 6l6 6-6 6" />
  </svg>
);

/** WalletCard is the sidebar wallet block: state-aware, with a Bauhaus composition. */
export function WalletCard({ wallet }: { readonly wallet: Wallet }) {
  const [menu, setMenu] = useState(false);
  const s = wallet.state;

  if (s.status === "connected") {
    return (
      <div className="wcard on">
        <button className="wcard-head" onClick={() => { setMenu((m) => !m); }} aria-expanded={menu}>
          <span className="wcard-addr">
            <span className="lbl">Connected · {s.chainId}</span>
            <span className="mono">{shortAddr(s.address)}</span>
          </span>
          <i className="dot" aria-hidden="true" />
        </button>
        {menu && (
          <div className="wcard-menu">
            <button onClick={() => { void navigator.clipboard.writeText(s.address).catch(() => undefined); setMenu(false); }}>Copy address</button>
            <button onClick={() => { wallet.disconnect(); setMenu(false); }}>Disconnect</button>
          </div>
        )}
      </div>
    );
  }

  if (s.status === "wrong-network") {
    return (
      <button className="wcard warn" onClick={() => void wallet.fixNetwork()}>
        <span className="wcard-head as-div">
          <span className="wcard-addr">
            <span className="lbl">On {s.chainId}</span>
            <span>Switch to {CHAIN_ID}</span>
          </span>
          <Arrow />
        </span>
      </button>
    );
  }

  const missing = s.status === "missing";
  const label = missing ? "Get Adena" : s.status === "connecting" ? "Connecting…" : "Connect Adena";
  const body = (
    <>
      <span className="wcard-head as-div">
        <span>{label}</span>
        <Arrow />
      </span>
      <span className="wcard-art" aria-hidden="true">
        <Composition variant={0} />
      </span>
    </>
  );
  return missing ? (
    <a className="wcard" href="https://adena.app" target="_blank" rel="noreferrer">{body}</a>
  ) : (
    <button className="wcard" onClick={() => void wallet.connectWallet()} disabled={s.status === "connecting"}>{body}</button>
  );
}

/** WalletPill is the compact mobile version. */
export function WalletPill({ wallet }: { readonly wallet: Wallet }) {
  const s = wallet.state;
  if (s.status === "connected") return <span className="pill ink mono">{shortAddr(s.address)}</span>;
  if (s.status === "wrong-network") return <button className="pill red" onClick={() => void wallet.fixNetwork()}>Switch to {CHAIN_ID}</button>;
  if (s.status === "missing") {
    const mobile = /Android|iPhone|iPad/i.test(navigator.userAgent);
    return mobile ? <span className="pill" title="Adena runs as a desktop browser extension for now">Listen-only on mobile</span> : <a className="pill" href="https://adena.app" target="_blank" rel="noreferrer">Get Adena</a>;
  }
  return <button className="pill ink" onClick={() => void wallet.connectWallet()} disabled={s.status === "connecting"}>{s.status === "connecting" ? "Connecting…" : "Connect"}</button>;
}
