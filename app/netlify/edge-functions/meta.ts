// Per-page link previews (paths in netlify.toml). Preview bots (WhatsApp, X,
// Discord…) do not run JavaScript, so for a shared track, artist, album,
// playlist, station, listener or concert this reads it on-chain (cards.ts) and
// writes it into the page's title and Open Graph tags, with its own image
// (functions/og.mts). Everyone else gets the page untouched.
import { cardOf, version } from "../cards";
import { serverRPC } from "../../src/lib/network";
import { esc } from "../../src/lib/format";

const BOTS = /bot|crawler|spider|facebookexternalhit|whatsapp|telegram|slack|discord|linkedin|embedly|pinterest|skype|vkshare|mastodon|bluesky|iframely/i;


/** setTag writes content into the meta tags named; replacer functions, not strings: a chain name holding $1 or $` stays text. */
const setTag = (html: string, names: string, content: string) =>
  html.replace(new RegExp(`(<meta (?:name|property)="(?:${names})" content=")[^"]*"`, "g"), (_m, p1: string) => `${p1}${esc(content)}"`);

export default async (req: Request, context: { next: () => Promise<Response> }): Promise<Response> => {
  const page = await context.next();
  if (!BOTS.test(req.headers.get("user-agent") ?? "")) return page;
  const url = new URL(req.url);
  try {
    const c = await cardOf(serverRPC(), url.pathname);
    if (!c?.title) return page;
    const image = `${url.origin}/og${c.path}.png?v=${version(c)}`;
    let html = (await page.text()).replace(/<title>[^<]*<\/title>/, () => `<title>${esc(c.page)}</title>`);
    html = setTag(html, "og:title|twitter:title", c.page);
    html = setTag(html, "description|og:description|twitter:description", c.description.slice(0, 200));
    html = setTag(html, "og:url", req.url);
    html = setTag(html, "og:image|twitter:image", image);
    html = setTag(html, "og:image:alt|twitter:image:alt", c.alt);
    // The body changed: drop the original length and validators.
    const headers = new Headers(page.headers);
    for (const h of ["content-length", "etag", "last-modified"]) headers.delete(h);
    return new Response(html, { status: page.status, headers });
  } catch {
    return page;
  }
};
