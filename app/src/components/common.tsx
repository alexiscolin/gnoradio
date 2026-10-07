import { withRef } from "../lib/incentives";
import { Icon } from "./Icons";
import { type ReactNode, useState } from "react";
import { clock, licenseLabel } from "../lib/format";
import { viewToPath } from "../lib/router";
import type { Saved } from "../lib/saved";
import type { Navigate, Track, View } from "../lib/types";
import type { Actions } from "../player/useActions";
import type { Player } from "../player/usePlayer";
import { Cover } from "./Cover";
import { type Glyph, Shape } from "./Shapes";

export function Head({ a, b, note, right }: { readonly a: string; readonly b?: string; readonly note?: ReactNode; readonly right?: ReactNode }) {
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
  readonly items: readonly { key: string | number; label: string; count?: number | string; dim?: boolean; live?: boolean; empty?: boolean; pressed?: boolean; onClick: () => void }[];
  readonly compact?: boolean;
}) {
  return (
    <div className={`biglist${compact ? " compact" : ""}`}>
      {items.map((it) => (
        <button key={it.key} className={it.empty ? "empty" : it.dim ? "dim" : it.live ? "on" : ""} disabled={it.empty} aria-pressed={it.pressed} onClick={it.onClick}>
          {it.label}
          {it.empty ? <sup>(empty)</sup> : it.count !== undefined && <sup>({it.count})</sup>}
          {it.live && (<><i className="dot" aria-hidden="true" /><span className="sr"> playing now</span></>)}
        </button>
      ))}
    </div>
  );
}

/** TrackRows lists tracks; clicking one plays the list from there. */
const ROWS_PAGE = 100;

/** rightsLabel is how a track's rights read in a list. */
export const rightsLabel = (t: Track): string => (t.origin === "audius" ? "Audius" : licenseLabel(t.license));

/** sharedValue is the value every track has in common, or "" when they differ. */
export function sharedValue(tracks: readonly Track[], of: (t: Track) => string): string {
  const first = tracks[0] ? of(tracks[0]) : "";
  return tracks.every((t) => of(t) === first) ? first : "";
}

/**
 * TrackRows lists tracks to play in order. What all rows share (one artist,
 * one license, as in an album) is said once by the page, not on every row.
 */
export function TrackRows({ tracks, player, actions, saved }: { readonly tracks: readonly Track[]; readonly player: Player; readonly actions: Actions; readonly saved: Saved }) {
  const ids = tracks.map((t) => t.id);
  const oneArtist = sharedValue(tracks, (t) => t.artistName) !== "";
  const oneRights = sharedValue(tracks, rightsLabel) !== "";
  // Long lists render 100 rows at a time (each row may fetch its cover); play still uses the whole list.
  const [shown, setShown] = useState(ROWS_PAGE);
  const left = tracks.length - shown;
  return (
    <div className="rows">
      {tracks.slice(0, shown).map((t, i) => {
        const like = likeState(t, actions);
        const kept = saved.has(t.id);
        return (
          // The play button covers the whole row (::after); like and save sit above it.
          <div key={t.id} className={`track${player.current === t.id ? " on" : ""}`}>
            <button className="track-play" onClick={() => { player.playList(ids, i); }}>
              <span className="mono muted num">
                {player.current === t.id && player.playing
                  ? <i className="eq" aria-label="Playing"><i /><i /><i /></i>
                  : String(i + 1).padStart(2, "0")}
              </span>
              <Cover t={t} size="40px" />
              <span className="tt">
                <b>{t.title}</b>
                {!(oneArtist && oneRights) && <span className="muted">{[oneArtist ? "" : t.artistName, oneRights ? "" : rightsLabel(t)].filter(Boolean).join(" · ")}</span>}
              </span>
            </button>
            <span className="muted likes">{t.likes > 0 && `♥ ${String(t.likes)}`}</span>
            <span className="row-acts">
              <button className="row-act like" aria-pressed={like.on} aria-busy={like.busy} disabled={like.busy} aria-label={`Like ${t.title}`} title={`${like.on ? "Unlike" : "Like"} · public, on-chain`} onClick={like.toggle}>
                <Icon name={like.on ? "heart-on" : "heart"} size={16} />
              </button>
              <button className="row-act" aria-pressed={kept} aria-label={`Save ${t.title}`} title={kept ? "Saved in this browser" : "Save in this browser"} onClick={() => { saved.toggle(t.id); }}>
                <Icon name={kept ? "bookmark-on" : "bookmark"} size={16} />
              </button>
            </span>
            <span className="mono">{clock(t.duration)}</span>
          </div>
        );
      })}
      {left > 0 && (
        <button className="more" onClick={() => { setShown((n) => n + ROWS_PAGE); }}>
          Show {String(Math.min(ROWS_PAGE, left))} more <span className="muted">· {String(left)} left</span>
        </button>
      )}
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

/** Proof links a screen to its twin page on gnoweb and to the code behind it. */
export function Proof({ page, code }: { readonly page: string; readonly code: string }) {
  return (
    <p className="proof">
      <a href={page} target="_blank" rel="noreferrer">View on gno.land <Icon name="external" size={12} className="nudge-out" /></a>
      <span aria-hidden="true"> · </span>
      <a href={code} target="_blank" rel="noreferrer">Read the code <Icon name="external" size={12} className="nudge-out" /></a>
    </p>
  );
}

const ONCHAIN = "Public, on-chain · opens Adena";

/** likeState is whether this wallet likes a track, whether it is signing, and the toggle (no wallet: the wallet sheet). */
function likeState(t: Track, actions: Actions) {
  const on = actions.liked.has(t.id);
  return { on, busy: actions.pending === `like:${String(t.id)}`, toggle: () => { if (on) actions.unlike(t); else actions.like(t); } };
}

/** LikeButton signs Like or Unlike; it shows the wallet's state and a pending one. */
export function LikeButton({ t, actions }: { readonly t: Track; readonly actions: Actions }) {
  const { on, busy, toggle } = likeState(t, actions);
  return (
    <button
      className={`onchain${busy ? " busy" : ""}`}
      aria-pressed={on}
      aria-busy={busy}
      disabled={busy}
      title={`${on ? "Unlike" : "Like"} · public, on-chain · the first like locks about 0.3 GNOT of storage deposit; Unlike frees it`}
      onClick={toggle}
    >
      <Icon name={on ? "heart-on" : "heart"} size={15} />
      {busy ? " Signing…" : ` ${on ? "Liked" : "Like"}${t.likes > 0 ? ` ${String(t.likes)}` : ""}`}
    </button>
  );
}

/** FollowButton signs Follow or Unfollow for an artist. */
export function FollowButton({ artist, followers, actions }: { readonly artist: number; readonly followers: number; readonly actions: Actions }) {
  const on = actions.following.has(artist);
  const busy = actions.pending === `follow:${String(artist)}`;
  return (
    <button
      className={`onchain${busy ? " busy" : ""}`}
      aria-pressed={on}
      aria-busy={busy}
      disabled={busy}
      title={`${on ? "Unfollow" : "Follow"} · ${ONCHAIN}`}
      onClick={() => { if (on) actions.unfollow(artist); else actions.follow(artist); }}
    >
      {busy ? "Signing…" : `${on ? "Following" : "Follow"}${followers > 0 ? ` · ${String(followers)}` : ""}`}
    </button>
  );
}

/** A step of the breadcrumb: a label and, except for the current page, where it leads. */
export interface Crumb {
  readonly label: string;
  readonly to?: View;
}

/** LIBRARY is the crumb every page under Library starts from. */
export const LIBRARY: Crumb = { label: "Library", to: { k: "library", genre: 0 } };

/**
 * Crumbs shows where a detail page sits (Library / Artist / Album) and
 * a back arrow to the level above: predictable, unlike the browser history.
 */
export function Crumbs({ trail, go }: { readonly trail: readonly Crumb[]; readonly go: Navigate }) {
  const up = trail.filter((c) => c.to !== undefined).at(-1);
  return (
    <nav className="crumbs" aria-label="Breadcrumb">
      {up?.to && (
        <button className="crumb-back" onClick={() => { if (up.to) go(up.to); }} aria-label={`Back to ${up.label}`} title={`Back to ${up.label}`}>
          <Icon name="arrow-left" size={16} />
        </button>
      )}
      <ol>
        {trail.map((c) => (
          <li key={c.label}>
            {c.to ? <button onClick={() => { if (c.to) go(c.to); }}>{c.label}</button> : <span aria-current="page">{c.label}</span>}
          </li>
        ))}
      </ol>
    </nav>
  );
}

/**
 * ShareButton shares a link, this page's by default: the system sheet on
 * phones, the clipboard elsewhere. `to` shares another screen, `text` adds a line.
 */
export function ShareButton({ title, to, text, refBy = "", compact = false }: { readonly title: string; readonly to?: View; readonly text?: string; readonly refBy?: string; readonly compact?: boolean }) {
  const [copied, setCopied] = useState(false);
  const share = async () => {
    // refBy makes the link earn: tips made from it share the artist's promo share with them.
    const url = withRef(to ? new URL(viewToPath(to, to.k === "stations" ? "" : title), location.origin).href : location.href, refBy);
    if (typeof navigator.share === "function") {
      await navigator.share({ title: `${title} · GnoRadio`, url, ...(text ? { text } : {}) }).catch(() => undefined);
      return;
    }
    await navigator.clipboard.writeText(text ? `${text} ${url}` : url);
    setCopied(true);
    setTimeout(() => { setCopied(false); }, 1800);
  };
  if (compact) {
    return <button className="mini-act" onClick={() => void share()} aria-label={copied ? "Link copied" : "Share"} title="Share a link"><Icon name={copied ? "check" : "share"} size={20} /></button>;
  }
  return (
    <button className="btn share" onClick={() => void share()} title="Share a link">
      <Icon name="share" size={15} /> {copied ? "Link copied" : "Share"}
    </button>
  );
}

/** Who names a listener (@name, else their nickname) and opens their page. */
export function Who({ address, shown, go, tabIndex }: { readonly address: string; readonly shown: (a: string) => string; readonly go: Navigate; readonly tabIndex?: number }) {
  return <button className="who" title={address} tabIndex={tabIndex} onClick={() => { go({ k: "listener", address }); }}>{shown(address)}</button>;
}

/** A stat of a Stats row; value 0 hides it. */
export interface Stat {
  readonly g: Glyph;
  readonly value: number;
  readonly shown: string;
  readonly label: string;
}

/** Stats shows the non-zero stats, or the empty line when none is. */
export function Stats({ items, empty }: { readonly items: readonly Stat[]; readonly empty: string }) {
  const on = items.filter((s) => s.value > 0);
  if (on.length === 0) return <p className="muted">{empty}</p>;
  return <div className="stats">{on.map((s) => <div key={s.label}><Shape g={s.g} size={14} /><b className="mono">{s.shown}</b><span>{s.label}</span></div>)}</div>;
}
