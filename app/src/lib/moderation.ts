// Thresholds of the dedication moderation robot (netlify/functions/moderate.mts),
// on the per-category scores of OpenAI's moderation model. Strict where the harm
// is severe, lenient for mild language, so "kick-ass party" stays on air. Pure:
// no Vite env here.
const LIMITS: Readonly<Record<string, number>> = {
  "sexual/minors": 0.1,
  "hate/threatening": 0.2,
  "self-harm/intent": 0.2,
  "self-harm/instructions": 0.2,
  "harassment/threatening": 0.3,
  "self-harm": 0.3,
  "illicit/violent": 0.3,
  hate: 0.4,
  "violence/graphic": 0.5,
  harassment: 0.8,
  illicit: 0.8,
  sexual: 0.85,
  violence: 0.85,
};

/** verdict is the first category over its limit, the reason a dedication is hidden ("" keeps it). */
export function verdict(scores: Readonly<Record<string, number>>): string {
  return Object.keys(LIMITS).find((k) => (scores[k] ?? 0) > (LIMITS[k] ?? 1)) ?? "";
}
