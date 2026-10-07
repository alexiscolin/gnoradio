import { useEffect, useState } from "react";
import { REALMS, qjson } from "../lib/gno";
import { type Infer, bool, num, obj, opt, str } from "../lib/guard";
import { hostOf } from "../lib/format";
import { WELL_KNOWN, proofLine } from "../lib/proof";
import { safeHttps } from "../lib/safe";
import type { Artist } from "../lib/types";
import type { Actions } from "../player/useActions";
import { Help } from "./Help";
import { Icon } from "./Icons";
import { Shape } from "./Shapes";

export const isClaim = obj({ verified: bool, proof: str, pending: bool, to: opt(str), pendingProof: opt(str), readyAt: opt(num), bot: bool });
type Claim = Infer<typeof isClaim>;

const VERIFY_HELP =
  "Tips and paid tickets only reach artists who proved who they are, so nobody can collect money in someone else's name. " +
  "The proof is a short code the artist adds where only they can write: their Audius bio, or a file on their own website. " +
  "A robot reads it, then the request stays public for 72 hours before it counts: if the page was hacked, there is time to stop it. " +
  "GnoRadio never holds the money and takes nothing: a tip reaches the artist in the same transaction.";

/** tippable: tips and paid tickets need a verified artist (catalog/verify.gno). */
export const tippable = (a: Artist | undefined): boolean => a !== undefined && a.owner !== "" && a.verified;

const day = (unix: number) => new Date(unix * 1000).toLocaleString("en", { weekday: "short", month: "short", day: "numeric", hour: "2-digit", minute: "2-digit", hourCycle: "h23" });

export function useClaim(artistID: number, refresh: number): Claim | null {
  const [c, setC] = useState<Claim | null>(null);
  useEffect(() => {
    let alive = true;
    qjson(REALMS.catalog, `ClaimJSON(${String(artistID)})`, isClaim).then((v) => { if (alive) setC(v); }, () => { if (alive) setC(null); });
    return () => { alive = false; };
  }, [artistID, refresh]);
  return c;
}

/** VerifyStatus is the one-line state shown on an artist page. */
export function VerifyStatus({ a, claim, onVerify }: { readonly a: Artist; readonly claim: Claim | null; readonly onVerify: () => void }) {
  if (a.verified) {
    const proof = safeHttps(claim?.proof ?? "");
    return (
      <span className="vstatus ok">
        <Shape g="circle" size={10} fill="var(--blue)" /> Verified artist
        {proof && <> · <a href={proof} target="_blank" rel="noreferrer">via {hostOf(proof)}</a></>}
        <Help text={VERIFY_HELP} />
      </span>
    );
  }
  if (claim?.pending) {
    // Anyone may turn tips on once the 72 h wait is over (catalog.FinalizeClaim): the panel has the button.
    return Date.now() / 1000 >= (claim.readyAt ?? 0)
      ? <span className="vstatus wait"><Shape g="quarter" size={10} /> Verification done · <button className="link" onClick={onVerify}>Turn on tips</button> <Help text={VERIFY_HELP} /></span>
      : <span className="vstatus wait"><Shape g="quarter" size={10} /> Verification in progress · tips open {day(claim.readyAt ?? 0)} <Help text={VERIFY_HELP} /></span>;
  }
  return (
    <span className="vstatus">
      Not verified yet · <button className="link" onClick={onVerify}>Is this you? Verify it (tips open 72 h later)</button>
      <Help text={VERIFY_HELP} />
    </span>
  );
}

interface Check { state: "idle" | "checking" | "notFound" | "error" | "found"; message?: string; page?: string }

/**
 * VerifyPanel walks a non-technical artist through it: copy a code, paste it
 * on your page, press Check. Then, after the safety delay, turn tips on.
 */
export function VerifyPanel({ a, claim, actions, onClose, onChange }: { readonly a: Artist; readonly claim: Claim | null; readonly actions: Actions; readonly onClose: () => void; readonly onChange: () => void }) {
  const ws = actions.wallet.state;
  const wallet = ws.status === "connected" ? ws.address : "";
  const [page, setPage] = useState("");
  const [copied, setCopied] = useState(false);
  const [check, setCheck] = useState<Check>({ state: "idle" });
  const line = wallet ? proofLine(a.id, wallet) : "";
  const now = Date.now() / 1000;
  const where =
    a.kind === "audius" ? "in your Audius bio (Audius › Edit profile › Bio)"
      : a.kind === "curated" && a.source ? `in a file on your site: ${new URL(a.source).origin}${WELL_KNOWN}`
        : `in a file on your own website: yourname.com${WELL_KNOWN}`;
  const needsPage = a.kind === "artist";

  const run = async () => {
    setCheck({ state: "checking" });
    try {
      const r = await fetch("/api/verify", { method: "POST", headers: { "content-type": "application/json" }, body: JSON.stringify({ artist: a.id, wallet, page }) });
      const body = (await r.json()) as { error?: string; page?: string; note?: string; expires?: number; sig?: string };
      if (r.ok && body.sig && body.expires) {
        // The robot signed a certificate; the artist submits it from their own wallet.
        setCheck({ state: "found", page: body.page ?? "" });
        actions.claim(a.id, body.page ?? "", body.expires, body.sig, onChange);
      } else if (r.ok) {
        setCheck({ state: "error", message: body.note ?? "The check failed, try again in a minute." });
      } else if (body.error === "notFound") {
        setCheck({ state: "notFound", page: body.page ?? "" });
      } else {
        setCheck({ state: "error", message: body.error ?? "The check failed, try again in a minute." });
      }
    } catch {
      setCheck({ state: "error", message: "The check failed, try again in a minute." });
    }
  };

  return (
    <section className="panel verify" aria-label={`Verify ${a.name}`}>
      <div className="verify-head">
        <h3><Shape g="circle" size={14} fill="var(--blue)" /> Verify {a.name}</h3>
        <button className="x" onClick={onClose} aria-label="Close"><Icon name="close" /></button>
      </div>
      <p className="muted small">Prove this is you so fans can tip you and buy your paid tickets. No paperwork, no email: a short code on your own page is enough. <Help text={VERIFY_HELP} /></p>

      {claim?.pending && (claim.to === wallet || now >= (claim.readyAt ?? 0)) ? (
        <div className="verify-done">
          <b>{claim.to === wallet ? "Your proof was found." : "The proof was found."} </b>
          {now >= (claim.readyAt ?? 0) ? (
            <>
              <span>The 72-hour safety wait is over.</span>
              <button className="cta" onClick={() => { actions.finalizeClaim(a.id); }}>Turn on tips · one signature</button>
            </>
          ) : (
            <span>Tips open on <b>{day(claim.readyAt ?? 0)}</b>. This 72-hour wait is public, so if someone hacked your page there is time to stop it. You can then remove the code from your page.</span>
          )}
        </div>
      ) : !wallet ? (
        <div className="verify-done">
          <span>First connect the wallet that should receive your tips.</span>
          <button className="cta" onClick={() => void actions.wallet.connectWallet()}>Connect Adena</button>
        </div>
      ) : (
        <ol className="vsteps">
          <li>
            <b>1</b>
            <div>
              <span>Copy your code</span>
              <div className="vcode">
                <code>{line}</code>
                <button className="btn" onClick={() => { void navigator.clipboard.writeText(line).then(() => { setCopied(true); }); }}>{copied ? "Copied" : "Copy"}</button>
              </div>
              <small className="muted">It links this profile to your wallet <span className="mono">{wallet.slice(0, 10)}…</span>. It is not a password: showing it is safe.</small>
            </div>
          </li>
          <li>
            <b>2</b>
            <div>
              <span>Paste it {where}</span>
              {needsPage && (
                <label className="field">Your website<input className="mono" type="url" inputMode="url" value={page} placeholder="https://yourname.com" onChange={(e) => { setPage(e.target.value); }} /></label>
              )}
              {a.kind === "curated" && !a.source && <small className="error">This profile has no page of its own to check. Register your own artist profile instead.</small>}
            </div>
          </li>
          <li>
            <b>3</b>
            <div>
              <span>Let the robot check</span>
              <button className="cta" disabled={check.state === "checking" || (needsPage && !page.trim())} onClick={() => void run()}>{check.state === "checking" ? "Checking…" : "Check my page"}</button>
              {check.state === "notFound" && <p className="error small" role="alert">The code is not on {check.page ? hostOf(check.page) : "your page"} yet. Save your page, wait a minute, then check again.</p>}
              {check.state === "error" && <p className="error small" role="alert">{check.message}</p>}
              {check.state === "found" && <p className="ok small" role="status">Found it. Confirm in your wallet (about 0.05 GNOT of gas): tips then open in 72 hours, a public safety wait.</p>}
            </div>
          </li>
        </ol>
      )}
    </section>
  );
}
