import { gnot, shortAddr } from "../lib/format";
import type { Activity, Catalog, Navigate } from "../lib/types";
import { type Glyph, Shape } from "./Shapes";

const GLYPH: Record<Activity["kind"], Glyph> = {
  like: "circle",
  follow: "circle",
  tip: "square",
  support: "square",
  queue: "quarter",
  curator: "quarter",
  claim: "quarter",
  publish: "triangle",
  album: "triangle",
  playlist: "triangle",
};

function ago(at: number, now: number): string {
  const s = Math.max(0, Math.round(now - at));
  if (s < 60) return `${String(s)}s`;
  if (s < 3600) return `${String(Math.floor(s / 60))}m`;
  if (s < 86400) return `${String(Math.floor(s / 3600))}h`;
  return `${String(Math.floor(s / 86400))}d`;
}

/** ActivityFeed is the community pulse: every row is a transaction anyone can verify. */
export function ActivityFeed({ items, cat, go, now, compact = false }: {
  readonly items: readonly Activity[];
  readonly cat: Catalog;
  readonly go: Navigate;
  readonly now: number;
  readonly compact?: boolean;
}) {
  if (items.length === 0) return <p className="muted">No activity yet. Be the first: like, tip or queue a track.</p>;
  return (
    <ol className={`feed${compact ? " compact" : ""}`}>
      {items.map((a, idx) => {
        const isTrack = a.kind === "like" || a.kind === "tip" || a.kind === "queue" || a.kind === "curator" || a.kind === "publish";
        const t = isTrack ? cat.byId.get(a.track) : undefined;
        const who = cat.artists.get(t?.artist ?? 0);
        const artistName = cat.artists.get(a.artist ?? 0)?.name ?? who?.name ?? "an artist";
        const title = t?.title ?? "a track";
        const station = cat.stations.find((s) => s.id === a.station)?.name ?? "the radio";
        const target = ((): Parameters<Navigate>[0] | undefined => {
          if (t) return { k: "track", id: t.id };
          if (a.kind === "playlist" && a.track) return { k: "playlist", id: a.track };
          if (a.kind === "album" && a.track) return { k: "album", id: a.track };
          if ((a.kind === "follow" || a.kind === "claim") && a.artist) return { k: "artist", id: a.artist };
          if (a.kind === "support") return { k: "community" };
          return undefined;
        })();
        const open = () => { if (target) go(target); };
        let text: string;
        switch (a.kind) {
          case "tip": text = `tipped ${gnot(a.amount ?? 0)} to ${artistName}`; break;
          case "support": text = `supported GnoRadio with ${gnot(a.amount ?? 0)}`; break;
          case "like": text = `liked ${title}`; break;
          case "follow": text = `followed ${artistName}`; break;
          case "queue": text = `queued ${title} on ${station}`; break;
          case "curator": text = `programmed ${title} on ${station}`; break;
          case "publish": text = `published ${title}`; break;
          case "album": text = "released an album"; break;
          case "playlist": text = "shared a playlist"; break;
          case "claim": text = `${artistName} claimed their profile`; break;
        }
        return (
          <li key={`${String(idx)}-${a.kind}-${String(a.at)}-${a.by}-${String(a.track)}`}>
            <Shape g={GLYPH[a.kind]} size={12} />
            <button className="feed-txt" onClick={open} disabled={!target}>
              <span className="mono who">{shortAddr(a.by)}</span> {text}
            </button>
            <span className="mono muted">{ago(a.at, now)}</span>
          </li>
        );
      })}
    </ol>
  );
}
