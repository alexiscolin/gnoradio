import { REALMS, gnoAddress, qjson } from "./gno";
import { isActivities, isFees, isSupport, isTickets, isUser } from "./schemas";
import type { Activity, Fees, SupportInfo, UserInfo } from "./types";

const EMPTY_SUPPORT: SupportInfo = { treasury: "", total: 0, supporters: 0, month: "", monthTotal: 0, goal: 0, top: [] };

/** loadActivity merges the catalog and radio feeds, newest first. */
export async function loadActivity(limit = 40): Promise<Activity[]> {
  const [cat, radio] = await Promise.all([
    qjson(REALMS.catalog, `ActivityJSON(${String(limit)})`, isActivities).catch((): Activity[] => []),
    qjson(REALMS.radio, `ActivityJSON(${String(limit)})`, isActivities).catch((): Activity[] => []),
  ]);
  return [...cat, ...radio].sort((a, b) => b.at - a.at).slice(0, limit);
}

export const loadSupport = (): Promise<SupportInfo> => qjson(REALMS.catalog, "SupportJSON()", isSupport).catch(() => EMPTY_SUPPORT);

export const loadFees = (): Promise<Fees> => qjson(REALMS.tickets, "FeesJSON()", isFees).catch(() => ({ serviceFee: 0, treasury: "" }));

export const loadUser = (address: string): Promise<UserInfo> => qjson(REALMS.catalog, `UserJSON(${gnoAddress(address)})`, isUser);

export interface OwnedTicket {
  readonly id: number;
  readonly event: number;
  readonly serial: number;
  readonly attended: boolean;
}

export const loadTicketsOf = (address: string): Promise<OwnedTicket[]> =>
  qjson(REALMS.tickets, `TicketsOfJSON(${gnoAddress(address)})`, isTickets).catch((): OwnedTicket[] => []);
