import { type ReactNode, useRef } from "react";
import { ShareButton, jumpTo } from "../components/common";
import { Icon } from "../components/Icons";
import { Composition, Shape } from "../components/Shapes";
import { track } from "../lib/analytics";
import { CANNOT, EXAMPLE, type Go, HERO, IMPORTED, PHONE_SIGN, SHARE_TEXT, TRUST, VIDEO, audiences, hrefOf, moneyRows } from "../lib/features";
import { licenseURL, licenseLabel } from "../lib/format";
import { realmPage } from "../lib/links";
import { CHAIN_ID, hasAdena, isPhone, networkLabel } from "../lib/gno";
import { useFees } from "../lib/fees";
import { INDEPENDENT } from "../lib/legal";
import { viewToPath } from "../lib/router";
import type { Catalog, Navigate, SupportInfo, View } from "../lib/types";
import { liveFacts } from "./About";
import { FEATURES_NAME } from "../lib/seo";

const out = { target: "_blank", rel: "noreferrer" } as const;
type At = "hero" | "start" | "card" | "more" | "end";
const toOf = (go: Go): string => ("pick" in go ? "pick" : "href" in go ? "gnoweb" : go.view.k);
const TUNE_IN: View = { k: "stations", live: 0 };
const MAKE_MUSIC: View = { k: "contribute", path: "artist" };

/** FeatLink is a feature's way in: a real, crawlable link, followed inside the app; a gnoweb one opens a new tab. */
function FeatLink({ to, at, className, follow, children }: { readonly to: Go; readonly at: At; readonly className: string; readonly follow: (to: Go, at: At) => void; readonly children: ReactNode }) {
  const ext = "href" in to;
  return (
    <a className={className} href={hrefOf(to, (v) => viewToPath(v))} {...(ext ? out : {})} onClick={(e) => { if (!ext) e.preventDefault(); follow(to, at); }}>
      {children} <Icon name={ext ? "external" : "arrow-right"} size={14} className={ext ? "nudge-out" : "nudge"} />
    </a>
  );
}

/** Features is the "Get started" landing page: every feature, for listeners and for artists, each with the way to it. */
export function Features({ cat, support, go, openPick, me }: { readonly cat: Catalog; readonly support: SupportInfo; readonly go: Navigate; readonly openPick: (station: number) => void; readonly me: string }) {
  const fees = useFees();
  const net = networkLabel(CHAIN_ID);
  const follow = (to: Go, at: At) => {
    track("cta", { page: "features", at, to: toOf(to) });
    if ("pick" in to) { openPick(0); return; }
    if ("href" in to) return;
    go(to.view);
    const hash = to.hash;
    if (hash) window.setTimeout(() => { jumpTo(hash); }, 120);
  };
  const half = useRef(false);
  const facts = liveFacts(cat, support).slice(0, 3);
  const ctas = (at: At, extra?: ReactNode) => (
    <div className="feat-ctas">
      <button className="cta red" onClick={() => { follow({ view: TUNE_IN }, at); }}>Tune in <Icon name="arrow-right" size={16} className="nudge" /></button>
      <button className="cta" onClick={() => { follow({ view: MAKE_MUSIC }, at); }}>Make music <Icon name="arrow-right" size={16} className="nudge" /></button>
      {extra}
    </div>
  );
  return (
    <article className="about feat">
      <header className="feat-hero">
        <div className="feat-hero-txt">
          <span className="lbl">{HERO.kicker}</span>
          <h1>{HERO.title}</h1>
          <p className="about-lead">{HERO.lead}</p>
          {ctas("hero", <ShareButton title={FEATURES_NAME} to={{ k: "features" }} refBy={me} text={SHARE_TEXT} />)}
        </div>
        <div className="feat-hero-art"><Composition variant={0} /></div>
      </header>

      <figure className="feat-video">
        <video
          controls preload="none" playsInline poster={VIDEO.poster} src={VIDEO.src} aria-label={VIDEO.caption}
          onPlay={() => { track("video", { state: "play" }); }}
          onTimeUpdate={(e) => { const v = e.currentTarget; if (!half.current && v.currentTime >= v.duration / 2) { half.current = true; track("video", { state: "half" }); } }}
          onEnded={() => { track("video", { state: "end" }); }}
        />
        <figcaption>
          <span>{VIDEO.caption}</span>
          <span className="muted small">
            Music: “{VIDEO.music.title}” by <a href={VIDEO.music.site} {...out}>{VIDEO.music.artist}</a>, edited, licensed under <a href={licenseURL(VIDEO.music.license)} {...out}>{licenseLabel(VIDEO.music.license)}</a>.
          </span>
        </figcaption>
      </figure>

      {facts.length > 0 && (
        <ul className="about-facts" aria-label="On GnoRadio now">
          {facts.map(([n, label]) => <li key={label}><b>{n}</b><span>{label}</span></li>)}
        </ul>
      )}

      <section className="about-sec feat-final" aria-label="Get started">
        <button className="bethedj" onClick={() => { follow({ pick: true }, "start"); }}>
          <Icon name="on-air" size={48} className="bethedj-icon" />
          <span className="bethedj-txt"><b>Be the DJ</b><span>{isPhone() && !hasAdena() ? PHONE_SIGN : "Pick a track: it plays for everyone tuned in."}</span></span>
          <span className="bethedj-go">Pick a track <Icon name="arrow-right" size={16} className="nudge" /></span>
        </button>
        <button className="block-yellow feat-make" onClick={() => { follow({ view: MAKE_MUSIC }, "start"); }}>
          <Shape g="triangle" size={40} />
          <span className="big">Make music</span>
          <span className="small">Create your profile and publish. GnoRadio takes nothing from your tips.</span>
          <span className="go">Start <Icon name="arrow-right" size={16} className="nudge" /></span>
        </button>
      </section>

      {audiences(fees.ticketFee).map((a) => (
        <section key={a.id} className="about-sec" id={a.id}>
          <h2 className="feat-h2">{a.title} <span>{a.lead}</span></h2>
          <ol className="about-steps feat-grid">
            {a.cards.map((f, i) => (
              <li key={f.title}>
                <div className="about-step-top"><span className="about-n">{String(i + 1).padStart(2, "0")}</span><Shape g={f.g} size={26} /></div>
                <h3>{f.title}</h3>
                <p>{f.line}</p>
                <FeatLink to={f.go} at="card" className="feat-go" follow={follow}>{f.cta}</FeatLink>
              </li>
            ))}
          </ol>
          <details className="feat-more-box">
            <summary className="sub feat-more-h">{a.more.length} more for {a.id} <Icon name="arrow-right" size={14} className="nudge" /></summary>
            <ul className="feat-more">
              {a.more.map((m) => (
                <li key={m.title}>
                  <FeatLink to={m.go} at="more" className="feat-more-a" follow={follow}>
                    <h3>{m.title}</h3>
                    <span className="muted small">{m.line}</span>
                  </FeatLink>
                </li>
              ))}
            </ul>
          </details>
        </section>
      ))}

      <section className="about-sec">
        <h2 className="feat-h2">Where every GNOT goes</h2>
        <p className="feat-example">{EXAMPLE}</p>
        <div className="about-table">
          {moneyRows(fees).map(([what, where, note]) => (
            <div key={what}><span>{what}</span><b>{where}</b><span className="muted small">{note}</span></div>
          ))}
        </div>
      </section>

      <section className="about-sec">
        <h2 className="feat-h2">Check it, don't trust it</h2>
        <div className="about-powers">
          <div>
            {TRUST.map(([title, text]) => <div key={title}><h3>{title}</h3><p className="muted">{text}</p></div>)}
            <p className="proof">
              <button className="link small" onClick={() => { go({ k: "about" }); }}>How it works, in detail</button>
              <span aria-hidden="true"> · </span>
              <a href={realmPage("home")} {...out}>GnoRadio rendered by gno.land <Icon name="external" size={12} className="nudge-out" /></a>
            </p>
          </div>
          <div className="cannot">
            <span className="tag blue">Nobody can</span>
            <p>{CANNOT}</p>
          </div>
        </div>
      </section>

      <section className="about-sec feat-end" aria-label="Start now">
        {ctas("end")}
        <FeatLink to={{ view: { k: "contribute", path: "claim" } }} at="end" className="feat-go" follow={follow}>{IMPORTED}</FeatLink>
      </section>

      <footer className="about-credit">
        <span>{INDEPENDENT}{net ? ` ${net}: test GNOT, no real value.` : ""}</span>
      </footer>
    </article>
  );
}
