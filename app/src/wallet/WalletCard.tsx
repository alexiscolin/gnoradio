import { useEffect, useState } from "react";
import { nameOf, nameReg, useNames } from "../lib/names";
import { NameSheet } from "./NameSheet";
import { CHAIN_ID } from "../lib/gno";
import type { Wallet } from "./useWallet";
import { Icon } from "../components/Icons";
import { Composition } from "../components/Shapes";
import { Help } from "../components/Help";
import { DAILY_UGNOT, DAYS } from "../lib/session";

const REVOKE = "To fully revoke access, remove GnoRadio in Adena › Settings › Connected sites.";

const GNOKEY_HELP = "No browser wallet? Every action then shows the exact gnokey command to sign in your terminal.";

/** SignOptions is one quiet line under the card: the other way to sign, or quick actions once Adena is connected. */
function SignOptions({ wallet }: { readonly wallet: Wallet }) {
  if (wallet.signer === "gnokey") {
    return <div className="signwith"><button className="link small" onClick={() => { wallet.setSigner("adena"); }}>Use Adena instead</button></div>;
  }
  if (wallet.state.status === "connected") {
    return (
      <div className="signwith">
        <label><input type="checkbox" role="switch" checked={wallet.quick} onChange={(e) => void wallet.setQuick(e.target.checked)} /> Quick actions</label>
        <Help text={`Approve once in Adena: likes, follows, picks and other GnoRadio actions without coins then go through without a prompt for ${String(DAYS)} days, spending at most ${String(DAILY_UGNOT / 1e6)} GNOT a day (fees and deposits). The key stays in this browser; turning it off revokes it. Tips and tickets always ask Adena.`} />
      </div>
    );
  }
  return (
    <div className="signwith">
      <button className="link small" onClick={() => { wallet.setSigner("gnokey"); }} title={GNOKEY_HELP}>No wallet? Sign with gnokey</button>
    </div>
  );
}

/** WalletCard is the sidebar wallet block (one card, same footprint in every state) and how actions get signed. */
export function WalletCard(props: { readonly wallet: Wallet; readonly onRegister: (name: string) => void }) {
  return <><Card {...props} /><SignOptions wallet={props.wallet} /></>;
}

function Card({ wallet, onRegister }: { readonly wallet: Wallet; readonly onRegister: (name: string) => void }) {
  const s = wallet.state;
  const [naming, setNaming] = useState(false);
  const [reg, setReg] = useState(false);
  const address = s.status === "connected" ? s.address : "";
  const show = useNames(address ? [address] : []);
  useEffect(() => { void nameReg().then((r) => { setReg(r !== ""); }); }, []);
  if (s.status === "connected") {
    const named = nameOf(s.address) !== "";
    return (
      <div className="wcard on wc">
        <i className="wc-shape" aria-hidden="true" />
        <span className="wc-label"><i className="status" aria-hidden="true" />Connected</span>
        <span className="wc-addr mono" title={s.address}>{show(s.address)}</span>
        {!named && reg && <button className="link small wc-name" onClick={() => { setNaming(true); }}>Choose a name</button>}
        {naming && <NameSheet onRegister={onRegister} onClose={() => { setNaming(false); }} />}
        <button className="wc-out" onClick={wallet.disconnect} title={REVOKE}>Disconnect</button>
      </div>
    );
  }
  if (s.status === "wrong-network") {
    return (
      <button className="wcard warn" onClick={() => void wallet.fixNetwork()}>
        <span className="wcard-head as-div"><span>Switch to {CHAIN_ID}</span><Icon name="arrow-right" className="nudge" /></span>
      </button>
    );
  }
  if (wallet.signer === "gnokey") {
    return (
      <div className="wcard on wc">
        <i className="wc-shape" aria-hidden="true" />
        <span className="wc-label">Signing with gnokey</span>
        <span className="small muted">Each action shows a command to copy into your terminal.</span>
      </div>
    );
  }
  const missing = s.status === "missing";
  const body = (
    <>
      <span className="wcard-head as-div">
        <span>{missing ? "Get Adena" : s.status === "connecting" ? "Connecting…" : "Connect Adena"}</span>
        <Icon name={missing ? "external" : "arrow-right"} className={missing ? "nudge-out" : "nudge"} />
      </span>
      <span className="wcard-art" aria-hidden="true"><Composition variant={0} /></span>
    </>
  );
  return missing ? (
    <a className="wcard" href="https://adena.app" target="_blank" rel="noreferrer">{body}</a>
  ) : (
    <button className="wcard" onClick={() => void wallet.connectWallet()} disabled={s.status === "connecting"}>{body}</button>
  );
}

/** WalletPill is the mobile top-bar version; tapping the address offers Disconnect. */
export function WalletPill({ wallet }: { readonly wallet: Wallet }) {
  const [menu, setMenu] = useState(false);
  const s = wallet.state;
  const show = useNames(s.status === "connected" ? [s.address] : []);
  if (s.status === "connected") {
    return (
      <span className="pill-wrap">
        <button className="pill mono" aria-expanded={menu} onClick={() => { setMenu((m) => !m); }}>{show(s.address)}</button>
        {menu && (
          <span className="pill-menu">
            <span className="mono"><i className="status" aria-hidden="true" />{show(s.address)}</span>
            <button className="btn-out" onClick={() => { wallet.disconnect(); setMenu(false); }}>Disconnect</button>
            <small>{REVOKE}</small>
            <SignOptions wallet={wallet} />
          </span>
        )}
      </span>
    );
  }
  if (s.status === "wrong-network") return <button className="pill red" onClick={() => void wallet.fixNetwork()}>Switch to {CHAIN_ID}</button>;
  // No Adena on phones yet: listening needs no wallet, so show nothing.
  if (s.status === "missing") return /Android|iPhone|iPad/i.test(navigator.userAgent) ? null : <a className="pill" href="https://adena.app" target="_blank" rel="noreferrer">Get Adena</a>;
  return <button className="pill" onClick={() => void wallet.connectWallet()} disabled={s.status === "connecting"}>{s.status === "connecting" ? "Connecting…" : "Connect"}</button>;
}
