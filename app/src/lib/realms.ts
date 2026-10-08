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

// The release of the rules realms in force. VITE_RULES_VERSION names it (v1 by default) and
// VITE_RULES_FROM, if set, the unix time it takes over (data.Writers() "at"): before that the
// previous one is in force, so the site switches on its own at the release's hour (docs/DEPLOY.md).
// data is permanent: it holds every record and the promo vault, and names the realms in force.
const env = (name: string): string | undefined =>
  // eslint-disable-next-line @typescript-eslint/no-unnecessary-condition
  unset(import.meta.env === undefined ? undefined : (import.meta.env as Record<string, string | undefined>)[name]) ?? unset(runtimeEnv(name));
const RELEASE = env("VITE_RULES_VERSION") ?? "v1";
const FROM = Number(env("VITE_RULES_FROM") ?? 0);
/** rulesVersion is the release in force at unix time now (seconds). */
export function rulesVersion(now = Date.now() / 1000): string {
  const n = Number(RELEASE.slice(1));
  return FROM > 0 && now < FROM && n > 1 ? `v${String(n - 1)}` : RELEASE;
}
const rules = (role: string): `gno.land/r/${string}` => `gno.land/r/${NS}/${role}/${rulesVersion()}`;
// Getters: a page (or a warm function) open across the takeover reads the release in force.
export const REALMS = {
  get home() { return rules("home"); },
  get catalog() { return rules("catalog"); },
  get radio() { return rules("radio"); },
  get tickets() { return rules("tickets"); },
  data: `gno.land/r/${NS}/data` as const,
  nft: `gno.land/r/${NS}/tickets/nft` as const,
};

/** SAFE screens dedications (p/<NS>/safe); the app asks it before signing. */
export const SAFE = `gno.land/p/${NS}/safe/v0` as const;
