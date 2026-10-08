// Which gno.land chain GnoRadio talks to. VITE_NETWORK picks a preset (dev,
// onyx, mainnet); VITE_RPC, VITE_CHAIN_ID, VITE_WALLET_RPC and VITE_GNOWEB
// still override one value each. Shared by the app (gno.ts, inlined at build)
// and netlify/ (read at run time through runtimeEnv).
import { runtimeEnv } from "./realms";

export type Network = "dev" | "onyx" | "mainnet";

/** set: an empty variable (KEY= in a copied .env file) counts as unset. */
export const set = (v: string | undefined): string | undefined => (v === "" ? undefined : v);

/** The public chains: both RPCs answer cross-origin reads (CORS *), so the page reads them directly. */
const PUBLIC = {
  onyx: { chainId: "onyx-1", rpc: "https://rpc.onyx.testnets.gno.land:443", gnoweb: "https://onyx.testnets.gno.land" },
  mainnet: { chainId: "gnoland-1", rpc: "https://rpc.gno.land:443", gnoweb: "https://gno.land" },
} as const;

export interface Endpoints {
  readonly network: Network;
  readonly chainId: string;
  /** rpc: where the page reads; walletRpc: what Adena is given (a devnet's /rpc proxy is the page's only). */
  readonly rpc: string;
  readonly walletRpc: string;
  readonly gnoweb: string;
}

type Env = Readonly<Partial<Record<"VITE_NETWORK" | "VITE_RPC" | "VITE_CHAIN_ID" | "VITE_WALLET_RPC" | "VITE_GNOWEB", string | undefined>>>;

/** endpoints resolves the preset, then the per-value overrides. fallback: the network when VITE_NETWORK is unset. */
export function endpoints(env: Env, fallback: Network, host = "127.0.0.1"): Endpoints {
  const want = env.VITE_NETWORK;
  const network: Network = want === "dev" || want === "onyx" || want === "mainnet" ? want : fallback;
  const p = network === "dev"
    ? { chainId: "dev", rpc: "/rpc", walletRpc: `http://${host}:27157`, gnoweb: `http://${host}:8911` }
    : { ...PUBLIC[network], walletRpc: PUBLIC[network].rpc };
  return {
    network,
    chainId: set(env.VITE_CHAIN_ID) ?? p.chainId,
    rpc: set(env.VITE_RPC) ?? p.rpc,
    walletRpc: set(env.VITE_WALLET_RPC) ?? p.walletRpc,
    gnoweb: set(env.VITE_GNOWEB) ?? p.gnoweb,
  };
}

/** serverRPC is the RPC netlify/ reads: the site's VITE_WALLET_RPC, else its network's (onyx when unset). */
export const serverRPC = (): string =>
  endpoints({ VITE_NETWORK: runtimeEnv("VITE_NETWORK"), VITE_WALLET_RPC: runtimeEnv("VITE_WALLET_RPC") }, "onyx").walletRpc;

/** serverChainId is the chain netlify/ certifies for: the site's VITE_CHAIN_ID, else its network's. */
export const serverChainId = (): string =>
  endpoints({ VITE_NETWORK: runtimeEnv("VITE_NETWORK"), VITE_CHAIN_ID: runtimeEnv("VITE_CHAIN_ID") }, "onyx").chainId;
