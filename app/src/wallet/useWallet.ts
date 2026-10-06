import { useCallback, useEffect, useMemo, useState } from "react";
import { CHAIN_ID, account, connect, hasAdena, isCancel, onWalletChange, switchNetwork } from "../lib/gno";
import { errorMessage } from "../lib/format";

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

/** useWallet tracks the Adena wallet: installed, connected, on the right network. */
export function useWallet(onError: (msg: string) => void) {
  const [state, setState] = useState<WalletState>(() => (hasAdena() ? { status: "idle" } : { status: "missing" }));

  const refresh = useCallback(async () => {
    if (!hasAdena()) {
      setState({ status: "missing" });
      return;
    }
    setState(fromAccount(await account()));
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

  const connectWallet = useCallback(async () => {
    setState({ status: "connecting" });
    try {
      setState(fromAccount(await connect()));
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
    let acc = await account();
    acc ??= await connect();
    if (acc.chainId !== CHAIN_ID) {
      await switchNetwork();
      acc = await account();
    }
    if (!acc) throw new Error("Adena is not connected.");
    if (acc.chainId !== CHAIN_ID) throw new Error(`Switch Adena to the ${CHAIN_ID} network.`);
    setState(fromAccount(acc));
    return acc.address;
  }, []);

  const disconnect = useCallback(() => { setState({ status: "idle" }); }, []);
  return useMemo(() => ({ state, connectWallet, fixNetwork, ensure, disconnect }), [state, connectWallet, fixNetwork, ensure, disconnect]);
}

export type Wallet = ReturnType<typeof useWallet>;
