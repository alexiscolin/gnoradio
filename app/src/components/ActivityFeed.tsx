import { gnot } from "../lib/format";
import { useNames } from "../lib/names";
import type { Activity, Catalog, Navigate } from "../lib/types";
import { type Glyph, Shape } from "./Shapes";
import { Who } from "./common";

const GLYPH: Record<Activity["kind"], Glyph> = {
  like: "circle",
  follow: "quarter",
  tip: "square",
  support: "square",
  queue: "quarter",
  curator: "quarter",
  sponsored: "quarter",
  claim: "quarter",
  publish: "triangle",
  album: "triangle",
  playlist: "triangle",
};

/** ago is how long ago a unix time was: 42s, 5m, 3h, 2d. */
export function ago(at: number, now: number): string {
  const s = Math.max(0, Math.round(now - at));
  if (s < 60) return `${String(s)}s`;
  if (s < 3600) return `${String(Math.floor(s / 60))}m`;
  if (s < 86400) return `${String(Math.floor(s / 3600))}h`;
  return `${String(Math.floor(s / 86400))}d`;
}

type Target = Parameters<Navigate>[0];

/** A feed line's parts: what it is about (the title, first), what happened, where. */
export interface Line {
  readonly title: string;
  readonly verb: string;
  readonly station: string;
  readonly target?: Target | undefined;
}

/** activityLine words one activity; null when what it points at is unknown (hidden or not loaded), so the row is left out. */
export function activityLine(a: Activity, cat: Catalog): Line | null {
  const t = cat.byId.get(a.track);
  const artist = cat.artists.get(a.artist ?? t?.artist ?? 0);
  const onAir = a.kind === "queue" || a.kind === "curator" || a.kind === "sponsored" || a.kind === "tip";
  const station = onAir && a.station !== undefined ? cat.stations.find((s) => s.id === a.station)?.name ?? "" : "";
  const track = (verb: string): Line | null => (t ? { title: t.title, verb, station, target: { k: "track", id: t.id } } : null);
  switch (a.kind) {
    case "like": return track("Liked");
    case "tip": return track(`Tipped ${gnot(a.amount ?? 0)}`);
    case "queue": return track("Picked");
    case "curator": return track("Programmed");
    case "sponsored": return track("Free pick");
    case "publish": return track("Published");
    case "support": return { title: "GnoRadio", verb: `Supported with ${gnot(a.amount ?? 0)}`, station: "", target: { k: "community" } };
    case "follow": return artist ? { title: artist.name, verb: "Followed", station: "", target: { k: "artist", id: artist.id } } : null;
    case "claim": return artist ? { title: artist.name, verb: "Profile verified", station: "", target: { k: "artist", id: artist.id } } : null;
    case "album": {
      const al = cat.albums.find((x) => x.id === a.track);
      return al ? { title: al.title, verb: "New album", station: "", target: { k: "album", id: al.id } } : null;
    }
    case "playlist": {
      const pl = cat.playlists.find((x) => x.id === a.track);
      return pl ? { title: pl.title, verb: "New playlist", station: "", target: { k: "playlist", id: pl.id } } : null;
    }
  }
}

/** FeedItem is one feed row: the title in bold, then "<verb> by <who> · <station> · <when>" under it. */
export function FeedItem({ g, line, by, shown, go, when }: {
  readonly g: Glyph;
  readonly line: Line;
  readonly by: string;
  readonly shown: (a: string) => string;
  readonly go: Navigate;
  readonly when: string;
}) {
  const { target } = line;
  return (
    <li>
      <Shape g={g} size={12} />
      <span className="feed-main">
        {target ? <button className="feed-title" onClick={() => { go(target); }}>{line.title}</button> : <b className="feed-title">{line.title}</b>}
        <span className="feed-by">
          {line.verb} by <Who address={by} shown={shown} go={go} />{line.station && ` · ${line.station}`} · <span className="mono">{when}</span>
        </span>
      </span>
    </li>
  );
}

/** ActivityFeed is the community pulse: every row is a transaction anyone can verify. */
export function ActivityFeed({ items, cat, go, now, compact = false }: {
  readonly items: readonly Activity[];
  readonly cat: Catalog;
  readonly go: Navigate;
  readonly now: number;
  readonly compact?: boolean;
}) {
  const shown = useNames(items.map((a) => a.by));
  const rows = items.flatMap((a) => { const line = activityLine(a, cat); return line ? [{ a, line }] : []; });
  if (rows.length === 0) return <p className="muted">No activity yet. Be the first: like, tip or pick a track.</p>;
  return (
    <ol className={`feed lines${compact ? " compact" : ""}`}>
      {rows.map(({ a, line }, idx) => (
        <FeedItem key={`${String(idx)}-${a.kind}-${String(a.at)}-${a.by}-${String(a.track)}`} g={GLYPH[a.kind]} line={line} by={a.by} shown={shown} go={go} when={ago(a.at, now)} />
      ))}
    </ol>
  );
}
