// Link previews: what a shared page shows in a preview (title, line, cover),
// read on-chain. Shared by the edge function meta.ts (the tags, Deno) and the
// function og.mts (the image, Node): plain fetch, nothing else.
import { fnv, utf8Base64 } from "../src/lib/format";
import { nickname } from "../src/lib/nickname";
import { isAddress, unquote } from "../src/lib/proof";
import { REALMS, SAFE } from "../src/lib/realms";
import { FEATURES_META, FEATURES_NAME } from "../src/lib/seo";

export interface Card {
  /** path is the card's canonical page, its image lives at /og<path>.png. */
  readonly path: string;
  readonly kicker: string;
  readonly title: string;
  readonly by: string;
  /** art is the real cover's media reference (https, ipfs, ar), "" for the generated one. */
  readonly art: string;
  /** seed picks the generated composition, as Cover.tsx does: `${id}${title}` of the track. */
  readonly seed: string;
  readonly page: string;
  readonly description: string;
  readonly alt: string;
}

interface Track { id: number; title: string; artistName: string; cover: string; audio: string }
interface Event { id: number; artistName: string; title: string; venue: string; start: number; cancelled: boolean }

/** RealmError: the node answered, and the realm refused the read (an unknown or hidden id panics); a timeout or a bad reply is not one. */
export class RealmError extends Error {}

/** qevalRaw reads a realm expression's raw answer, e.g. `(12 int64)`; netlify/'s one chain-read client. */
export async function qevalRaw(rpc: string, realm: string, expr: string): Promise<string> {
  const r = await fetch(rpc, {
    method: "POST",
    headers: { "content-type": "application/json" },
    body: JSON.stringify({ jsonrpc: "2.0", id: 1, method: "abci_query", params: { path: "vm/qeval", data: utf8Base64(`${realm}.${expr}`) } }),
    signal: AbortSignal.timeout(3000),
  });
  const res = ((await r.json()) as { result?: { response?: { ResponseBase?: { Data?: string; Error?: unknown } } } }).result?.response?.ResponseBase;
  if (res?.Error) throw new RealmError(`${expr}: no answer`);
  if (!res?.Data) throw new Error(`${expr}: no answer`);
  return new TextDecoder().decode(Uint8Array.from(atob(res.Data), (c) => c.charCodeAt(0)));
}

/** qeval reads a realm expression returning a string ("" when the realm has none). */
export const qeval = async (rpc: string, realm: string, expr: string): Promise<string> => unquote(await qevalRaw(rpc, realm, expr));
const read = async <T>(rpc: string, realm: string, expr: string): Promise<T> => JSON.parse(await qeval(rpc, realm, expr)) as T;

/**
 * named gives an Audius or Jamendo pointer (no title on chain) the platform's
 * name as title and artist. A preview never calls the platforms: they are read
 * for /api/meta (bounded by the chain, an hour of cache) and nothing else.
 */
function named(t: Track): Track {
  if (t.title !== "" || !/^(audius|jamendo):/.test(t.audio)) return t;
  const platform = t.audio.startsWith("jamendo:") ? "Jamendo" : "Audius";
  return { ...t, title: `${platform} track`, artistName: `${platform} artist`, cover: "" };
}

/** art is the track's real cover, as Cover.tsx resolves it: its own cover (a pointer has none: the generated one). */
const art = (t: Track): string => t.cover;
const seed = (t: Track): string => `${String(t.id)}${t.title}`;
const LISTEN = "Listen on GnoRadio";

/** cardOf reads the card for a page path (/track/air-4, /live/3, /listener/g1…, /door/7-g1…), null when there is none. */
export async function cardOf(rpc: string, path: string): Promise<Card | null> {
  const [, kind = "", arg = ""] = path.split("/");
  // An id goes into a Gno expression and the canonical path: always as a plain number
  // (TrackJSON(012) would read octal 10), so /track/012 is track 12's card.
  const id = canonicalId(/(?:^|-)(\d{1,9})$/.exec(arg)?.[1]);
  const track = (n: number | string) => read<Track>(rpc, REALMS.catalog, `TrackJSON(${String(n)})`).then(named);
  // An artist's, album's or playlist's lists keep its hidden tracks, whose TrackJSON fails: the card goes without.
  const listed = (n: number) => track(n).catch(() => null);
  switch (kind) {
    case "track": {
      if (id === undefined) return null;
      const t = await track(id);
      return {
        path: `/track/${id}`, kicker: LISTEN, title: t.title, by: t.artistName, art: art(t), seed: seed(t),
        page: `${t.title} · ${t.artistName} · GnoRadio`,
        description: `Listen to ${t.title} by ${t.artistName} on GnoRadio, the community radio on gno.land.`,
        alt: `Cover of ${t.title} by ${t.artistName}, on GnoRadio`,
      };
    }
    case "artist": {
      if (id === undefined) return null;
      const a = await read<{ name: string; bio: string; tracks: number[]; verified?: boolean; proofHost?: string }>(rpc, REALMS.catalog, `ArtistJSON(${id})`);
      const latest = a.tracks.length ? await listed(Math.max(...a.tracks)) : null;
      // The host a verified artist's proof was found on (ArtistJSON's proofHost), "" when unknown.
      const host = a.verified && /^[a-z0-9.-]{1,253}$/i.test(a.proofHost ?? "") ? (a.proofHost ?? "").toLowerCase() : "";
      // Anyone can register any name: an unverified profile says so, and neither its own bio nor tips are shown.
      // A ✓ only proves control of a domain, so the domain is named.
      const status = a.verified ? (host ? `Verified via ${host}` : "Verified artist") : "Unverified profile";
      return {
        path: `/artist/${id}`, kicker: a.verified ? `Artist · ${host ? `verified via ${host}` : "verified"}` : "Artist · unverified profile", title: a.name, by: latest ? `Latest: ${latest.title}` : "",
        art: latest ? art(latest) : "", seed: latest ? seed(latest) : `${id}${a.name}`,
        page: `${a.name} · GnoRadio`,
        description: a.verified
          ? `${status}. ${a.bio || `Listen to ${a.name} on GnoRadio, the community radio on gno.land. Tips go straight to the artist's wallet.`}`
          : `${status}: anyone can register a name on GnoRadio. Listen on GnoRadio, the community radio on gno.land.`,
        alt: `${a.name} on GnoRadio, with the cover of their latest track`,
      };
    }
    case "album":
    case "playlist": {
      if (id === undefined) return null;
      const fn = kind === "album" ? "AlbumJSON" : "PlaylistJSON";
      const { cover = "", ...l } = await read<{ title: string; cover?: string; tracks: number[] }>(rpc, REALMS.catalog, `${fn}(${id})`);
      const first = l.tracks[0] === undefined ? null : await listed(l.tracks[0]);
      const by = kind === "album" ? first?.artistName ?? "" : `Playlist · ${String(l.tracks.length)} tracks`;
      return {
        path: `/${kind}/${id}`, kicker: LISTEN, title: l.title, by,
        art: cover || (first ? art(first) : ""), seed: first ? seed(first) : `${id}${l.title}`,
        page: `${l.title}${kind === "album" && by ? ` · ${by}` : ""} · GnoRadio`,
        description: `Listen to ${l.title}${kind === "album" && by ? ` by ${by}` : ""} on GnoRadio, the community radio on gno.land. Your song. On air. For everyone.`,
        alt: `Cover of ${l.title}, on GnoRadio`,
      };
    }
    case "live": {
      const sid = arg === "" ? "0" : id;
      if (sid === undefined) return null;
      const { stations } = await read<{ stations: { id: number; name: string; now: { track: number } }[] }>(rpc, REALMS.radio, "StationsJSON()");
      const st = stations.find((s) => s.id === Number(sid));
      if (!st) return null;
      const t = st.now.track > 0 ? await track(st.now.track) : null;
      const onAir = t ? `${t.title} · ${t.artistName}` : "";
      return {
        path: `/live/${sid}`, kicker: `On air now · ${st.name}`, title: t?.title ?? st.name, by: t?.artistName ?? "",
        art: t ? art(t) : "", seed: t ? seed(t) : `${sid}${st.name}`,
        page: t ? `On air now on ${st.name}: ${onAir}` : `${st.name} live · GnoRadio`,
        description: `Tune in to ${st.name} on GnoRadio, the community radio on gno.land: pick what plays next for everyone.`,
        alt: t ? `On air now on GnoRadio ${st.name}: ${onAir}` : `GnoRadio ${st.name}`,
      };
    }
    case "listener": {
      const a = arg.slice(-40);
      if (!isAddress(a) || (arg.length !== 40 && arg.at(-41) !== "-")) return null;
      const [name, picks] = await Promise.all([
        gnoName(rpc, a).catch(() => ""),
        read<{ picks: number }>(rpc, REALMS.radio, `CuratorJSON(address("${a}"))`).then((c) => c.picks, () => 0),
      ]);
      const who = name ? `@${name}` : nickname(a);
      const n = `${String(picks)} ${picks === 1 ? "pick" : "picks"} on air`;
      return {
        path: `/listener/${a}`, kicker: "Listener on GnoRadio", title: who, by: n, art: "", seed: a,
        page: `${who} · GnoRadio`,
        description: `${who}: ${n}, played for everyone on GnoRadio. Listening is free, no wallet needed.`,
        alt: `${who}, a GnoRadio listener: ${n}`,
      };
    }
    case "concerts":
    case "door": {
      // /concerts/3 names the concert, /door/7-g1… a ticket for one.
      const [rawTicket = "", holder = ""] = arg.split("-");
      const ticket = canonicalId(rawTicket);
      const expr = kind === "door"
        ? ticket !== undefined && isAddress(holder) ? `func() string { t, ok := TicketInfo(${ticket}); if !ok { return "" }; e, ok := EventInfo(t.Event); if !ok { return "" }; return eventJSON(&e, "0") }()` : ""
        : id === undefined ? "" : `func() string { e, ok := EventInfo(${id}); if !ok { return "" }; return eventJSON(&e, "0") }()`;
      if (!expr) return null;
      const e = await read<Event>(rpc, REALMS.tickets, expr);
      const date = new Date(e.start * 1000).toLocaleDateString("en-GB", { day: "numeric", month: "short", year: "numeric", timeZone: "UTC" });
      return {
        path: `/concerts/${String(e.id)}`, kicker: `${e.cancelled ? "Cancelled" : "Concert"} · ${date}`, title: e.title, by: `${e.artistName} · ${e.venue}`,
        art: "", seed: `${String(e.id)}${e.title}`,
        page: `${e.title} · ${e.artistName} · GnoRadio`,
        description: `${e.artistName} live at ${e.venue}, ${date}${e.cancelled ? " (cancelled)" : ""}. Tickets on GnoRadio, on-chain on gno.land.`,
        alt: `${e.title}: ${e.artistName} at ${e.venue}, ${date}`,
      };
    }
    case "features":
      // A fixed page: nothing to read on-chain.
      return {
        path: "/features", kicker: FEATURES_NAME, title: "Your song. On air. For everyone.", by: "Pick · Tip · Publish",
        art: "", seed: "features",
        page: FEATURES_META.title, description: FEATURES_META.description,
        alt: "GnoRadio: what you can do as a listener or an artist",
      };
    default:
      return null;
  }
}

/** canonicalId is a 1-9 digit id as a plain decimal (leading zeros dropped), undefined for anything else. */
const canonicalId = (raw: string | undefined): string | undefined => (raw !== undefined && /^\d{1,9}$/.test(raw) ? String(Number(raw)) : undefined);

/** gnoName is the address's gno.land name (r/sys/users), "" when none or when p/<NS>/safe blocks it. */
async function gnoName(rpc: string, a: string): Promise<string> {
  const n = await qeval(rpc, "gno.land/r/sys/users", `func() string { if d := ResolveAddress(address("${a}")); d != nil { return d.Name() }; return "" }()`);
  if (!/^[a-z0-9._-]{1,64}$/i.test(n)) return "";
  return (await qeval(rpc, SAFE, `func() string { if Blocked(${JSON.stringify(n)}) { return "1" }; return "0" }()`)) === "0" ? n : "";
}

/** version keys the image on what it shows: a new title or cover is a new URL, past every cache. */
export const version = (c: Card): string => fnv(JSON.stringify([c.kicker, c.title, c.by, c.art, c.seed])).toString(36);
