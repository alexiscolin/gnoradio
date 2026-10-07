// Thresholds of the dedication moderation robot (netlify/functions/dedication.mts),
// on the per-category scores of OpenAI's moderation model. Strict where the harm
// is severe, lenient for mild language, so "kick-ass party" stays on air. Tuned on a
// 70-text corpus (2026-10-07): with the word filter first, 33 of 40 abusive texts
// refused and none of 30 everyday dedications. Pure:
// no Vite env here.

/** MAX_NOTE is a dedication's length cap (radio maxNote), the same in the app and the robot. */
export const MAX_NOTE = 40;
/** DOWN is what a listener reads when the robot cannot judge a dedication. */
export const DOWN = "Dedications are paused right now. Your pick can still go on air without one.";

const LIMITS: Readonly<Record<string, number>> = {
  "sexual/minors": 0.1,
  "hate/threatening": 0.2,
  "self-harm/intent": 0.2,
  "self-harm/instructions": 0.2,
  "harassment/threatening": 0.25,
  "self-harm": 0.3,
  "illicit/violent": 0.3,
  hate: 0.25,
  "violence/graphic": 0.5,
  harassment: 0.45,
  illicit: 0.8,
  sexual: 0.6,
  violence: 0.85,
};

/** verdict is the first category over its limit, the reason a dedication is refused ("" passes it). */
export function verdict(scores: Readonly<Record<string, number>>): string {
  return Object.keys(LIMITS).find((k) => (scores[k] ?? 0) > (LIMITS[k] ?? 1)) ?? "";
}

/** dedicationCertificate asks the robot to judge a dedication; it throws the reason shown to the listener. */
export async function dedicationCertificate(note: string, author: string, station: number): Promise<{ expires: number; sig: string }> {
  // The certificate is bound to this listener and station (radio.NoteMessage): nobody can reuse it elsewhere.
  const r = await fetch("/api/dedication", { method: "POST", headers: { "content-type": "application/json" }, body: JSON.stringify({ note, author, station }) }).catch(() => null);
  const body = ((await r?.json().catch(() => null)) ?? {}) as { expires?: number; sig?: string; error?: string };
  if (r?.ok && body.sig && body.expires) return { expires: body.expires, sig: body.sig };
  // Only the robot's own sentences reach the listener (a refused text, too many tries); anything else is "paused".
  throw new Error(r && (r.status === 422 || r.status === 429) && body.error ? body.error : DOWN);
}
