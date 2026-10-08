import { describe, expect, it } from "vitest";
import { AUDIENCES } from "./features";
import { featuresPage } from "./prerender";
import { FEATURES_META, sitemap } from "./seo";

const INDEX = `<html><head><title>GnoRadio</title>
<meta name="description" content="x" />
<meta property="og:title" content="x" />
<meta property="og:description" content="x" />
<meta property="og:url" content="https://site.example/" />
<meta name="twitter:title" content="x" />
<meta name="twitter:description" content="x" />
</head><body><div id="root"><div class="splash"></div></div></body></html>`;

describe("featuresPage", () => {
  const html = featuresPage(INDEX, "https://site.example");
  const doc = new DOMParser().parseFromString(html, "text/html");
  const meta = (sel: string) => doc.querySelector(sel)?.getAttribute("content");

  it("has its own head", () => {
    expect(doc.title).toBe(FEATURES_META.title);
    expect(meta('meta[name="description"]')).toBe(FEATURES_META.description);
    expect(meta('meta[property="og:url"]')).toBe("https://site.example/features");
    expect(meta('meta[name="twitter:title"]')).toBe(FEATURES_META.title);
    expect(doc.querySelector('link[rel="canonical"]')?.getAttribute("href")).toBe("https://site.example/features");
  });
  it("describes the page and the video in JSON-LD", () => {
    const ld = JSON.parse(doc.querySelector('script[type="application/ld+json"]')?.textContent ?? "") as { "@type": string; duration?: string; contentUrl?: string }[];
    expect(ld.map((x) => x["@type"])).toEqual(["WebPage", "VideoObject", "WebApplication"]);
    expect(JSON.stringify(ld[2])).toContain('"price":"0"');
    expect(ld[1]?.duration).toBe("PT57S");
    expect(ld[1]?.contentUrl).toBe("https://archive.org/download/gnoradio-promo/promo.mp4");
  });
  it("puts every feature in the body, one h1, before the app takes over", () => {
    expect(doc.querySelectorAll("h1")).toHaveLength(1);
    const h3 = [...doc.querySelectorAll("#root h3")].map((h) => h.textContent);
    for (const f of AUDIENCES.flatMap((a) => [...a.cards, ...a.more])) expect(h3).toContain(f.title);
    expect(doc.querySelector("#root .splash")).not.toBeNull();
    // main.tsx removes exactly this before hydrateRoot, so React finds App's first render (the splash).
    expect(doc.querySelector("#root > .seo-static + .splash, #root > .seo-static ~ *")).not.toBeNull();
    expect(doc.querySelectorAll("#root .seo-static h3").length).toBe(h3.length);
    expect(doc.querySelector("video")?.hasAttribute("autoplay")).toBe(false);
  });
});

describe("sitemap", () => {
  it("is valid XML listing each path", () => {
    const xml = new DOMParser().parseFromString(sitemap("https://site.example", ["", "features"]), "application/xml");
    expect(xml.querySelector("parsererror")).toBeNull();
    expect([...xml.querySelectorAll("loc")].map((l) => l.textContent)).toEqual(["https://site.example/", "https://site.example/features"]);
  });
});
