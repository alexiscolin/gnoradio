import { useState } from "react";
import { Head } from "../components/common";
import { measured, optOut, optedOut } from "../lib/analytics";
import { REFUND } from "../lib/concerts";
import { CHAIN_ID } from "../lib/gno";
import { REF_DAYS } from "../lib/incentives";
import { DAYS } from "../lib/session";
import { CONTACT, HOST, INDEPENDENT, MIN_AGE, NO_PERSONAL_DATA, NOTICE_DELAY, PUBLISHER, REPEAT_INFRINGER, TERMS_DATE, TREASURY_HOLDER, NO_FEE } from "../lib/legal";
import { useFees } from "../lib/fees";

/** StatsChoice is the one-click objection to the audience measurement. */
function StatsChoice() {
  const [off, setOff] = useState(optedOut);
  if (!measured()) return <>this build measures nothing.</>;
  return off ? <>you objected; nothing is measured in this browser.</> : <button className="link" onClick={() => { optOut(); setOff(true); }}>don't measure my visits</button>;
}

// Contact goes through the repository's issues: public, so no private data in them.
const issue = (label: string) => <a href={CONTACT} target="_blank" rel="noreferrer">{label}</a>;

/** Legal: legal notice, privacy and terms, on one page. */
export function Legal() {
  const fees = useFees();
  return (
    <article className="about legal-page">
      <Head a="Legal" b="privacy · terms" note="Who runs GnoRadio, what it does with your data, and the rules of use." />

      <section className="about-sec">
        <h2 className="sub">Legal notice</h2>
        <p>Publisher: {PUBLISHER}.</p>
        <p>Contact: {issue("an issue on GitHub")}, for public questions. {NO_PERSONAL_DATA}</p>
        <p>Host: {HOST}</p>
        <p>{INDEPENDENT} Music belongs to its artists; each track shows its licence.</p>
      </section>

      <section className="about-sec">
        <h2 className="sub">Privacy</h2>
        <p>No account, no advertising, no tracking across sites. What is processed, why, and for how long:</p>
        <ul className="legal-list">
          <li><b>Chain records</b> (likes, picks, dedications, tips, tickets, reports, playlists, profiles), tied to your wallet address: to run the service you take part in (contract, GDPR art. 6(1)(b)). Permanent on gno.land: GnoRadio can hide them in its pages on request where possible, but cannot erase them from the chain.</li>
          <li><b>Dedication moderation</b>: before you sign, a dedication's text alone is sent to OpenAI's moderation service, never your address (legitimate interest: keep the air safe). OpenAI is in the US: the transfer relies on the provider's safeguards; it may keep the text up to 30 days.</li>
          <li><b>Audience measurement</b>: PostHog, EU servers, through GnoRadio's own address (legitimate interest, exempt from consent under the CNIL's audience-measurement rules). It counts pages seen and what is used (listening, picks, tips, saves, shares), with one first-party cookie kept 13 months at most; events are kept 25 months at most and never combined with other data. It never receives your wallet address, a name or a dedication; text on screen is masked, addresses are cut from every event and your IP address is discarded. You can object at any time: <StatsChoice /></li>
          <li><b>Host logs</b>: Netlify keeps standard access logs (legitimate interest: security), for Netlify's own retention period.</li>
        </ul>
        <p>Recipients: Netlify (host, US), PostHog (measurement, EU), OpenAI (dedication moderation, US), the RPC node that serves the chain, and the audio and cover hosts (Audius, Jamendo, archive.org, IPFS gateways, Arweave), which see your IP address as any website you visit does.</p>
        <p>Tracks from Audius and Jamendo are read live through their APIs: GnoRadio keeps only a pointer on the chain (the platform's track id, genre, duration and licence), never their titles, names or covers, which stay in your browser's memory for the session. Their terms apply: Audius's <a href="https://audius.co/documents/ApiTerms.pdf" target="_blank" rel="noreferrer">API Terms</a> and <a href="https://audius.co/documents/PrivacyPolicy.pdf" target="_blank" rel="noreferrer">Privacy Policy</a>, Jamendo's <a href="https://devportal.jamendo.com/api_terms_of_use" target="_blank" rel="noreferrer">API terms</a>.</p>
        <p>Mutes and strikes on dedications, and moderation records, are public and permanent on the chain.</p>
        <p>Your browser stores your saves, volume, wallet choice, gnokey key name, dismissed hints, whether you have seen the intro, a copy of the public catalog (to load faster) and, for {REF_DAYS} days, the address of whoever shared the link that brought you (so a tip you make shares the artist's promo share with them, shown before you sign). When quick actions are on, it also stores a session key that signs for you until it expires ({DAYS} days); turn quick actions off to delete it.</p>
        <p>Your rights: access, rectification, erasure (limited on the chain, see above), restriction, objection and portability. Ask through {issue("a GitHub issue")}, without personal data in it. You can also complain to the CNIL (<a href="https://www.cnil.fr" target="_blank" rel="noreferrer">cnil.fr</a>).</p>
      </section>

      <section className="about-sec">
        <h2 className="sub">Terms</h2>
        <p className="muted small">Version of {TERMS_DATE}.</p>
        <p>GnoRadio is provided as is, to the extent permitted by law; nothing limits liability for gross negligence, intentional fault or bodily harm. You must be {MIN_AGE} or older to use its on-chain features. French law applies.</p>
        <p>{CHAIN_ID === "gnoland-1" ? "GNOT on gno.land mainnet has real value: check every amount before you sign." : "Testnet GNOT has no monetary value."} GnoRadio is not a financial or payment service. You are responsible for your wallet and keys.</p>
        <p>A transaction you sign is final. Tips and ticket prices go to the artist in the same transaction; GnoRadio cannot refund them. {fees ? <>Support and service fees go to the treasury, held by {TREASURY_HOLDER}.</> : NO_FEE}</p>
        <p>{REFUND}</p>
        <p>Listeners and artists alone are responsible for what they publish: tracks, covers, names, bios, playlists, dedications, concert listings. GnoRadio is a hosting service for that content: it does not review it before it appears (apart from the automatic screening of dedications) and is not liable for it, except where, once told about illegal content, it does not act promptly to hide it (EU Digital Services Act art. 6, French LCEN art. 6). Forbidden: hate, harassment, threats, sexual content involving minors, terrorist content, doxxing (publishing someone's private details) and any illegal content.</p>
        <p>Publish only music you own or control the rights to, or hold a licence for. Publishing grants the licence stated in the rights declaration you accept.</p>
        <p>Copyright or illegal content? Open {issue("a GitHub issue")}, or report it on-chain from its page, with: the link, why it is illegal or which right it infringes, and a statement that you believe this in good faith. {NO_PERSONAL_DATA} We hide reported content while we check, usually within {NOTICE_DELAY}, and tell the uploader why. {REPEAT_INFRINGER}. A removal order from an authority for terrorist content is handled within 1 hour (EU Regulation 2021/784).</p>
        <p>The moderator may hide content and dedications that break these terms or the law.</p>
      </section>
    </article>
  );
}
