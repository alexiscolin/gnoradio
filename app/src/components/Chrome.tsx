import type { Catalog, Navigate, View } from "../lib/types";
import type { Actions } from "../player/useActions";
import { type Player, usePosition } from "../player/usePlayer";
import { WalletCard, WalletPill } from "../wallet/WalletCard";
import { Cover } from "./Cover";

type Tab = Exclude<View["k"], "artist" | "album" | "playlist" | "track">;

const TABS: readonly (readonly [Tab, string])[] = [
  ["listen", "Listen"],
  ["stations", "Stations"],
  ["library", "Library"],
  ["search", "Search"],
  ["community", "Community"],
  ["concerts", "Concerts"],
  ["saved", "Saved"],
  ["me", "Me"],
];

const viewOf = (k: Tab): View => (k === "library" ? { k, genre: 0 } : { k });

export function Sidebar({ view, go, player: p, actions, isAdmin }: { readonly view: View; readonly go: Navigate; readonly player: Player; readonly actions: Actions; readonly isAdmin: boolean }) {
  return (
    <aside className="side">
      <div className="brand">GnoRadio<i className="dot" /></div>
      <nav aria-label="Main">
        {TABS.map(([k, label]) => (
          <button key={k} className={view.k === k ? "on" : ""} aria-current={view.k === k ? "page" : undefined} onClick={() => { go(viewOf(k)); }}>{label}</button>
        ))}
        {isAdmin && <button className={view.k === "studio" ? "on studio" : "studio"} onClick={() => { go({ k: "studio" }); }}>Studio</button>}
      </nav>
      <div className="seg" role="group" aria-label="Mode">
        <button className={p.mode === "library" ? "on" : ""} aria-pressed={p.mode === "library"} onClick={p.toLibrary}>Library</button>
        <button className={p.mode === "live" ? "on live" : ""} aria-pressed={p.mode === "live"} onClick={() => { p.goLive(p.station); }}>Live</button>
      </div>
      <p className="hint">{p.mode === "live" ? "Everyone hears the same second. The schedule lives on-chain." : "Play anything, in any order. Listening never costs a transaction."}</p>
      <WalletCard wallet={actions.wallet} />
    </aside>
  );
}

export function MiniPlayer({ cat, player: p, onOpen }: { readonly cat: Catalog; readonly player: Player; readonly onOpen: () => void }) {
  const pos = usePosition(p.audio);
  const t = cat.byId.get(p.current);
  const progress = t && t.duration > 0 ? Math.min(1, pos / t.duration) : 0;
  return (
    <div className="mini">
      <button className="mini-open" onClick={onOpen} aria-label="Open player">
        <Cover t={t} size="44px" />
        <span className="mini-txt"><b>{t?.title ?? "GnoRadio"}</b><span>{t ? t.artistName : "Tap to play"}</span></span>
      </button>
      <button className="mini-play" onClick={p.toggle} aria-label={p.playing ? "Pause" : "Play"}>{p.playing ? "❚❚" : "▶"}</button>
      <i style={{ width: `${String(progress * 100)}%` }} />
    </div>
  );
}

export function TabBar({ view, go }: { readonly view: View; readonly go: Navigate }) {
  return (
    <nav className="tabbar" aria-label="Main">
      {TABS.filter(([k]) => k === "listen" || k === "stations" || k === "library" || k === "community" || k === "me").map(([k, label]) => (
        <button key={k} className={view.k === k ? "on" : ""} aria-current={view.k === k ? "page" : undefined} onClick={() => { go(viewOf(k)); }}>{label}</button>
      ))}
    </nav>
  );
}

/** MobileTop shows the brand and the wallet on small screens. */
export function MobileTop({ actions }: { readonly actions: Actions }) {
  return (
    <header className="mtop">
      <span className="brand">GnoRadio<i className="dot" /></span>
      <WalletPill wallet={actions.wallet} />
    </header>
  );
}
