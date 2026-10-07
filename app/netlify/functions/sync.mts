// Optional (SYNC_ROBOT=on): keeps the smart flow going when nobody picks.
// Every 30 minutes the robot asks the chain,
// for free, whether radio.Sync has work (new tracks, or less than an hour of
// Main's flow left; listener picks top the flow up on their own). Only then
// does it pay for a Sync: about 0.02 GNOT, a few times a day when nobody picks.
import { botCall, provider } from "../bot";

const RADIO = "gno.land/r/gnoradio/radio/v0";

export default async (): Promise<Response> => {
  // Off unless SYNC_ROBOT=on: listener picks already keep the radio fed for free.
  if (process.env["SYNC_ROBOT"] !== "on") return Response.json({ sent: false, enabled: false });
  const p = await provider();
  if (!(await p.evaluateExpression(RADIO, "NeedsSync()")).startsWith("(true")) return Response.json({ sent: false, needed: false });
  return Response.json({ sent: await botCall(p, RADIO, "Sync", ["20"], 20_000_000n), needed: true });
};

export const config = { schedule: "*/30 * * * *" };
