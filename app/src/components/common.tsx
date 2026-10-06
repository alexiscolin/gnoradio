import type { ReactNode } from "react";
import { clock, licenseLabel } from "../lib/format";
import type { Track } from "../lib/types";
import type { Player } from "../player/usePlayer";
import { Cover } from "./Cover";

export function Head({ a, b, note, right }: { readonly a: string; readonly b?: string; readonly note?: string; readonly right?: ReactNode }) {
  return (
    <div className="head">
      <div>
        <h2>
          {a} {b !== undefined && <span>{b}</span>}
        </h2>
        {note !== undefined && <p className="muted">{note}</p>}
      </div>
      {right}
    </div>
  );
}

export function Count({ label, value }: { readonly label: string; readonly value: number | string }) {
  return (
    <span className="count">
      <span className="muted small">{label}</span>
      <b>{value}</b>
    </span>
  );
}

/** BigList is the huge-type list of the design (stations, genres, playlists). */
export function BigList({ items, compact = false }: {
  readonly items: readonly { key: string | number; label: string; count?: number | string; dim?: boolean; live?: boolean; onClick: () => void }[];
  readonly compact?: boolean;
}) {
  return (
    <div className={`biglist${compact ? " compact" : ""}`}>
      {items.map((it) => (
        <button key={it.key} className={it.dim ? "dim" : ""} onClick={it.onClick}>
          {it.label}
          {it.count !== undefined && <sup>({it.count})</sup>}
          {it.live && (<><i className="dot" aria-hidden="true" /><span className="sr"> playing now</span></>)}
        </button>
      ))}
    </div>
  );
}

/** TrackRows lists tracks; clicking one plays the list from there. */
export function TrackRows({ tracks, player }: { readonly tracks: readonly Track[]; readonly player: Player }) {
  const ids = tracks.map((t) => t.id);
  return (
    <div className="rows">
      {tracks.map((t, i) => (
        <button key={t.id} className={`track${player.current === t.id ? " on" : ""}`} onClick={() => { player.playList(ids, i); }}>
          <span className="mono muted">{String(i + 1).padStart(2, "0")}</span>
          <Cover t={t} size="40px" />
          <span className="tt">
            <b>{t.title}</b>
            <span className="muted">{t.artistName} · {t.origin === "audius" ? "Audius" : licenseLabel(t.license)}</span>
          </span>
          <span className="muted">♥ {t.likes}</span>
          <span className="mono">{clock(t.duration)}</span>
        </button>
      ))}
    </div>
  );
}

export function TrackCards({ tracks, player, meta }: { readonly tracks: readonly Track[]; readonly player: Player; readonly meta: (t: Track) => string }) {
  const ids = tracks.map((t) => t.id);
  return (
    <div className="grid">
      {tracks.map((t, i) => (
        <button key={t.id} className="card" onClick={() => { player.playList(ids, i); }}>
          <Cover t={t} />
          <b>{t.title}</b>
          <span className="muted">{meta(t)}</span>
        </button>
      ))}
    </div>
  );
}
