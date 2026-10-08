import { nickname } from "./nickname.ts";
import type { Section } from "./router.ts";
import type { View } from "./types.ts";

/** FEATURES_NAME: the /features page, in the menu, the tab title and its share card. */
export const FEATURES_NAME = "Get started";

const SECTION_TITLES: Readonly<Record<Section, string>> = {
  listen: "Community radio, open music",
  stations: "Stations",
  library: "Library",
  community: "Community",
  concerts: "Concerts",
  contribute: "Contribute",
  me: "Me",
  studio: "Studio",
  about: "About",
  features: FEATURES_NAME,
  legal: "Legal",
};

/** FEATURES_META: the /features page's title and description, for the tab, the static copy and link previews. */
export const FEATURES_META = {
  title: "GnoRadio · Free community radio you program, tips to artists",
  description: "Listen free, no wallet. Pick the next song for everyone on air. Artists publish their music and get tipped, 0% to GnoRadio.",
} as const;

/** sitemap lists the site's sections for crawlers (paths without the leading slash, "" for home). */
export const sitemap = (site: string, paths: readonly string[]): string =>
  `<?xml version="1.0" encoding="UTF-8"?><urlset xmlns="http://www.sitemaps.org/schemas/sitemap/0.9">${paths.map((p) => `<url><loc>${site}/${p}</loc></url>`).join("")}</urlset>\n`;

/** pageTitle names a screen for the tab, history and bookmarks: "Air · GnoRadio". */
export function pageTitle(v: View, name: string): string {
  if (v.k === "listener") return `${name ? `@${name}` : nickname(v.address)} · GnoRadio`;
  if (v.k === "collection") return `${v.list === "saved" ? "Saved" : "Liked"} · Your library · GnoRadio`;
  if (v.k === "notfound") return "Not found · GnoRadio";
  if (v.k === "door") return `Ticket #${String(v.ticket)} · GnoRadio`;
  if (v.k === "stations" && v.live !== undefined) return `${name || "Main"} live · GnoRadio`;
  const label = name || (v.k === "track" || v.k === "artist" || v.k === "album" || v.k === "playlist" ? "" : SECTION_TITLES[v.k]);
  return label ? `${label} · GnoRadio` : "GnoRadio";
}
