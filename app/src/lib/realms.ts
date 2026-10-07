// GnoRadio's realm paths, shared by the app (gno.ts) and the robot
// (netlify/). A version upgrade edits this file only.
//
// NS is where the packages live: "gnoradio" on a local devnet, the deployer's
// namespace on a public chain (tools/deploy/stage.py). VITE_GNORADIO_NS is
// inlined in the app at build time and read from the environment by the robot.
const fromEnv = (globalThis as { process?: { env: Record<string, string | undefined> } }).process?.env["VITE_GNORADIO_NS"];
// import.meta.env exists in the app (Vite inlines it) but not in the robot's Node runtime.
// eslint-disable-next-line @typescript-eslint/no-unnecessary-condition
const NS: string = (import.meta.env === undefined ? undefined : import.meta.env.VITE_GNORADIO_NS) ?? fromEnv ?? "gnoradio";

export const REALMS = {
  home: `gno.land/r/${NS}/home/v0`,
  catalog: `gno.land/r/${NS}/catalog/v0`,
  radio: `gno.land/r/${NS}/radio/v0`,
  tickets: `gno.land/r/${NS}/tickets/v0`,
} as const;

/** SAFE screens dedications (p/<NS>/safe); the app asks it before signing. */
export const SAFE = `gno.land/p/${NS}/safe/v0` as const;
