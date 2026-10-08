import { Icon } from "../components/Icons";
import { type Glyph, Shape } from "../components/Shapes";
import { gnot, shortAddr } from "../lib/format";
import { CHAIN_ID } from "../lib/gno";
import { CANNOT, PICK_WINDOW, REPORTS, TIP_LINE, moneyRows } from "../lib/features";
import { useFees } from "../lib/fees";
import { CONTACT, INDEPENDENT, NO_PERSONAL_DATA, NOTICE_DELAY, REPO } from "../lib/legal";
import { realmPage, sourceURL } from "../lib/links";
import type { Catalog, Navigate, SupportInfo } from "../lib/types";
import { FEATURES_NAME } from "../lib/seo";

const out = { target: "_blank", rel: "noreferrer" } as const;

const STEPS: readonly { readonly g: Glyph; readonly title: string; readonly text: string }[] = [
  { g: "circle", title: "You listen", text: "Play any album or playlist, or tune into a live station. Everyone hears the same second, read from the chain. No wallet, no transaction." },
  { g: "quarter", title: "Listeners program the radio", text: `Pick a track and it airs for everyone, next or at a time you choose, ${PICK_WINDOW}. The schedule is a public realm: nobody edits it in secret.` },
  { g: "square", title: "You support artists in one transaction", text: TIP_LINE },
  { g: "triangle", title: "Artists publish in one transaction", text: "A published track joins its genre station (which Main relays in its hours) and New in the artist's own transaction: no one has to approve or schedule it." },
];

const VERIFY_STEPS: readonly { readonly g: Glyph; readonly title: string; readonly text: string }[] = [
  { g: "square", title: "A code on your own page", text: "The artist adds a short code to their Audius bio or to a file on their own website (/.well-known/gnoradio.txt): places only they control." },
  { g: "circle", title: "A robot checks it", text: "No email, no paperwork. The robot reads the page and the request is recorded publicly on gno.land. The moderator can also give a profile to the artist who proved it, which verifies it: imported curated profiles are verified only that way." },
  { g: "quarter", title: "72 hours, then tips open", text: "The request stays public for 72 hours, time to stop it if a page was hacked. Then the profile is verified and fans can tip it." },
];

// What gnoweb shows of GnoRadio, to check it runs as it says.
const VERIFY = [
  ["Every record, and who may write it", "data", "data.gno"],
  ["Promo budgets: who funds, who withdraws", "data", "vault.gno"],
  ["Tips, likes and follows", "catalog", "social.gno"],
  ["How artists are verified", "catalog", "verify.gno"],
  ["Refunded picks", "catalog", "sponsor.gno"],
  ["Where GnoRadio's support goes", "catalog", "support.gno"],
  ["Who may hide what", "catalog", "moderation.gno"],
  ["Publishing to the stations", "radio", "publish.gno"],
  ["Picks and the queue", "radio", "queue.gno"],
  ["Concert tickets", "tickets", "tickets.gno"],
  ["The tickets as NFTs", "nft", "nft.gno"],
  ["The site as text", "home", "home.gno"],
] as const;

// The admin's powers, as the realms define them (catalog artists, moderation, verify, support; radio admin, notes, queue, publish; tickets; home app).
const CAN = [
  "Import curated and Audius tracks (through the radio, so they join their stations); create curated profiles and assign one to the artist who proved it (verified by the moderator), or free a reserved name; verify or un-verify an artist, cancel a pending verification or undo a wrong one; name the verification robot; allow an audio host.",
  "Hide or restore tracks, albums, artists, playlists and concerts, with a public reason; resolve reports; restore a dedication hidden by mistake or lift a dedication pause; name the dedication robot.",
  "Remove a track from a station's rotation or put it back, take a pick off the queue, add a curator pick; set the monthly goal, the treasury address and the ticket service fee (10 GNOT at most).",
  "Set the app's link and the contact line on gnoweb, and pass the admin role on (offered, then accepted) or give it up.",
];

// The owner of the data realm (data.gno) and its guardian, apart from the admin.
const UPGRADE = "Every record lives in one permanent data realm. Its owner can propose new rules realms, which take over only 72 hours after they are all on chain, and can pause writes. A separate guardian can only pause and cancel a pending release; the owner can replace the guardian only 144 hours after announcing it. Neither can edit a record or touch a promo budget. A funder can withdraw a budget even while GnoRadio is paused, and a pause pushes back every refund still to collect by its length.";


/** liveFacts: what GnoRadio holds now, as number and label pairs; a zero says nothing, so it is left out. */
export function liveFacts(cat: Catalog, support: SupportInfo): readonly (readonly [string, string])[] {
  const count = (n: number, word: string) => [n, String(n), n === 1 ? word : `${word}s`] as const;
  return [
    count(cat.tracks.length, "track"),
    count(cat.artists.size, "artist"),
    count(cat.stations.filter((s) => s.tracks > 0).length, "live station"),
    count(cat.playlists.length, "playlist"),
    [support.total, gnot(support.total), "given to support the project"] as const,
  ].filter(([n]) => n > 0).map(([, shown, label]) => [shown, label] as const);
}

/** About: how GnoRadio works, where the money goes, and how to check it. */
export function About({ cat, support, go }: { readonly cat: Catalog; readonly support: SupportInfo; readonly go: Navigate }) {
  const facts = liveFacts(cat, support);
  const fees = useFees();
  const links = [
    ["GnoRadio on gnoweb", realmPage("home"), "The same radio, rendered by the chain"],
    ["gno.land", "https://gno.land", "The chain it runs on"],
    ["Adena", "https://adena.app", "The wallet that signs your picks and tips"],
    ["Source code", REPO, "Realms, app and curation tools on GitHub"],
  ] as const;

  return (
    <article className="about">
      <header className="about-hero">
        <span className="lbl">About · {CHAIN_ID === "dev" ? "local devnet" : CHAIN_ID}</span>
        <h1>Gno<br />Radio<i className="dot" /></h1>
        <p className="about-lead">A community radio and open music player whose rules live on <b>gno.land</b>. Listening is free and never touches the chain; what pays, proves or commits is a public transaction.</p>
      </header>

      <ol className="about-steps">
        {STEPS.map((s, i) => (
          <li key={s.title}>
            <div className="about-step-top">
              <span className="about-n">{String(i + 1).padStart(2, "0")}</span>
              <Shape g={s.g} size={28} />
            </div>
            <b>{s.title}</b>
            <p>{s.text}</p>
          </li>
        ))}
      </ol>

      <ul className="about-facts" aria-label="On GnoRadio now">
        {facts.map(([n, label]) => <li key={label}><b>{n}</b><span>{label}</span></li>)}
        <li className="about-more">
          <button onClick={() => { go({ k: "features" }); }}>{FEATURES_NAME} <Icon name="arrow-right" size={16} className="nudge" /></button>
        </li>
      </ul>

      <section className="about-sec">
        <h2 className="sub">Where the money goes</h2>
        <div className="about-table">
          {moneyRows(fees).map(([what, where, note]) => (
            <div key={what}>
              <span>{what}</span>
              <b>{where}</b>
              <span className="muted small">{note}</span>
            </div>
          ))}
          {support.treasury && <p className="muted small">Treasury: <span className="mono">{shortAddr(support.treasury)}</span></p>}
        </div>
      </section>

      <section className="about-sec" id="verified">
        <h2 className="sub">Verified artists</h2>
        <ol className="about-steps compact">
          {VERIFY_STEPS.map((v, i) => (
            <li key={v.title}>
              <div className="about-step-top"><span className="about-n">{String(i + 1).padStart(2, "0")}</span><Shape g={v.g} size={22} /></div>
              <b>{v.title}</b>
              <p>{v.text}</p>
            </li>
          ))}
        </ol>
        <p className="muted small">Why it is safe: GnoRadio never holds money, a tip goes straight to the artist in the same transaction. The robot can only propose a verification; it cannot move funds or change settings, and the admin can cancel one during the wait or revoke the robot key at once. A ✓ shows the host the proof was found on, or says it was verified by the GnoRadio moderator. Artist? <button className="link" onClick={() => { go({ k: "contribute", path: "claim" }); }}>Verify your profile</button>.</p>
      </section>

      <section className="about-sec">
        <h2 className="sub">Who can change what</h2>
        <div className="about-powers">
          <div>
            <span className="tag">The admin can</span>
            <ul>{CAN.map((c) => <li key={c}>{c}</li>)}</ul>
          </div>
          <div className="cannot">
            <span className="tag blue">Nobody can</span>
            <p>{CANNOT}</p>
            <p className="muted small">{UPGRADE}</p>
            <p className="muted small">Admin today: <span className="mono">{cat.admin ? shortAddr(cat.admin) : "unknown"}</span>, a personal wallet, visible on-chain.</p>
          </div>
        </div>
      </section>

      <section className="about-sec">
        <h2 className="sub">Verify it yourself</h2>
        <p className="muted">gnoweb renders every GnoRadio page straight from the chain: <a href={realmPage("home")} {...out}>GnoRadio on gno.land <Icon name="external" size={12} className="nudge-out" /></a>. The code that runs it:</p>
        <ul className="about-rows">
          {VERIFY.map(([name, realm, file]) => (
            <li key={name}>
              <a href={sourceURL(realm, file)} {...out}>
                <span>{name}</span>
                <span className="mono muted small">{realm}/{file}</span>
                <Icon name="external" size={16} className="nudge-out" />
              </a>
            </li>
          ))}
        </ul>
      </section>

      <section className="about-sec">
        <h2 className="sub">Go further</h2>
        <ul className="about-links">
          {links.map(([name, href, what]) => (
            <li key={name}>
              <a href={href} {...out}>
                <b>{name} <Icon name="external" size={14} className="nudge-out" /></b>
                <span className="muted small">{what}</span>
              </a>
            </li>
          ))}
        </ul>
      </section>

      <section className="about-sec legal">
        <h2 className="sub">Legal</h2>
        <p className="muted small">
          {INDEPENDENT}
          Music belongs to its artists and is streamed under the Audius Open Music License or the licence shown on each track.
          On-chain actions (likes, tips, picks, dedications, tickets, reports) are public and permanent; what your browser keeps and who sees what is in the <button className="link" onClick={() => { go({ k: "legal" }); }}>privacy notice</button>.
          Dedications are screened before they go on air: a word list on-chain, then an automated moderation service (OpenAI receives the dedication text only, never your address).
          A dedication on air can be reported by listeners with some pick history, the same as for a free pick: a first pick at least 7 days old and 3 normal picks in the last two 15-day periods. Three reports hide it; a second hidden dedication within a week pauses its author's dedications for a week.
          {REPORTS}
        </p>
        <p className="muted small">
          Copyright or illegal content? Open an <a href={CONTACT} {...out}>issue on GitHub</a> (public questions), or report it on-chain from its page, with: the link, why it is illegal or which right it infringes, and a statement that you believe this in good faith. We hide reported content while we check, usually within {NOTICE_DELAY}, and tell the uploader why. {NO_PERSONAL_DATA}
        </p>
        <p className="muted small">
          Accessibility: GnoRadio is built to work with a keyboard and a screen reader, but it has not been audited. Tell us what gets in your way in a <a href={CONTACT} {...out}>GitHub issue</a>.
        </p>
        <p className="muted small">
          <button className="link" onClick={() => { go({ k: "legal" }); }}>Legal notice, privacy and terms</button> · <a href={`${REPO}/blob/main/NOTICE`} {...out}>Third-party notices</a>
        </p>
      </section>

      <footer className="about-credit">
        <svg viewBox="0 0 16 16" width="18" height="18" aria-hidden="true"><path fill="currentColor" d="M8 0C3.58 0 0 3.58 0 8c0 3.54 2.29 6.53 5.47 7.59.4.07.55-.17.55-.38 0-.19-.01-.82-.01-1.49-2.01.37-2.53-.49-2.69-.94-.09-.23-.48-.94-.82-1.13-.28-.15-.68-.52-.01-.53.63-.01 1.08.58 1.23.82.72 1.21 1.87.87 2.33.66.07-.52.28-.87.51-1.07-1.78-.2-3.64-.89-3.64-3.95 0-.87.31-1.59.82-2.15-.08-.2-.36-1.02.08-2.12 0 0 .67-.21 2.2.82.64-.18 1.32-.27 2-.27.68 0 1.36.09 2 .27 1.53-1.04 2.2-.82 2.2-.82.44 1.1.16 1.92.08 2.12.51.56.82 1.27.82 2.15 0 3.07-1.87 3.75-3.65 3.95.29.25.54.73.54 1.48 0 1.07-.01 1.93-.01 2.2 0 .21.15.46.55.38A8.013 8.013 0 0016 8c0-4.42-3.58-8-8-8z" /></svg>
        <span>Made by <a href="https://github.com/alexiscolin" {...out}><b>alexiscolin</b></a> · source <a href={REPO} {...out}>GitHub <Icon name="external" size={12} /></a></span>
      </footer>
    </article>
  );
}
