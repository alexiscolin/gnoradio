import { useEffect, useRef, useState } from "react";
import { Icon } from "./Icons";
import { Help } from "./Help";
import { CHAIN_ID, type Call, WALLET_RPC, hasAdena } from "../lib/gno";
import { gnokeyCommand } from "../lib/gnokey";

const KEY = "gnoradio.gnokeyName";
const savedKey = () => { try { return localStorage.getItem(KEY) ?? ""; } catch { return ""; } };

/** GnokeySheet shows an action as the gnokey command that signs it, ready to copy. */
export function GnokeySheet({ label, call, onClose }: { readonly label: string; readonly call: Call; readonly onClose: () => void }) {
  const ref = useRef<HTMLDialogElement>(null);
  useEffect(() => {
    const d = ref.current;
    if (d && !d.open && typeof d.showModal === "function") d.showModal();
    return () => { d?.close(); };
  }, []);
  const [key, setKey] = useState(savedKey);
  const [copied, setCopied] = useState(false);
  const command = gnokeyCommand(call, CHAIN_ID, WALLET_RPC, key);
  const copy = async () => {
    await navigator.clipboard.writeText(command);
    setCopied(true);
    setTimeout(() => { setCopied(false); }, 1800);
  };
  return (
    <dialog ref={ref} className="sheet gnokey" aria-label={`${label} with gnokey`} onCancel={(e) => { e.preventDefault(); onClose(); }} onClick={(e) => { if (e.target === e.currentTarget) onClose(); }}>
      <div className="sheet-body">
        <div className="sheet-head">
          <span><b>{label}</b> with gnokey</span>
          <Help text="gnokey is gno.land's command-line wallet. Your key stays in your terminal; GnoRadio only writes the command." more="https://docs.gno.land/users/interact-with-gnokey" />
          <button className="x" onClick={onClose} aria-label="Close"><Icon name="close" /></button>
        </div>
        {!hasAdena() && <p className="muted small">No Adena in this browser: run this in a terminal where gnokey has your key.</p>}
        <label className="field">Your key name
          <input value={key} autoComplete="off" autoCapitalize="none" spellCheck={false} maxLength={64} placeholder="gnokey list shows it"
            onChange={(e) => { setKey(e.target.value); try { localStorage.setItem(KEY, e.target.value.trim()); } catch { /* this visit only */ } }} />
        </label>
        <pre className="mono gnokey-cmd">{command}</pre>
        <button className="send" onClick={() => void copy()}>{copied ? "Copied" : "Copy command"}</button>
        <p className="muted small">Paste it in a terminal and type your key's password. Done when it prints <b>OK!</b>; close this to refresh.</p>
      </div>
    </dialog>
  );
}
