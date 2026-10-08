import { useEffect, useState } from "react";
import { REALMS, gnoAddress, qeval, unquote, qjson } from "./gno";
import { type Infer, arr, num, obj, oneOf, str } from "./guard";
import { feesOn } from "./fees";
import { isActivities, isEvent, isFees, isSupport, isTickets, isUser } from "./schemas";
import type { Activity, Catalog, ConcertEvent, OwnedTicket, SupportInfo, UserInfo } from "./types";

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
const isPicks = arr(obj({ kind: oneOf("queue", "curator", "sponsored"), by: str, track: num, station: num, start: num, at: num }));
export type RadioPick = Infer<typeof isPicks>[number];

/** loadPicks reads who programmed what on the radio: its last 64 picks, newest first. */
export const loadPicks = (): Promise<RadioPick[]> => qjson(REALMS.radio, "ActivityJSON(64)", isPicks).catch((): RadioPick[] => []);

export const loadSupport = (): Promise<SupportInfo> => qjson(REALMS.catalog, "SupportJSON()", isSupport).catch(() => EMPTY_SUPPORT);

/** loadFees reads whether the operator takes any fee (treasury set, or a ticket service fee); false when unknown. */
export const loadFees = (): Promise<boolean> => qjson(REALMS.tickets, "FeesJSON()", isFees).then((f) => feesOn(f.treasury, f.serviceFee)).catch(() => false);

export const loadUser = (address: string): Promise<UserInfo> => qjson(REALMS.catalog, `UserJSON(${gnoAddress(address)})`, isUser);

export const loadTicketsOf = (address: string): Promise<OwnedTicket[]> =>
  qjson(REALMS.tickets, `TicketsOfJSON(${gnoAddress(address)})`, isTickets).catch((): OwnedTicket[] => []);

/** loadTicket reads one ticket by id (tickets.TicketInfo, any holder, however many they have); null if none. */
export const loadTicket = async (id: number): Promise<OwnedTicket | null> => {
  const m = /\((\d+) int\),\s*\((\d+) int\),\s*\((\d+) int\),\s*\((true|false) bool\).*\(true bool\)/s.exec(await qeval(REALMS.tickets, `TicketInfo(${String(id)})`));
  return m ? { id: Number(m[1]), event: Number(m[2]), serial: Number(m[3]), attended: m[4] === "true" } : null;
};

/** loadTicketOwner reads who holds a ticket now ("" if none). */
export const loadTicketOwner = async (ticket: number): Promise<string> =>
  /g1[a-z0-9]{38}/.exec(await qeval(REALMS.tickets, `TicketOwner(${String(ticket)})`))?.[0] ?? "";

/** PRESENT_WINDOW: tickets.CheckIn takes a ticket its holder presented (tickets.Present) this many seconds ago at most. */
export const PRESENT_WINDOW = 600;
/** OPENS_BEFORE: check-in opens this long before the start (tickets.checkInWindow); a Present before that fails. */
export const OPENS_BEFORE = 12 * 3600;

/** loadPresentedAt reads when a ticket's holder last signed tickets.Present with this door code (unix seconds, 0 if not). */
export const loadPresentedAt = async (ticket: number, code: string): Promise<number> =>
  Number(/^\((-?\d+) int64\)/.exec(await qeval(REALMS.tickets, `PresentedAt(${String(ticket)}, ${JSON.stringify(code)})`))?.[1] ?? 0);

/** DOOR_CODE: the code the door shows after a scan and the holder signs in tickets.Present (4 to 8 digits). */
export const DOOR_CODE = /^\d{4,8}$/;

/** doorCode draws a fresh 4-digit door code. */
export const doorCode = (): string => String((crypto.getRandomValues(new Uint32Array(1))[0] ?? 0) % 10000).padStart(4, "0");

export const RIGHTS_FALLBACK = "I own or control the rights to this recording and its composition, or hold a licence that allows this, and I grant the operator of GnoRadio and its users a worldwide, non-exclusive, royalty-free licence to store, stream, broadcast and display it through GnoRadio and gno.land for as long as it is published.";

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

/** loadEvent reads one concert, past, cancelled or upcoming (null when there is none to show). */
export const loadEvent = (id: number): Promise<ConcertEvent | null> =>
  qjson(REALMS.tickets, `func() string { e, ok := EventInfo(${String(id)}); if !ok { return "" }; return eventJSON(&e, "0") }()`, isEvent).catch(() => null);

/**
 * useEvents gives the concerts of these ids: from the catalog's upcoming list, else read one
 * by one (a ticket for a cancelled or past concert is not in that list). A missing id maps to
 * undefined while it loads, null once the chain has none.
 */
export function useEvents(cat: Pick<Catalog, "events">, ids: readonly number[]): ReadonlyMap<number, ConcertEvent | null> {
  const [read, setRead] = useState<ReadonlyMap<number, ConcertEvent | null>>(new Map());
  const want = [...new Set(ids)].filter((id) => !cat.events.some((e) => e.id === id) && !read.has(id));
  const key = want.join(",");
  useEffect(() => {
    if (!key) return;
    let alive = true;
    void Promise.all(key.split(",").map(Number).map(async (id) => [id, await loadEvent(id)] as const)).then((got) => {
      if (alive) setRead((m) => new Map([...m, ...got]));
    });
    return () => { alive = false; };
  }, [key]);
  return new Map(ids.map((id) => [id, cat.events.find((e) => e.id === id) ?? read.get(id)] as const).filter((x): x is readonly [number, ConcertEvent | null] => x[1] !== undefined));
}
