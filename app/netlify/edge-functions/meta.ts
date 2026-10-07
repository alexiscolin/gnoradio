// Optional link previews per page (off by default: see netlify.toml). Preview
// bots (WhatsApp, X, Discord…) do not run JavaScript, so for a shared artist,
// track, album or playlist this reads its name on-chain and writes it into the
// page's title and Open Graph tags. Everyone else gets the page untouched.
import { unquote } from "../../src/lib/proof";

const BOTS = /bot|crawler|spider|facebookexternalhit|whatsapp|telegram|slack|discord|linkedin|embedly|pinterest|skype|vkshare/i;
const CATALOG = "gno.land/r/gnoradio/catalog/v0";
const READ: Readonly<Record<string, string>> = { artist: "ArtistJSON", track: "TrackJSON", album: "AlbumJSON", playlist: "PlaylistJSON" };

interface Named { name?: string; title?: string; artistName?: string; bio?: string }

async function named(kind: string, id: string): Promise<Named | null> {
  const fn = READ[kind];
  if (!fn) return null;
  const rpc = Netlify.env.get("VITE_WALLET_RPC") ?? "https://rpc.onyx.testnets.gno.land:443";
  const r = await fetch(rpc, {
    method: "POST",
    headers: { "content-type": "application/json" },
    body: JSON.stringify({ jsonrpc: "2.0", id: 1, method: "abci_query", params: { path: "vm/qeval", data: btoa(`${CATALOG}.${fn}(${id})`) } }),
    signal: AbortSignal.timeout(3000),
  });
  const data = ((await r.json()) as { result?: { response?: { ResponseBase?: { Data?: string } } } }).result?.response?.ResponseBase?.Data;
  return data ? (JSON.parse(unquote(atob(data))) as Named) : null;
}

const esc = (s: string) => s.replace(/[&<>"]/g, (c) => `&#${String(c.charCodeAt(0))};`);

function setMeta(html: string, title: string, description: string, url: string): string {
  return html
    .replace(/<title>[^<]*<\/title>/, `<title>${esc(title)}</title>`)
    .replace(/(<meta (?:name|property)="(?:og:title|twitter:title)" content=")[^"]*"/g, `$1${esc(title)}"`)
    .replace(/(<meta (?:name|property)="(?:description|og:description|twitter:description)" content=")[^"]*"/g, `$1${esc(description)}"`)
    .replace(/(<meta property="og:url" content=")[^"]*"/, `$1${esc(url)}"`);
}

export default async (req: Request, context: { next: () => Promise<Response> }): Promise<Response> => {
  const page = await context.next();
  if (!BOTS.test(req.headers.get("user-agent") ?? "")) return page;
  const [, kind = "", arg = ""] = new URL(req.url).pathname.split("/");
  const id = /(\d+)$/.exec(arg)?.[1];
  try {
    const n = id === undefined ? null : await named(kind, id);
    const name = n?.title ?? n?.name;
    if (!name) return page;
    const by = n?.artistName ? ` · ${n.artistName}` : "";
    const bio = n?.bio ?? "";
    const description = bio !== "" ? bio : `Listen to ${name}${by} on GnoRadio, the community radio on gno.land. 100% of tips go to the artist.`;
    // The body changed: drop the original length and validators.
    const headers = new Headers(page.headers);
    for (const h of ["content-length", "etag", "last-modified"]) headers.delete(h);
    return new Response(setMeta(await page.text(), `${name}${by} · GnoRadio`, description.slice(0, 200), req.url), { status: page.status, headers });
  } catch {
    return page;
  }
};
