import { isAddress } from "./proof";
import type { View } from "./types";

/** slug turns a name into a URL word: "Scott Buckley" -> "scott-buckley". */
export const slug = (name: string): string =>
  name.normalize("NFKD").replace(/[\u0300-\u036f]/g, "").toLowerCase().replace(/[^a-z0-9]+/g, "-").replace(/^-+|-+$/g, "").slice(0, 60);

/** withName is "name-12": readable, and the id at the end keeps it unique and stable across renames. */
const withName = (id: number, name: string): string => (slug(name) ? `${slug(name)}-${String(id)}` : String(id));

/**
 * Every screen has a real, shareable path: /artist/scott-buckley-1,
 * /track/air-4, /live (Main), /live/ambient-3, /library/ambient-3… name is
 * the label shown in the URL (optional: the id alone resolves the same).
 */
export function viewToPath(v: View, name = ""): string {
  switch (v.k) {
    case "listen":
      return "/";
    case "library":
      return v.genre ? `/library/${withName(v.genre, name)}` : "/library";
    case "contribute":
      return v.path ? `/contribute/${v.path}` : "/contribute";
    case "track":
    case "artist":
    case "album":
    case "playlist":
      return `/${v.k}/${withName(v.id, name)}`;
    case "listener": // /listener/alice-g1… or /listener/g1…: the address is the id
      return `/listener/${slug(name) ? `${slug(name)}-` : ""}${v.address}`;
    case "stations":
      return v.live === undefined ? "/stations" : v.live === 0 ? "/live" : `/live/${withName(v.live, name)}`;
    default:
      return `/${v.k}`;
  }
}

/** pathToView reads a path, or a legacy "#/kind/id" hash link. */
export function pathToView(path: string): View {
  const [k = "", arg = ""] = path.replace(/^#?\/*/, "").split(/[/?#]/);
  const tail = /(?:^|-)(\d+)$/.exec(arg)?.[1];
  const n = tail === undefined ? 0 : Number(tail);
  switch (k) {
    case "search": // folded into Library
      return { k: "library", genre: 0 };
    case "saved": // folded into Me
      return { k: "me" };
    case "contribute":
      return arg === "listener" || arg === "artist" || arg === "claim" || arg === "report" ? { k, path: arg } : { k };
    case "live":
      return { k: "stations", live: arg === "" ? 0 : n };
    case "station": // legacy #/station/3
      return tail === undefined ? { k: "stations" } : { k: "stations", live: n };
    case "stations":
    case "concerts":
    case "community":
    case "me":
    case "studio":
    case "about":
    case "legal":
      return { k };
    case "library":
      return { k, genre: n };
    case "track":
    case "artist":
    case "album":
    case "playlist":
      return n > 0 ? { k, id: n } : { k: "listen" };
    case "listener": {
      const a = arg.slice(-40);
      return isAddress(a) && (arg.length === 40 || arg.at(-41) === "-") ? { k, address: a } : { k: "listen" };
    }
    default:
      return { k: "listen" };
  }
}

/** A top-level screen, one per navigation entry. Detail pages live under one. */
export type Section = Exclude<View["k"], "artist" | "album" | "playlist" | "track" | "listener">;

/** sectionOf is the navigation entry a screen belongs to, so the menu always shows where you are. */
export function sectionOf(v: View): Section {
  switch (v.k) {
    case "track":
    case "artist":
    case "album":
    case "playlist":
      return "library";
    case "listener":
      return "community";
    default:
      return v.k;
  }
}

/** sectionView opens a section at its root. */
export const sectionView = (k: Section): View => (k === "library" ? { k, genre: 0 } : { k });
