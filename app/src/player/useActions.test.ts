import { act, renderHook } from "@testing-library/react";
import { describe, expect, it, vi } from "vitest";
import type { Call } from "../lib/gno";
import type { ConcertEvent, Track } from "../lib/types";
import { useActions } from "./useActions";

// What reaches the signer: the realm, function, positional args and coins of each action.
const ME = "g1jg8mtutu9khhfwc4nxmuhcpftf0pajdhfvsqf5";
const sent: Call[] = [];
vi.mock("../lib/gno", async (orig) => ({
  ...(await orig<object>()),
  hasAdena: () => true,
  call: (_a: string, c: Call) => { sent.push(c); return Promise.resolve({ hash: "h", height: "1" }); },
  qeval: () => Promise.resolve(""),
  qjson: (_p: string, expr: string) => Promise.resolve(expr.startsWith("FeesJSON") ? { serviceFee: 500_000 } : []),
}));
vi.mock("../lib/session", () => ({ inSession: () => false, usableSession: () => Promise.resolve(false), sessionCall: vi.fn() }));
vi.mock("../wallet/useWallet", () => ({
  useWallet: () => ({ state: { status: "idle" }, ensure: () => Promise.resolve(ME), signer: "adena", ask: vi.fn() }),
}));

const t = { id: 8, artist: 3 } as unknown as Track;

async function sign(f: (a: ReturnType<typeof useActions>) => void): Promise<Call | undefined> {
  sent.length = 0;
  const { result } = renderHook(() => useActions(() => undefined));
  await act(async () => { f(result.current); await new Promise((r) => setTimeout(r, 0)); });
  return sent[0];
}

describe("useActions encodes each call as the realm expects", () => {
  it("likes, picks, books and tips", async () => {
    const R = (await import("../lib/realms")).REALMS;
    expect(await sign((a) => { a.like(t); })).toEqual({ pkg: R.catalog, func: "Like", args: ["8"], send: undefined });
    expect(await sign((a) => { a.queue(t, 3); })).toEqual({ pkg: R.radio, func: "Queue", args: ["3", "8"], send: undefined });
    expect(await sign((a) => { a.queue(t, 3, "", false, 1_800_000_000); })).toMatchObject({ func: "QueueAt", args: ["3", "8", "1800000000"] });
    expect(await sign((a) => { a.queue(t, 3, "", true); })).toMatchObject({ func: "QueueSponsored", args: ["3", "8"] });
    expect(await sign((a) => { a.tip(t, 1_000_000, 10); })).toEqual({ pkg: R.catalog, func: "TipWithSupport", args: ["8", "10"], send: 1_000_000 });
    expect(await sign((a) => { a.tip(t, 1_000_000, 0, 2, ME); })).toEqual({ pkg: R.radio, func: "TipOnAir", args: ["2", "8", "0", ME], send: 1_000_000 });
  });

  it("buys a ticket for price plus the fee read now, and withdraws from the vault account", async () => {
    const R = (await import("../lib/realms")).REALMS;
    expect(await sign((a) => { a.buyTicket({ id: 4, price: 2_000_000 } as ConcertEvent); })).toEqual({ pkg: R.tickets, func: "BuyTicket", args: ["4"], send: 2_500_000 });
    expect(await sign((a) => { a.withdrawPromo(3); })).toEqual({ pkg: R.data, func: "VaultWithdraw", args: ["catalog/00000003"], send: undefined });
    expect(await sign((a) => { a.reportNote(2, 1700, () => undefined); })).toMatchObject({ pkg: R.radio, func: "ReportNote", args: ["2", "1700"] });
  });
});
