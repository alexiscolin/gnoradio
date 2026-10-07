import { useCallback, useEffect, useMemo, useReducer, useState } from "react";
import { CHAIN_ID, account, connect, hasAdena, isCancel, onWalletChange, switchNetwork } from "../lib/gno";
import { errorMessage } from "../lib/format";
import { endSession, savedSession, startSession } from "../lib/session";

export type WalletState =
  | { readonly status: "missing" }
  | { readonly status: "idle" }
  | { readonly status: "connecting" }
  | { readonly status: "wrong-network"; readonly address: string; readonly chainId: string }
  | { readonly status: "connected"; readonly address: string; readonly chainId: string };

const fromAccount = (acc: { address: string; chainId: string } | undefined): WalletState => {
  if (!acc) return { status: "idle" };
  return acc.chainId === CHAIN_ID
    ? { status: "connected", address: acc.address, chainId: acc.chainId }
    : { status: "wrong-network", address: acc.address, chainId: acc.chainId };
};

// Adena has no disconnect API: "Disconnect" makes the app forget the wallet,
// remembered across reloads so it never reconnects silently. Connect clears it.
const FORGOT = "gnoradio.walletForgotten";
const isForgotten = (): boolean => { try { return localStorage.getItem(FORGOT) === "1"; } catch { return false; } };
const setForgotten = (on: boolean) => {
  try { if (on) localStorage.setItem(FORGOT, "1"); else localStorage.removeItem(FORGOT); } catch { /* private mode: forget for this session only */ }
};

/** Signer is how actions get signed: in Adena, or as a gnokey command the user runs. */
export type Signer = "adena" | "gnokey";
const SIGNER = "gnoradio.signer";
const savedSigner = (): Signer => { try { return localStorage.getItem(SIGNER) === "gnokey" ? "gnokey" : "adena"; } catch { return "adena"; } };

/** useWallet tracks the Adena wallet (installed, connected, on the right network), the signer and quick actions. */
export function useWallet(onError: (msg: string) => void) {
  const [state, setState] = useState<WalletState>(() => (hasAdena() ? { status: "idle" } : { status: "missing" }));

  const refresh = useCallback(async () => {
    if (!hasAdena()) {
      setState({ status: "missing" });
      return;
    }
    setState(isForgotten() ? { status: "idle" } : fromAccount(await account()));
  }, []);

  useEffect(() => {
    // Adena injects itself after load: look again shortly after, then listen.
    let off: (() => void) | undefined;
    const id = window.setTimeout(() => {
      void refresh();
      off = onWalletChange(() => void refresh());
    }, 600);
    return () => {
      window.clearTimeout(id);
      off?.();
    };
  }, [refresh]);

  // No Adena in this browser: actions and Connect open the "you need a wallet" sheet instead.
  const [asking, setAsking] = useState(false);
  const ask = useCallback(() => { setAsking(true); }, []);
  const closeAsk = useCallback(() => { setAsking(false); }, []);

  const connectWallet = useCallback(async () => {
    if (!hasAdena()) {
      setAsking(true);
      return;
    }
    setState({ status: "connecting" });
    try {
      const acc = await connect();
      setForgotten(false); // only once the user actually accepted: a cancelled prompt keeps the Disconnect
      setState(fromAccount(acc));
    } catch (e) {
      if (!isCancel(e)) onError(errorMessage(e));
      await refresh();
    }
  }, [onError, refresh]);

  const fixNetwork = useCallback(async () => {
    try {
      await switchNetwork();
      await refresh();
    } catch (e) {
      onError(errorMessage(e));
    }
  }, [onError, refresh]);

  /** ensure returns a usable address, prompting for connection or network as needed. */
  const ensure = useCallback(async (): Promise<string> => {
    let acc = isForgotten() ? undefined : await account();
    acc ??= await connect();
    setForgotten(false); // cleared only after a successful connect
    if (acc.chainId !== CHAIN_ID) {
      await switchNetwork();
      acc = await account();
    }
    if (!acc) throw new Error("Adena is not connected.");
    if (acc.chainId !== CHAIN_ID) throw new Error(`Switch Adena to the ${CHAIN_ID} network.`);
    setState(fromAccount(acc));
    return acc.address;
  }, []);

  const disconnect = useCallback(() => { setForgotten(true); setState({ status: "idle" }); }, []);

  const [signer, setSignerState] = useState(savedSigner);
  const setSigner = useCallback((s: Signer) => {
    try { localStorage.setItem(SIGNER, s); } catch { /* private mode: this visit only */ }
    setSignerState(s);
  }, []);

  // Quick actions: the account session this browser holds for the connected address (lib/session).
  const [, recheck] = useReducer((n: number) => n + 1, 0);
  const quick = state.status === "connected" && savedSession(state.address) !== undefined;
  const setQuick = useCallback(async (on: boolean) => {
    try {
      const address = await ensure();
      await (on ? startSession(address) : endSession(address));
      onError(on ? "Quick actions on" : "Quick actions off");
    } catch (e) {
      if (!isCancel(e)) onError(errorMessage(e));
    } finally {
      recheck();
    }
  }, [ensure, onError]);

  return useMemo(
    () => ({ state, connectWallet, fixNetwork, ensure, disconnect, signer, setSigner, quick, setQuick, asking, ask, closeAsk }),
    [state, connectWallet, fixNetwork, ensure, disconnect, signer, setSigner, quick, setQuick, asking, ask, closeAsk],
  );
}

export type Wallet = ReturnType<typeof useWallet>;
