import { REALMS, gnoAddress, qeval, unquote, qjson } from "./gno";
import { type Infer, arr, num, obj, oneOf, str } from "./guard";
import { realmPage } from "./links";
import { isActivities, isSupport, isTickets, isUser } from "./schemas";
import type { Activity, OwnedTicket, SupportInfo, UserInfo } from "./types";

export const EMPTY_SUPPORT: SupportInfo = { treasury: "", total: 0, supporters: 0, month: "", monthTotal: 0, goal: 0, top: [] };

/** loadActivity merges the catalog and radio feeds, newest first. */
export async function loadActivity(limit = 40): Promise<Activity[]> {
  const [cat, radio] = await Promise.all([
    qjson(REALMS.catalog, `ActivityJSON(${String(limit)})`, isActivities).catch((): Activity[] => []),
    qjson(REALMS.radio, `ActivityJSON(${String(limit)})`, isActivities).catch((): Activity[] => []),
  ]);
  return [...cat, ...radio].sort((a, b) => b.at - a.at).slice(0, limit);
}

// The radio's own feed also says when each pick airs ("start").
const isPicks = arr(obj({ kind: oneOf("queue", "curator"), by: str, track: num, station: num, start: num, at: num }));
export type RadioPick = Infer<typeof isPicks>[number];

/** loadPicks reads who programmed what on the radio: its last 64 picks, newest first. */
export const loadPicks = (): Promise<RadioPick[]> => qjson(REALMS.radio, "ActivityJSON(64)", isPicks).catch((): RadioPick[] => []);

const WEEK = 7 * 86400;

/**
 * topProgrammers ranks listeners by their picks of the last 7 days (curator
 * picks do not count), most first.
 */
// ponytail: the radio keeps its last 64 picks only, so a busy week is undercounted; an indexer lifts that.
export function topProgrammers(picks: readonly RadioPick[], now: number, max = 5): { by: string; picks: number }[] {
  const n = new Map<string, number>();
  for (const p of picks) if (p.kind === "queue" && now - p.at < WEEK) n.set(p.by, (n.get(p.by) ?? 0) + 1);
  return [...n].map(([by, count]) => ({ by, picks: count })).sort((a, b) => b.picks - a.picks).slice(0, max);
}

/** listenerPage is a listener's public page on gnoweb: likes, playlists, tickets, badges. */
export const listenerPage = (address: string): string => realmPage("home", `listener/${address}`);

export const loadSupport = (): Promise<SupportInfo> => qjson(REALMS.catalog, "SupportJSON()", isSupport).catch(() => EMPTY_SUPPORT);

export const loadUser = (address: string): Promise<UserInfo> => qjson(REALMS.catalog, `UserJSON(${gnoAddress(address)})`, isUser);

export const loadTicketsOf = (address: string): Promise<OwnedTicket[]> =>
  qjson(REALMS.tickets, `TicketsOfJSON(${gnoAddress(address)})`, isTickets).catch((): OwnedTicket[] => []);

const RIGHTS_FALLBACK = "I own the rights to this recording and composition and grant GnoRadio a non-exclusive right to stream, broadcast and display it.";

/** loadRightsTerms reads the statement an artist accepts when publishing. */
export async function loadRightsTerms(): Promise<string> {
  try {
    return unquote(await qeval(REALMS.catalog, "RightsTerms()")) || RIGHTS_FALLBACK;
  } catch {
    return RIGHTS_FALLBACK;
  }
}

/** hostAllowed asks the catalog whether an https host is on its allowlist. */
export async function hostAllowed(host: string): Promise<boolean | undefined> {
  if (!/^[a-z0-9.-]{3,100}$/.test(host)) return false;
  try {
    const raw = await qeval(REALMS.catalog, `HostAllowed(${JSON.stringify(host)})`);
    return raw.startsWith("(true bool)");
  } catch {
    return undefined;
  }
}
