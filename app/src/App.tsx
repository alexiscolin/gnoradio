import { useCallback, useEffect, useRef, useState } from "react";
import { MiniPlayer, MobileTop, Sidebar, TabBar } from "./components/Chrome";
import { NowPlaying } from "./components/NowPlaying";
import { Composition } from "./components/Shapes";
import { SupportSheet, type SupportTarget } from "./components/SupportSheet";
import { loadCatalog } from "./lib/catalog";
import { loadActivity, loadSupport } from "./lib/community";
import { errorMessage } from "./lib/format";
import { GNOWEB, REALMS } from "./lib/gno";
import { hashToView, viewToHash } from "./lib/router";
import { useSaved } from "./lib/saved";
import type { Activity, Catalog, SupportInfo, View } from "./lib/types";
import { type Actions, useActions } from "./player/useActions";
import { type Player, usePlayer } from "./player/usePlayer";
import { Library, Listen, Saved, Search, Stations } from "./views/Browse";
import { Community, Me, Studio } from "./views/Community";
import { AlbumView, ArtistView, Concerts, PlaylistView, TrackView } from "./views/Detail";

const PULSE_MS = 60_000;
const CODE_URL = `${GNOWEB}/${REALMS.catalog.replace(/^gno\.land\//, "")}$source&file=social.gno`;
const EMPTY_SUPPORT: SupportInfo = { treasury: "", total: 0, supporters: 0, month: "", monthTotal: 0, goal: 0, top: [] };

export default function App() {
  const [cat, setCat] = useState<Catalog | null>(null);
  const [loadError, setLoadError] = useState("");
  const [view, setView] = useState<View>(() => hashToView(window.location.hash));
  const [sheet, setSheet] = useState(false);
  const [supportTarget, setSupportTarget] = useState<SupportTarget | null>(null);
  const [activity, setActivity] = useState<readonly Activity[]>([]);
  const [support, setSupport] = useState<SupportInfo>(EMPTY_SUPPORT);
  const [now, setNow] = useState(() => Date.now() / 1000);

  const refreshPulse = useCallback(() => {
    void loadActivity().then(setActivity);
    void loadSupport().then(setSupport);
    setNow(Date.now() / 1000);
  }, []);

  const loadSeq = useRef(0);
  const refresh = useCallback(() => {
    const seq = ++loadSeq.current;
    loadCatalog().then(
      (c) => {
        if (seq !== loadSeq.current) return;
        setCat(c);
        setLoadError("");
      },
      (e: unknown) => { if (seq === loadSeq.current) setLoadError(errorMessage(e)); },
    );
    refreshPulse();
  }, [refreshPulse]);

  useEffect(refresh, [refresh]);
  useEffect(() => {
    const id = window.setInterval(() => { if (!document.hidden) refreshPulse(); }, PULSE_MS);
    return () => { window.clearInterval(id); };
  }, [refreshPulse]);

  // Hash routing: every screen has a shareable URL and the back button works.
  useEffect(() => {
    const onHash = () => { setView(hashToView(window.location.hash)); };
    window.addEventListener("hashchange", onHash);
    return () => { window.removeEventListener("hashchange", onHash); };
  }, []);

  const player = usePlayer(cat);
  const { resync } = player;
  const afterTx = useCallback(() => { refresh(); resync(); }, [refresh, resync]);
  const actions = useActions(afterTx);
  const saved = useSaved();
  const go = useCallback((v: View) => {
    const hash = viewToHash(v);
    if (window.location.hash !== hash) window.location.hash = hash;
    setView(v);
    setSheet(false);
    document.querySelector(".main")?.scrollTo({ top: 0 });
  }, []);

  if (!cat) return <Splash error={loadError} />;

  const w = actions.wallet.state;
  const isAdmin = (w.status === "connected" || w.status === "wrong-network") && w.address === cat.admin;

  return (
    <div className="shell">
      <MobileTop actions={actions} />
      <Sidebar view={view} go={go} player={player} actions={actions} isAdmin={isAdmin} />
      <main className="main">
        {renderView({ view, cat, player, actions, go, savedIds: saved.ids, activity, support, now, openSupport: setSupportTarget, isAdmin })}
      </main>
      <NowPlaying cat={cat} player={player} actions={actions} saved={saved} open={sheet} onClose={() => { setSheet(false); }} go={go} openSupport={setSupportTarget} />
      <MiniPlayer cat={cat} player={player} onOpen={() => { setSheet(true); }} />
      <TabBar view={view} go={go} />
      {supportTarget && (
        <SupportSheet target={supportTarget} codeURL={CODE_URL} onClose={() => { setSupportTarget(null); }} onTip={actions.tip} onSupport={actions.support} />
      )}
      <div className={`toast${actions.toast ? "" : " empty"}`} role="status" aria-live="polite">
        {actions.toast?.text}
        {actions.toast?.link && <> · <a href={actions.toast.link} target="_blank" rel="noreferrer">View on gnoscan</a></>}
      </div>
    </div>
  );
}

interface RenderArgs {
  readonly view: View;
  readonly cat: Catalog;
  readonly player: Player;
  readonly actions: Actions;
  readonly go: (v: View) => void;
  readonly savedIds: readonly number[];
  readonly activity: readonly Activity[];
  readonly support: SupportInfo;
  readonly now: number;
  readonly openSupport: (t: SupportTarget) => void;
  readonly isAdmin: boolean;
}

function renderView(a: RenderArgs) {
  const { view, cat, player, actions, go } = a;
  switch (view.k) {
    case "listen":
      return <Listen cat={cat} player={player} go={go} activity={a.activity} support={a.support} now={a.now} openSupport={a.openSupport} />;
    case "stations":
      return <Stations cat={cat} player={player} />;
    case "library":
      return <Library cat={cat} player={player} go={go} genre={view.genre} />;
    case "search":
      return <Search cat={cat} player={player} go={go} />;
    case "saved":
      return <Saved cat={cat} player={player} ids={a.savedIds} />;
    case "concerts":
      return <Concerts cat={cat} go={go} actions={actions} />;
    case "community":
      return <Community cat={cat} go={go} support={a.support} activity={a.activity} now={a.now} onSupport={() => { a.openSupport({ kind: "platform" }); }} />;
    case "me":
      return <Me cat={cat} go={go} player={player} actions={actions} />;
    case "studio":
      return a.isAdmin ? <Studio cat={cat} go={go} actions={actions} /> : <p className="muted">The studio is for the GnoRadio admin.</p>;
    case "track":
      return <TrackView cat={cat} player={player} go={go} id={view.id} actions={actions} openSupport={a.openSupport} />;
    case "artist":
      return <ArtistView cat={cat} player={player} go={go} id={view.id} actions={actions} openSupport={a.openSupport} />;
    case "album":
      return <AlbumView cat={cat} player={player} go={go} id={view.id} />;
    case "playlist":
      return <PlaylistView cat={cat} player={player} id={view.id} />;
  }
}

/** Splash is the loading screen: a GnoRadio Bauhaus poster. */
function Splash({ error }: { readonly error: string }) {
  return (
    <div className="splash" aria-busy={!error}>
      <div className="splash-poster" aria-hidden="true">
        <Composition variant={2} />
      </div>
      <div className="splash-text">
        <p className="splash-kicker">Community radio · open music · on-chain</p>
        <p className="splash-word">Gno<br />Radio<i className="dot" /></p>
        <p className="splash-state">{error ? `Could not reach the chain: ${error}` : "Tuning in…"}</p>
      </div>
    </div>
  );
}
