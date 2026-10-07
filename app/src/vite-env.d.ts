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
  /** Namespace of the GnoRadio packages: "gnoradio" locally, the deployer's on a public chain. */
  readonly VITE_GNORADIO_NS?: string;
}

interface ImportMeta {
  readonly env: ImportMetaEnv;
}
