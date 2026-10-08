// The /features page as static HTML, written at build time (vite.config.ts) to
// dist/features/index.html: crawlers that run no script read the same copy the
// app shows (features.ts), with the page's own title, canonical and JSON-LD.
// main.tsx removes it before React takes over the splash. Live counts are left out.
import { NO_FEES } from "./fees";
import { AUDIENCES, CANNOT, EXAMPLE, HERO, moneyRows, TRUST, VIDEO, hrefOf } from "./features";
import { esc, licenseLabel, licenseURL } from "./format";
import { INDEPENDENT } from "./legal";
import { viewToPath } from "./router";
import { FEATURES_META } from "./seo";

const a = (href: string, text: string): string => `<a href="${esc(href)}">${esc(text)}</a>`;

/** UPLOADED is the promo video's publication date, for its VideoObject. */
const UPLOADED = "2026-10-08";

/** featuresBody is the page's text as semantic HTML: one h1, an h2 per section, an h3 per feature. */
export function featuresBody(): string {
  const link = (go: Parameters<typeof hrefOf>[0], text: string) => a(hrefOf(go, (v) => viewToPath(v)), text);
  const sections = AUDIENCES.map((au) => `<section id="${au.id}"><h2>${esc(au.title)}: ${esc(au.lead)}</h2>${
    au.cards.map((f) => `<h3>${esc(f.title)}</h3><p>${esc(f.line)} ${link(f.go, f.cta)}</p>`).join("")
  }<ul>${au.more.map((m) => `<li><h3>${esc(m.title)}</h3><p>${esc(m.line)} ${link(m.go, m.title)}</p></li>`).join("")}</ul></section>`).join("");
  return `<main class="seo-static"><h1>${esc(HERO.title)}</h1><p>${esc(HERO.lead)}</p>`
    + `<p>${a("/live", "Tune in")} · ${a("/contribute/artist", "Make music")}</p>`
    + `<figure><video controls preload="none" poster="${VIDEO.poster}" src="${VIDEO.src}" aria-label="${esc(VIDEO.caption)}"></video><figcaption>${esc(VIDEO.caption)} Music: “${esc(VIDEO.music.title)}” by ${a(VIDEO.music.site, VIDEO.music.artist)}, edited, licensed under ${a(licenseURL(VIDEO.music.license), licenseLabel(VIDEO.music.license))}.</figcaption></figure>`
    + sections
    + `<section><h2>Where every GNOT goes</h2><p>${esc(EXAMPLE)}</p><dl>${moneyRows(NO_FEES).map(([w, to, note]) => `<dt>${esc(w)}: ${esc(to)}</dt><dd>${esc(note)}</dd>`).join("")}</dl></section>`
    + `<section><h2>Check it, don't trust it</h2>${TRUST.map(([t, x]) => `<h3>${esc(t)}</h3><p>${esc(x)}</p>`).join("")}<h3>Nobody can</h3><p>${esc(CANNOT)}</p><p>${a("/about", "How it works, in detail")}</p></section>`
    + `<footer><p>${esc(INDEPENDENT)}</p></footer></main>`;
}

/** featuresPage turns the built index.html into /features: its own head, and the body text before the app takes over. */
export function featuresPage(index: string, site: string): string {
  const url = `${site}/features`;
  const ld = [
    { "@context": "https://schema.org", "@type": "WebPage", name: FEATURES_META.title, description: FEATURES_META.description, url },
    {
      "@context": "https://schema.org", "@type": "VideoObject", name: "GnoRadio in a minute", description: VIDEO.caption,
      thumbnailUrl: `${site}${VIDEO.poster}`, contentUrl: `${site}${VIDEO.src}`, duration: `PT${String(VIDEO.seconds)}S`, uploadDate: UPLOADED,
    },
    // Listening is free (no wallet, no account): the app's offer is 0.
    { "@context": "https://schema.org", "@type": "WebApplication", name: "GnoRadio", url: site, applicationCategory: "MultimediaApplication", operatingSystem: "Web", offers: { "@type": "Offer", price: "0", priceCurrency: "USD" } },
  ];
  const tag = (attr: string, names: string, content: string) => (html: string) =>
    html.replace(new RegExp(`(<meta ${attr}="(?:${names})" content=")[^"]*"`, "g"), (_m, p: string) => `${p}${esc(content)}"`);
  const steps = [
    tag("name", "description", FEATURES_META.description),
    tag("property", "og:title", FEATURES_META.title),
    tag("property", "og:description", FEATURES_META.description),
    tag("property", "og:url", url),
    tag("name", "twitter:title", FEATURES_META.title),
    tag("name", "twitter:description", FEATURES_META.description),
  ];
  const head = `<link rel="canonical" href="${url}" />`
    + `<meta property="og:video" content="${site}${VIDEO.src}" /><meta property="og:video:type" content="video/mp4" />`
    + `<script type="application/ld+json">${JSON.stringify(ld).replace(/</g, "\\u003c")}</script>`;
  return steps.reduce((h, f) => f(h), index)
    .replace(/<title>[^<]*<\/title>/, () => `<title>${esc(FEATURES_META.title)}</title>`)
    .replace("</head>", () => `${head}</head>`)
    .replace('<div id="root">', () => `<div id="root">${featuresBody()}`);
}
