// Dedications are judged before they reach the chain: the app sends the text
// here first; if the word filter (safe.Note) and OpenAI's moderation model
// (src/lib/moderation.ts) both pass it, the robot signs a short-lived
// certificate for that exact text, listener and station (radio.NoteMessage),
// and the listener sends it with radio.QueueWithNote, paying their own gas. The realm refuses a
// dedication without one, so GnoRadio pays nothing and nothing waits on air.
// The OpenAI key never leaves the server: no logs, generic errors.
import { provider, readBody, refuse, reply, signCertificate } from "../bot";
import { DOWN, MAX_NOTE, verdict } from "../../src/lib/moderation";
import { isAddress, unquote } from "../../src/lib/proof";
import { REALMS, SAFE } from "../../src/lib/realms";

const CERT_LIFE = 600; // seconds; the realm accepts at most 15 minutes
const REPHRASE = "Please rephrase your dedication.";

export default async (req: Request): Promise<Response> => {
  // A listener sends one note per pick; retries after a rephrase stay well under this.
  const no = refuse(req, 6);
  if (no) return no;
  let note = "", author = "", station = -1;
  const body = (await readBody(req)) as { note?: unknown; author?: unknown; station?: unknown } | null;
  if (!body || typeof body !== "object") return reply(400, { error: "invalid request" });
  note = typeof body.note === "string" ? body.note : "";
  author = typeof body.author === "string" ? body.author : "";
  station = typeof body.station === "number" && Number.isInteger(body.station) ? body.station : -1;
  if (note === "" || note.length > 4 * MAX_NOTE || !isAddress(author) || station < 0 || station > 1000) return reply(400, { error: "invalid request" });
  // Emoji and broken characters (lone UTF-16 halves) are not plain text: refuse them here, before they reach a Gno expression.
  if (/[\uD800-\uDFFF]/.test(note)) return reply(422, { error: "Dedication: letters, digits and . , ! ? ¡ ¿ ' - only." });
  const key = process.env["OPENAI_API_KEY"];
  // Local development without a key: only the word filter judges (never in production).
  if (!key && process.env["NETLIFY_DEV"] !== "true") return reply(503, { error: DOWN });

  try {
    const p = await provider();
    // The realm's own filter first: free, and its reason is the most precise.
    const why = unquote(await p.evaluateExpression(SAFE, `Note(${JSON.stringify(note)}, ${String(MAX_NOTE)})`));
    if (why) return reply(422, { error: `Dedication: ${why}.` });
    if (key) {
      const r = await fetch("https://api.openai.com/v1/moderations", {
        method: "POST",
        headers: { authorization: `Bearer ${key}`, "content-type": "application/json" },
        body: JSON.stringify({ model: "omni-moderation-latest", input: note }),
        signal: AbortSignal.timeout(8000),
      });
      if (!r.ok) return reply(503, { error: DOWN });
      const scores = ((await r.json()) as { results?: { category_scores: Record<string, number> }[] }).results?.[0]?.category_scores;
      if (!scores) return reply(503, { error: DOWN });
      if (verdict(scores)) return reply(422, { error: REPHRASE });
    }

    const expires = Math.floor(Date.now() / 1000) + CERT_LIFE;
    const message = unquote(await p.evaluateExpression(REALMS.radio, `NoteMessage(${JSON.stringify(author)}, ${String(station)}, ${JSON.stringify(note)}, ${String(expires)})`));
    const sig = message ? await signCertificate(message) : "";
    if (!sig) return reply(503, { error: DOWN });
    return reply(200, { expires, sig });
  } catch {
    return reply(503, { error: DOWN });
  }
};

export const config = { path: "/api/dedication" };
