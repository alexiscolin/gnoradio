/// <reference types="vite/client" />

interface ImportMetaEnv {
  /** Chain preset: dev, onyx or mainnet (lib/network.ts); each variable below overrides one value of it. */
  readonly VITE_NETWORK?: string;
  /** gno.land RPC the page reads; the dev proxy /rpc on a devnet, the chain's public RPC otherwise. */
  readonly VITE_RPC?: string;
  /** Chain id the wallet must sign for (dev, onyx-1…). */
  readonly VITE_CHAIN_ID?: string;
  /** RPC the Adena wallet should use for this chain (defaults to <host>:27157 on dev). */
  readonly VITE_WALLET_RPC?: string;
  /** gnoweb base URL, for "read the code" links. */
  readonly VITE_GNOWEB?: string;
  /** Namespace of the GnoRadio packages: "gnoradio" locally, the deployer's on a public chain. */
  readonly VITE_GNORADIO_NS?: string;
  readonly VITE_RULES_VERSION?: string; // the rules release in force: v1 (default), v2...
  readonly VITE_RULES_FROM?: string; // unix time that release takes over; before it, the previous one
  /** PostHog project key (phc_…, public, write-only): audience measurement; unset, nothing loads. */
  readonly VITE_POSTHOG_KEY?: string;
}

interface ImportMeta {
  readonly env: ImportMetaEnv;
}
