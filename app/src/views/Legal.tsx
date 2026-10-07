import { useState } from "react";
import { Head } from "../components/common";
import { measured, optOut, optedOut } from "../lib/analytics";
import { CONTACT, HOST, MIN_AGE, NOTICE_DELAY, PUBLISHER, REPEAT_INFRINGER, TREASURY_HOLDER } from "../lib/legal";

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
  return (
    <article className="about legal-page">
      <Head a="Legal" b="privacy · terms" note="Who runs GnoRadio, what it does with your data, and the rules of use." />

      <section className="about-sec">
        <h2 className="sub">Legal notice</h2>
        <p>Publisher: {PUBLISHER}.</p>
        <p>Contact: {issue("an issue on GitHub")}. Issues are public: put no personal data in them.</p>
        <p>Host: {HOST}</p>
        <p>GnoRadio is an independent project, not affiliated with or endorsed by Audius, the Open Audio Foundation, Adena or gno.land. Music belongs to its artists; each track shows its licence.</p>
      </section>

      <section className="about-sec">
        <h2 className="sub">Privacy</h2>
        <p>No account, no advertising, no tracking across sites.</p>
        <p>Audience measurement, anonymous: PostHog (EU servers), through GnoRadio's own address. It counts pages seen and what is used (listening, picks, tips, saves, shares), with one first-party cookie kept 13 months at most. It never receives your wallet address, a name or a dedication; text on screen is masked and addresses are cut from every event; your IP address is discarded. It is exempt from consent under the CNIL's audience-measurement rules, and you can object at any time: <StatsChoice /></p>
        <p>On-chain actions (likes, picks, dedications, tips, tickets, reports) are public and permanent on gno.land, tied to your wallet address. GnoRadio can hide them in its pages but cannot erase them from the chain: the right to erasure (GDPR art. 17) is limited by how a public blockchain works. We process them on the basis of legitimate interest, to run the radio you chose to take part in.</p>
        <p>A dedication's text is sent to OpenAI's moderation service before you sign. OpenAI is a US processor and may keep it for up to 30 days; it never receives your address.</p>
        <p>Your browser stores your saves, volume, wallet choice, gnokey key name, dismissed hints, whether you have seen the intro and a copy of the public catalog (to load faster). When quick actions are on, it also stores a session key that signs small actions for you until it expires; turn quick actions off to delete it.</p>
        <p>Playback loads audio and covers from their hosts (Audius, archive.org, IPFS gateways, Arweave) and reads the chain from an RPC node: they see your IP address, as any website you visit does. Netlify, our host, keeps standard access logs.</p>
        <p>Questions or requests: {issue("a GitHub issue")}.</p>
      </section>

      <section className="about-sec">
        <h2 className="sub">Terms</h2>
        <p>GnoRadio is provided as is, without warranty. You must be {MIN_AGE} or older to use its on-chain features.</p>
        <p>A transaction you sign is final. Tips and ticket prices go to the artist in the same transaction; GnoRadio cannot refund them. Support and service fees go to the treasury, held by {TREASURY_HOLDER}.</p>
        <p>Listeners and artists alone are responsible for what they publish: tracks, covers, names, bios, playlists, dedications, concert listings. GnoRadio is a hosting service for that content: it does not review it before it appears (apart from the automatic screening of dedications) and is not liable for it, except where, once told about illegal content, it does not act promptly to hide it (EU Digital Services Act art. 6, French LCEN art. 6). Hate, harassment, threats and any illegal content are forbidden.</p>
        <p>Publish only music you own or control the rights to, or hold a licence for. Publishing grants the licence stated in the rights declaration you accept.</p>
        <p>Copyright or illegal content? Open {issue("a GitHub issue")}, or report it on-chain from its page, with: the link, why it is illegal or which right it infringes, your name and a way to reach you, and a statement that you believe this in good faith. We hide reported content while we check, usually within {NOTICE_DELAY}, and tell the uploader why. {REPEAT_INFRINGER}.</p>
        <p>The moderator may hide content and dedications that break these terms or the law.</p>
      </section>
    </article>
  );
}
