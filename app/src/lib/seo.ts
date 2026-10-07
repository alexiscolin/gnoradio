import type { Section } from "./router";
import type { View } from "./types";

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
};

/** pageTitle names a screen for the tab, history and bookmarks: "Air · GnoRadio". */
export function pageTitle(v: View, name: string): string {
  if (v.k === "stations" && v.live !== undefined) return `${name || "Main"} live · GnoRadio`;
  const label = name || (v.k === "track" || v.k === "artist" || v.k === "album" || v.k === "playlist" ? "" : SECTION_TITLES[v.k]);
  return label ? `${label} · GnoRadio` : "GnoRadio";
}
