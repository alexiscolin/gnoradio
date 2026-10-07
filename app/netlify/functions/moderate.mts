// The app pings this right after a dedication so it is judged within seconds
// (netlify/moderation.ts). Only this site may call it, at most one run every
// few seconds per instance; the schedule (moderate-cron.mts) catches the rest.
// The OpenAI key never leaves the server: no logs, generic errors.
import { sameSite } from "../bot";
import { moderatePending } from "../moderation";

const COOLDOWN_MS = 3000;
let lastRun = 0;

export default async (req: Request): Promise<Response> => {
  if (req.method !== "POST") return Response.json({ error: "POST only" }, { status: 405 });
  if (!sameSite(req)) return Response.json({ error: "forbidden" }, { status: 403 });
  const key = process.env["OPENAI_API_KEY"];
  if (!key) return Response.json({ checked: 0, note: "moderation is not configured on this server" });
  if (Date.now() - lastRun < COOLDOWN_MS) return Response.json({ checked: 0, note: "a run just happened; the schedule follows up" });
  lastRun = Date.now();
  try {
    return Response.json(await moderatePending(key));
  } catch {
    return Response.json({ error: "moderation failed" }, { status: 502 });
  }
};

export const config = { path: "/api/moderate" };
