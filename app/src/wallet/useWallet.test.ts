import { act, renderHook, waitFor } from "@testing-library/react";
import { afterEach, describe, expect, it, vi } from "vitest";
import { useWallet } from "./useWallet";

const ADDR = "g1jg8mtutu9khhfwc4nxmuhcpftf0pajdhfvsqf5";
const ok = (type: string, data?: unknown) => Promise.resolve({ code: 0, status: "success", type, message: "", data });

// Node's own localStorage shadows jsdom's here; give the test a real in-memory one.
const store = new Map<string, string>();
vi.stubGlobal("localStorage", {
  getItem: (k: string) => store.get(k) ?? null,
  setItem: (k: string, v: string) => { store.set(k, v); },
  removeItem: (k: string) => { store.delete(k); },
});

afterEach(() => {
  Reflect.deleteProperty(window, "adena");
  store.clear();
});

describe("useWallet disconnect", () => {
  it("forgets the wallet across reloads until Connect is pressed again", async () => {
    const adena = {
      AddEstablish: vi.fn(() => ok("CONNECTION_SUCCESS")),
      GetAccount: vi.fn(() => ok("GET_ACCOUNT", { address: ADDR, chainId: "dev" })),
    };
    Object.defineProperty(window, "adena", { value: adena, configurable: true });

    const first = renderHook(() => useWallet(() => undefined));
    await waitFor(() => { expect(first.result.current.state.status).toBe("connected"); });
    act(() => { first.result.current.disconnect(); });
    expect(first.result.current.state.status).toBe("idle");
    first.unmount();

    const calls = adena.GetAccount.mock.calls.length;
    vi.useFakeTimers({ toFake: ["setTimeout", "clearTimeout"] });
    const reload = renderHook(() => useWallet(() => undefined));
    await act(() => vi.advanceTimersByTimeAsync(600)); // the delayed Adena check has run
    vi.useRealTimers();
    expect(reload.result.current.state.status).toBe("idle");
    expect(adena.GetAccount.mock.calls.length).toBe(calls); // it did not reconnect on its own

    await act(() => reload.result.current.connectWallet());
    expect(reload.result.current.state.status).toBe("connected");
  });

  it("keeps the Disconnect when the Adena prompt is cancelled", async () => {
    let accept = true;
    const adena = {
      AddEstablish: vi.fn(() => (accept ? ok("CONNECTION_SUCCESS") : Promise.resolve({ code: 4000, status: "failure", type: "TRANSACTION_REJECTED", message: "rejected", data: null }))),
      GetAccount: vi.fn(() => ok("GET_ACCOUNT", { address: ADDR, chainId: "dev" })),
    };
    Object.defineProperty(window, "adena", { value: adena, configurable: true });

    const first = renderHook(() => useWallet(() => undefined));
    await waitFor(() => { expect(first.result.current.state.status).toBe("connected"); });
    act(() => { first.result.current.disconnect(); });
    accept = false;
    await act(() => first.result.current.connectWallet()); // the user rejects the prompt
    first.unmount();

    const reload = renderHook(() => useWallet(() => undefined));
    await new Promise((r) => setTimeout(r, 700));
    expect(reload.result.current.state.status).toBe("idle");
  });
});
