// GnoRadio's realm paths, shared by the app (gno.ts) and the robot
// (netlify/). Pure: no Vite env here. A version upgrade edits this file only.

export const REALMS = {
  catalog: "gno.land/r/gnoradio/catalog/v0",
  radio: "gno.land/r/gnoradio/radio/v0",
  tickets: "gno.land/r/gnoradio/tickets/v0",
} as const;

/** SAFE screens dedications (p/gnoradio/safe); the app asks it before signing. */
export const SAFE = "gno.land/p/gnoradio/safe/v0";
