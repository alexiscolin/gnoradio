/// <reference types="vite/client" />

interface ImportMetaEnv {
  /** gno.land RPC endpoint; defaults to the dev proxy at /rpc. */
  readonly VITE_RPC?: string;
  /** Chain id the wallet must sign for (dev, onyx-1…). */
  readonly VITE_CHAIN_ID?: string;
  /** RPC the Adena wallet should use for this chain (defaults to <host>:27157 on dev). */
  readonly VITE_WALLET_RPC?: string;
  /** gnoweb base URL, for "read the code" links. */
  readonly VITE_GNOWEB?: string;
  /** The release this build is (commit), set in vite.config.ts. */
  readonly VITE_BUILD_ID?: string;
}

interface ImportMeta {
  readonly env: ImportMetaEnv;
}
