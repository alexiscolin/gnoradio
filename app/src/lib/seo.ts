import { nickname } from "./nickname";
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
  legal: "Legal",
};

/** pageTitle names a screen for the tab, history and bookmarks: "Air · GnoRadio". */
export function pageTitle(v: View, name: string): string {
  if (v.k === "listener") return `${name ? `@${name}` : nickname(v.address)} · GnoRadio`;
  if (v.k === "collection") return `${v.list === "saved" ? "Saved" : "Liked"} · Your library · GnoRadio`;
  if (v.k === "door") return `Ticket #${String(v.ticket)} · GnoRadio`;
  if (v.k === "stations" && v.live !== undefined) return `${name || "Main"} live · GnoRadio`;
  const label = name || (v.k === "track" || v.k === "artist" || v.k === "album" || v.k === "playlist" ? "" : SECTION_TITLES[v.k]);
  return label ? `${label} · GnoRadio` : "GnoRadio";
}
