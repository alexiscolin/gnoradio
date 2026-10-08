import { createContext, useContext } from "react";

/** feesOn: the operator takes a fee only when a treasury is set or tickets carry a service fee. */
export const feesOn = (treasury: string, serviceFee: number): boolean => treasury !== "" || serviceFee > 0;

/** FeesContext holds that decision, read once (community.loadFees); no fee until the realm says otherwise. */
export const FeesContext = createContext(false);
export const useFees = (): boolean => useContext(FeesContext);
