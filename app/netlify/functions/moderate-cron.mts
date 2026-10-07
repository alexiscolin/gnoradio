// Every minute: moderates dedications sent outside the app (gnokey, direct
// transactions), which never ping /api/moderate. Reading the chain is free;
// it pays only to hide. Off without OPENAI_API_KEY.
import { moderatePending } from "../moderation";

export default async (): Promise<Response> => {
  const key = process.env["OPENAI_API_KEY"];
  if (!key) return Response.json({ checked: 0 });
  try {
    return Response.json(await moderatePending(key));
  } catch {
    return Response.json({ error: "moderation failed" }, { status: 502 });
  }
};

export const config = { schedule: "* * * * *" };
