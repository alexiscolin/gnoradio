import { Head } from "../components/common";
import { ABUSE_EMAIL, CONTACT_EMAIL, DIRECTOR, HOST, MIN_AGE, NOTICE_DELAY, PUBLISHER, REPEAT_INFRINGER, TREASURY_HOLDER } from "../lib/legal";

const mail = (to: string) => <a href={`mailto:${to}`}>{to}</a>;

/** Legal: legal notice, privacy and terms, on one page. */
export function Legal() {
  return (
    <article className="about legal-page">
      <Head a="Legal" b="privacy · terms" note="Who runs GnoRadio, what it does with your data, and the rules of use." />

      <section className="about-sec">
        <h2 className="sub">Legal notice</h2>
        <p>Publisher: {PUBLISHER}</p>
        <p>Publication director: {DIRECTOR}</p>
        <p>Contact: {mail(CONTACT_EMAIL)}</p>
        <p>Host: {HOST}</p>
        <p>GnoRadio is an independent project, not affiliated with or endorsed by Audius, the Open Audio Foundation, Adena or gno.land. Music belongs to its artists; each track shows its licence.</p>
      </section>

      <section className="about-sec">
        <h2 className="sub">Privacy</h2>
        <p>No account, no tracking, no analytics, no advertising cookies.</p>
        <p>On-chain actions (likes, picks, dedications, tips, tickets, reports) are public and permanent on gno.land, tied to your wallet address. GnoRadio can hide them in its pages but cannot erase them from the chain: the right to erasure (GDPR art. 17) is limited by how a public blockchain works. We process them on the basis of legitimate interest, to run the radio you chose to take part in.</p>
        <p>A dedication's text is sent to OpenAI's moderation service before you sign. OpenAI is a US processor and may keep it for up to 30 days; it never receives your address.</p>
        <p>Your browser stores your saves, volume, wallet choice, gnokey key name, dismissed hints, whether you have seen the intro and a copy of the public catalog (to load faster). When quick actions are on, it also stores a session key that signs small actions for you until it expires; turn quick actions off to delete it.</p>
        <p>Playback loads audio and covers from their hosts (Audius, archive.org, IPFS gateways, Arweave) and reads the chain from an RPC node: they see your IP address, as any website you visit does. Netlify, our host, keeps standard access logs.</p>
        <p>Questions or requests: {mail(CONTACT_EMAIL)}.</p>
      </section>

      <section className="about-sec">
        <h2 className="sub">Terms</h2>
        <p>GnoRadio is provided as is, without warranty. You must be {MIN_AGE} or older to use its on-chain features.</p>
        <p>A transaction you sign is final. Tips and ticket prices go to the artist in the same transaction; GnoRadio cannot refund them. Support and service fees go to the treasury, held by {TREASURY_HOLDER}.</p>
        <p>Publish only music you own or control the rights to, or hold a licence for. Publishing grants the licence stated in the rights declaration you accept.</p>
        <p>Copyright or illegal content? Email {mail(ABUSE_EMAIL)} with: the link, why it is illegal or which right it infringes, your name and email, and a statement that you believe this in good faith. We hide reported content while we check, usually within {NOTICE_DELAY}, and tell the uploader why. {REPEAT_INFRINGER}.</p>
        <p>The moderator may hide content and dedications that break these terms or the law.</p>
      </section>
    </article>
  );
}
