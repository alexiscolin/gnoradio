// The dedication moderation run, shared by the app's ping (functions/moderate.mts)
// and the every-minute schedule (functions/moderate-cron.mts) that catches
// dedications sent outside the app. It reads the pending dedications from the
// chain itself, asks OpenAI's moderation model and hides what crosses the
// thresholds (src/lib/moderation.ts) with radio.HideNote. A dedication waits
// radio.noteGrace (90 s) before it shows, longer than the schedule's interval.
import { botCall, provider } from "./bot";
import { verdict } from "../src/lib/moderation";
import { unquote } from "../src/lib/proof";

const RADIO = "gno.land/r/gnoradio/radio/v0";
const MAX_BATCH = 32; // dedications per OpenAI call

interface Pending { station: number; start: number; note: string }

// Dedications already judged clean or hidden by this instance: each is sent to
// OpenAI once. A failed hide is not recorded, so the next run retries it.
const seen = new Set<string>();

export async function moderatePending(key: string): Promise<{ checked: number; hidden: string[]; status?: number }> {
  const p = await provider();
  const all = JSON.parse(unquote(await p.evaluateExpression(RADIO, "PendingNotesJSON()"))) as Pending[];
  const pending = all.filter((n) => !seen.has(`${String(n.station)}/${String(n.start)}`)).slice(0, MAX_BATCH);
  if (pending.length === 0) return { checked: 0, hidden: [] };
  const r = await fetch("https://api.openai.com/v1/moderations", {
    method: "POST",
    headers: { authorization: `Bearer ${key}`, "content-type": "application/json" },
    body: JSON.stringify({ model: "omni-moderation-latest", input: pending.map((n) => n.note) }),
    signal: AbortSignal.timeout(8000),
  });
  // Rate-limited or down: the dedications keep their grace and the next run retries.
  if (!r.ok) return { checked: 0, hidden: [], status: r.status };
  const results = ((await r.json()) as { results?: { category_scores: Record<string, number> }[] }).results ?? [];
  const hidden: string[] = [];
  for (const [i, n] of pending.entries()) {
    const id = `${String(n.station)}/${String(n.start)}`;
    const reason = verdict(results[i]?.category_scores ?? {});
    try {
      if (reason && !(await botCall(p, RADIO, "HideNote", [String(n.station), String(n.start), reason], 40_000_000n))) continue;
    } catch {
      continue; // out of gas, sequence clash, daily cap: retried on the next run
    }
    seen.add(id);
    if (reason) hidden.push(id);
  }
  if (seen.size > 2000) seen.clear();
  return { checked: pending.length, hidden };
}
