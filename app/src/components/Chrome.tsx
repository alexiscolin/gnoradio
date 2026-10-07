import { Help } from "./Help";
import { Icon } from "./Icons";
import { CHAIN_ID, networkLabel } from "../lib/gno";
import { realmPage } from "../lib/links";
import type { Catalog, Navigate, View } from "../lib/types";
import type { Actions } from "../player/useActions";
import { type Player, usePosition } from "../player/usePlayer";
import { WalletCard, WalletPill } from "../wallet/WalletCard";
import { Cover } from "./Cover";
import { Shape } from "./Shapes";
import { openSearch } from "../lib/search";
import { type Section, sectionOf, sectionView } from "../lib/router";


const TABS: readonly (readonly [Section, string])[] = [
  ["listen", "Listen"],
  ["stations", "Stations"],
  ["library", "Library"],
  ["community", "Community"],
  ["concerts", "Concerts"],
  ["contribute", "Contribute"],
  ["me", "Me"],
];
/** The phone tab bar: Concerts, Contribute and About open from Me. */
const MOBILE_TABS = new Set<Section>(["listen", "stations", "library", "community", "me"]);


/** Net is the small "which chain" badge; nothing on mainnet. */
const NET = networkLabel(CHAIN_ID);
const Net = () => (NET ? <span className={`net${CHAIN_ID === "dev" ? " dev" : ""}`} title={`${NET}: test GNOT, no real value. Perfect to try everything.`}>{NET} · test GNOT</span> : null);

// Each nav item gets its own pure Bauhaus shape; it pops in on hover and stays on the current screen.
const NAV_GLYPHS = [
  { g: "circle", fill: "var(--red)" },
  { g: "square", fill: "var(--yellow)" },
  { g: "quarter", fill: "var(--blue)" },
  { g: "triangle", fill: "var(--ink)" },
] as const;

export function Sidebar({ view, go, actions, isAdmin }: { readonly view: View; readonly go: Navigate; readonly actions: Actions; readonly isAdmin: boolean }) {
  return (
    <aside className="side">
      <div className="brand"><button className="brand-home" onClick={() => { go(sectionView("listen")); }} title="Back to Listen">GnoRadio<i className="dot" /></button> <span className="net-row"><Net /></span></div>
      <button className="side-search" onClick={openSearch} title="Search tracks, artists, albums and playlists">
        <Icon name="search" size={16} /><span>Search</span><kbd>⌘K</kbd>
      </button>
      <nav aria-label="Main">
        {TABS.map(([k, label], i) => (
          <button key={k} className={sectionOf(view) === k ? "on" : ""} aria-current={sectionOf(view) === k ? "page" : undefined} onClick={() => { go(sectionView(k)); }}>
            <span className="nav-glyph" aria-hidden="true"><Shape {...(NAV_GLYPHS[i % NAV_GLYPHS.length] ?? NAV_GLYPHS[0])} size={9} /></span>{label}
          </button>
        ))}
        {isAdmin && <button className={view.k === "studio" ? "on studio" : "studio"} onClick={() => { go({ k: "studio" }); }}>Studio</button>}
      </nav>
      <WalletCard wallet={actions.wallet} onRegister={actions.registerName} />
      <footer className="side-foot">
        <Help text="Adena is the gno.land wallet. It signs likes, tips and picks; listening never needs it. Disconnect makes GnoRadio forget it: remove the site in Adena to revoke access." />
        <button className={view.k === "about" ? "on" : ""} onClick={() => { go({ k: "about" }); }}>About</button>
        <a href={realmPage("home")} target="_blank" rel="noreferrer">gno.land <Icon name="external" size={12} className="nudge-out" /></a>
        <button className={view.k === "legal" ? "legal-link on" : "legal-link"} onClick={() => { go({ k: "legal" }); }}>Legal · Privacy · Terms</button>
      </footer>
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
      <button className="mini-play" onClick={p.toggle} aria-label={p.playing ? "Pause" : "Play"}><Icon name={p.playing ? "pause" : "play"} size={20} /></button>
      <i style={{ width: `${String(progress * 100)}%` }} />
    </div>
  );
}

export function TabBar({ view, go }: { readonly view: View; readonly go: Navigate }) {
  return (
    <nav className="tabbar" aria-label="Main">
      {TABS.filter(([k]) => MOBILE_TABS.has(k)).map(([k, label]) => (
        <button key={k} className={sectionOf(view) === k ? "on" : ""} aria-current={sectionOf(view) === k ? "page" : undefined} onClick={() => { go(sectionView(k)); }}>{label}</button>
      ))}
    </nav>
  );
}

/** MobileTop shows the brand and the wallet on small screens. */
export function MobileTop({ actions }: { readonly actions: Actions }) {
  return (
    <header className="mtop">
      <span className="brand">GnoRadio<i className="dot" /> <Net /></span>
      <WalletPill wallet={actions.wallet} />
    </header>
  );
}
