// GnoRadio's realm paths, shared by the app (gno.ts) and the robot
// (netlify/). A version upgrade edits this file only.
//
// NS is where the packages live: "gnoradio" on a local devnet, the deployer's
// namespace on a public chain (tools/deploy/stage.py). VITE_GNORADIO_NS is
// inlined in the app at build time and read at run time by netlify/.

/**
 * runtimeEnv reads a site variable at run time: Netlify.env on the edge
 * (Deno has no process.env) and in functions, else process.env. Netlify passes
 * only the variables set on the site, not netlify.toml's [build.environment].
 */
export function runtimeEnv(name: string): string | undefined {
  const g = globalThis as { Netlify?: { env: { get: (k: string) => string | undefined } }; process?: { env: Record<string, string | undefined> } };
  return g.Netlify?.env.get(name) ?? g.process?.env[name];
}

// import.meta.env exists in the app (Vite inlines it), not on Netlify's runtimes.
// An empty value (VITE_GNORADIO_NS= in a copied .env file) counts as unset.
const unset = (v: string | undefined): string | undefined => (v === "" ? undefined : v);
// eslint-disable-next-line @typescript-eslint/no-unnecessary-condition
const NS: string = unset(import.meta.env === undefined ? undefined : import.meta.env.VITE_GNORADIO_NS) ?? unset(runtimeEnv("VITE_GNORADIO_NS")) ?? "gnoradio";

// Release 1 of the rules realms. data is permanent: it holds every record and
// the promo vault, and names the realms in force (data.Writers()).
export const REALMS = {
  home: `gno.land/r/${NS}/home/v1`,
  catalog: `gno.land/r/${NS}/catalog/v1`,
  radio: `gno.land/r/${NS}/radio/v1`,
  tickets: `gno.land/r/${NS}/tickets/v1`,
  data: `gno.land/r/${NS}/data`,
  nft: `gno.land/r/${NS}/tickets/nft`,
} as const;

/** SAFE screens dedications (p/<NS>/safe); the app asks it before signing. */
export const SAFE = `gno.land/p/${NS}/safe/v0` as const;
