import { useEffect, useRef } from "react";
import { Icon } from "../components/Icons";
import { track } from "../lib/analytics";
import { isPhone } from "../lib/gno";
import type { Wallet } from "./useWallet";

// Adena has no phone app yet (adena.app lists iOS and Android as "coming soon", no deep link
// to open a page in it): phones get the site, computers the Chrome extension.
const ADENA_SITE = "https://adena.app";
const ADENA_STORE = "https://chrome.google.com/webstore/detail/adena/oefglhbffgfkcpboeackfgdagmlnihnh";

/** WalletSheet says, without jargon, that liking, picking and tipping need a wallet, and how to get one. */
export function WalletSheet({ wallet }: { readonly wallet: Wallet }) {
  const ref = useRef<HTMLDialogElement>(null);
  useEffect(() => {
    const d = ref.current;
    if (d && !d.open && typeof d.showModal === "function") d.showModal();
    return () => { d?.close(); };
  }, []);
  const close = () => { track("wallet_sheet", { choice: "close" }); wallet.closeAsk(); };
  const phone = isPhone();
  return (
    <dialog ref={ref} className="sheet walletsheet" aria-labelledby="walletsheet-title" onCancel={(e) => { e.preventDefault(); close(); }} onClick={(e) => { if (e.target === e.currentTarget) close(); }}>
      <div className="sheet-body">
        <div className="sheet-head">
          <b id="walletsheet-title">To like, pick or tip, you need a gno.land wallet</b>
          <button className="x" onClick={close} aria-label="Close"><Icon name="close" /></button>
        </div>
        <p className="muted small">
          {phone
            ? "Adena, the gno.land wallet, runs in Chrome on a computer. Its phone app is coming soon. Listening needs nothing."
            : "Adena is a free browser extension. Install it, then reload this page."}
        </p>
        <div className="walletsheet-go">
          {phone
            ? <a className="cta" href={ADENA_SITE} target="_blank" rel="noreferrer" onClick={() => { track("wallet_sheet", { choice: "install" }); }}>Get Adena <Icon name="external" size={14} /></a>
            : <>
              <a className="cta" href={ADENA_STORE} target="_blank" rel="noreferrer" onClick={() => { track("wallet_sheet", { choice: "install" }); }}>Install Adena <Icon name="external" size={14} /></a>
              <button className="cta ghost" onClick={() => { track("wallet_sheet", { choice: "later" }); wallet.closeAsk(); }}>Later</button>
            </>}
        </div>
        <button className="link small muted walletsheet-alt" onClick={() => { track("wallet_sheet", { choice: "gnokey" }); wallet.setSigner("gnokey"); wallet.closeAsk(); }}>Use gnokey instead</button>
      </div>
    </dialog>
  );
}
