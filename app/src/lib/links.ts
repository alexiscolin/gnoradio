// Links from the app to gnoweb: the same pages rendered by the chain, and the
// code that runs them.

import { GNOWEB, REALMS } from "./gno";
import type { View } from "./types";

export type Realm = keyof typeof REALMS;

const pathOf = (r: Realm): string => REALMS[r].replace(/^gno\.land/, "");

/** realmPage is a realm's rendered page on gnoweb, with an optional render path. */
export const realmPage = (r: Realm, path = ""): string => `${GNOWEB}${pathOf(r)}${path ? `:${path}` : ""}`;

/** txURL opens a realm function's signing form on gnoweb ($help), for actions the app has no screen for. */
export const txURL = (r: Realm, func: string): string => `${GNOWEB}${pathOf(r)}$help&func=${func}`;

/** sourceURL opens a realm's file on gnoweb ($source), the code that actually runs. */
export const sourceURL = (r: Realm, file?: string): string => `${GNOWEB}${pathOf(r)}$source${file ? `&file=${file}` : ""}`;

/** gnowebOf maps an app screen to the matching page of the home realm on gnoweb. */
export function gnowebOf(v: View): string {
  switch (v.k) {
    case "track":
    case "artist":
    case "album":
    case "playlist":
      return realmPage("home", `${v.k}/${String(v.id)}`);
    case "listener":
      return realmPage("home", `listener/${v.address}`);
    case "stations":
      return realmPage("home", "stations");
    case "collection":
      return realmPage("home", "catalog");
    case "library":
      return realmPage("home", v.genre ? `catalog?g=${String(v.genre)}` : "catalog");
    case "concerts":
    case "door":
      return realmPage("home", "concerts");
    case "community":
      return realmPage("home", "charts");
    case "about":
    case "legal":
      return realmPage("home", "about");
    case "contribute":
      return realmPage("home", "join");
    case "listen":
    case "me":
    case "studio":
      return realmPage("home");
  }
}

/** The file holding each user-facing action, for "Read the code" links. */
export const CODE = {
  tip: ["catalog", "social.gno"],
  support: ["catalog", "support.gno"],
  like: ["catalog", "social.gno"],
  playlist: ["catalog", "social.gno"],
  publish: ["catalog", "tracks.gno"],
  artist: ["catalog", "artists.gno"],
  report: ["catalog", "moderation.gno"],
  radio: ["radio", "radio.gno"],
  tickets: ["tickets", "tickets.gno"],
} as const satisfies Record<string, readonly [Realm, string]>;

export const codeURL = (k: keyof typeof CODE): string => sourceURL(CODE[k][0], CODE[k][1]);
