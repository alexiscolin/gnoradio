import { createContext, useContext } from "react";
import type { Call } from "./gno";
import { REALMS } from "./realms";

/**
 * Fees are two facts, read once (community.loadFees):
 * support: a treasury is set, so the +10% option, Support GnoRadio and the monthly goal exist;
 * ticketFee: tickets carry a service fee (the realm reports 0 while no treasury is set).
 */
export interface Fees {
  readonly support: boolean;
  readonly ticketFee: boolean;
  /** known is false until the realm has answered once (screens that depend on the fee show nothing meanwhile); absent means known. */
  readonly known?: boolean;
}

export const NO_FEES: Fees = { support: false, ticketFee: false };
/** UNKNOWN_FEES is the state before the first answer. */
export const UNKNOWN_FEES: Fees = { ...NO_FEES, known: false };

/** retryDelay is the wait before the n-th (1-based) retry of a failed read: 5 s, doubling, at most a minute. */
export const retryDelay = (n: number): number => Math.min(5000 * 2 ** (n - 1), 60_000);

export const feesOf = (treasury: string, serviceFee: number): Fees => ({ support: treasury !== "", ticketFee: serviceFee > 0 });

/** changesFees: a signed call that can change those facts (the admin's treasury or service fee). */
export const changesFees = (c?: Pick<Call, "pkg" | "func">): boolean =>
  (c?.pkg === REALMS.tickets && c.func === "SetServiceFee") || (c?.pkg === REALMS.catalog && c.func === "SetTreasury");

/** FeesContext holds them; no fee until the realm says otherwise. */
export const FeesContext = createContext<Fees>(NO_FEES);
export const useFees = (): Fees => useContext(FeesContext);
