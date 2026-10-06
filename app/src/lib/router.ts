import type { View } from "./types";

/** Hash routes make every screen shareable: #/track/12, #/station/3, #/artist/2… */
export function viewToHash(v: View): string {
  switch (v.k) {
    case "library":
      return v.genre ? `#/library/${String(v.genre)}` : "#/library";
    case "track":
    case "artist":
    case "album":
    case "playlist":
      return `#/${v.k}/${String(v.id)}`;
    case "listen":
      return "#/";
    default:
      return `#/${v.k}`;
  }
}

export function hashToView(hash: string): View {
  const [k = "", arg = ""] = hash.replace(/^#\/?/, "").split("/");
  const id = Number.parseInt(arg, 10);
  const n = Number.isFinite(id) && id > 0 ? id : 0;
  switch (k) {
    case "stations":
    case "search":
    case "saved":
    case "concerts":
    case "community":
    case "me":
    case "studio":
      return { k };
    case "library":
      return { k, genre: n };
    case "track":
    case "artist":
    case "album":
    case "playlist":
      return n ? { k, id: n } : { k: "listen" };
    default:
      return { k: "listen" };
  }
}
