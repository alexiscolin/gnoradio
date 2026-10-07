import { useEffect, useRef, useState } from "react";
import { Icon } from "../components/Icons";
import { nameProblem, nameShape } from "../lib/names";

/** NameSheet lets a connected listener take a gno.land name, checked live against the registrar. */
export function NameSheet({ onRegister, onClose }: { readonly onRegister: (name: string) => void; readonly onClose: () => void }) {
  const ref = useRef<HTMLDialogElement>(null);
  useEffect(() => {
    const d = ref.current;
    if (d && !d.open && typeof d.showModal === "function") d.showModal();
    return () => { d?.close(); };
  }, []);
  const [name, setName] = useState("");
  const [problem, setProblem] = useState("");
  const [checking, setChecking] = useState(false);
  useEffect(() => {
    if (!name) { setProblem(""); return; }
    if (!nameShape(name)) { setProblem("Lowercase letters, digits, dashes and underscores only."); return; }
    setChecking(true);
    let alive = true;
    const id = window.setTimeout(() => {
      nameProblem(name).then((p) => { if (alive) setProblem(p); }, () => { if (alive) setProblem("The chain did not answer. Try again."); }).finally(() => { if (alive) setChecking(false); });
    }, 300);
    return () => { alive = false; window.clearTimeout(id); };
  }, [name]);
  const ok = name !== "" && !problem && !checking;
  return (
    <dialog ref={ref} className="sheet" aria-label="Choose a name" onCancel={(e) => { e.preventDefault(); onClose(); }} onClick={(e) => { if (e.target === e.currentTarget) onClose(); }}>
      <div className="sheet-body">
        <div className="sheet-head"><span>Choose your <b>gno.land name</b></span><button className="x" onClick={onClose} aria-label="Close"><Icon name="close" /></button></div>
        <p className="muted small">It replaces your address everywhere on gno.land, GnoRadio included.</p>
        <label className="field">Name
          <span className="with-prefix"><span>@</span><input value={name} autoComplete="off" autoCapitalize="none" spellCheck={false} maxLength={64} placeholder="lea_kosmos" onChange={(e) => { setName(e.target.value.trim()); }} /></span>
        </label>
        <p className={`small ${problem ? "error" : "muted"}`} role="status">{checking ? "Checking…" : problem || (name ? "Available." : "One signature, no fee on this chain.")}</p>
        <button className="send" disabled={!ok} onClick={() => { onRegister(name); onClose(); }}>{ok ? `Take @${name} with Adena` : "Type an available name"}</button>
      </div>
    </dialog>
  );
}
