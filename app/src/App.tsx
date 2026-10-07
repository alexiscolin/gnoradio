import { useCallback, useEffect, useRef, useState } from "react";
import { MiniPlayer, MobileTop, Sidebar, TabBar } from "./components/Chrome";
import { GnokeySheet } from "./components/GnokeySheet";
import { NowPlaying } from "./components/NowPlaying";
import { PickNext } from "./components/PickNext";
import { Splash } from "./components/Splash";
import { SupportSheet, type SupportTarget } from "./components/SupportSheet";
import { loadCatalog, viewName } from "./lib/catalog";
import { EMPTY_SUPPORT, loadActivity, loadSupport } from "./lib/community";
import { errorMessage } from "./lib/format";
import { codeURL } from "./lib/links";
import { openSearch } from "./lib/search";
import { pathToView, viewToPath } from "./lib/router";
import { pageTitle } from "./lib/seo";
import { useSaved } from "./lib/saved";
import type { Activity, Catalog, SupportInfo, View } from "./lib/types";
import { type Actions, useActions } from "./player/useActions";
import { useMediaMeta } from "./player/useMediaMeta";
import { type Player, usePlayer } from "./player/usePlayer";
import { Library, Listen, Stations } from "./views/Browse";
import { Community, Me, Studio } from "./views/Community";
import { About } from "./views/About";
import { Contribute } from "./views/Contribute";
import { AlbumView, ArtistView, Concerts, PlaylistView, TrackView } from "./views/Detail";

const PULSE_MS = 60_000;
// "Read the code" opens the file holding the function the sheet calls.
const codeURLFor = (t: SupportTarget) => codeURL(t.kind === "tip" ? "tip" : "support");

export default function App() {
  const [cat, setCat] = useState<Catalog | null>(null);
  const [loadError, setLoadError] = useState("");
  // Old #/ links still open the right screen; the URL is rewritten to a path below.
  const [view, setView] = useState<View>(() => pathToView(window.location.hash.startsWith("#/") ? window.location.hash : window.location.pathname));
  const [sheet, setSheet] = useState(false);
  const [supportTarget, setSupportTarget] = useState<SupportTarget | null>(null);
  const [pick, setPick] = useState<{ readonly station: number; readonly track?: number | undefined } | null>(null);
  const openPick = useCallback((station: number, track?: number) => { setPick({ station, track }); }, []);
  const closeSheet = useCallback(() => { setSheet(false); }, []);
  const [activity, setActivity] = useState<readonly Activity[]>([]);
  const [support, setSupport] = useState<SupportInfo>(EMPTY_SUPPORT);
  const [now, setNow] = useState(() => Date.now() / 1000);
  const [splash, setSplash] = useState<"on" | "leaving" | "done">("on");
  const [intro, setIntro] = useState(false); // panels rise in once, under the lifting poster
  const onSplashLeave = useCallback(() => {
    setSplash("leaving");
    setIntro(true);
    window.setTimeout(() => { setIntro(false); }, 2800);
  }, []);
  const onSplashDone = useCallback(() => { setSplash("done"); }, []);

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

  // ⌘K / Ctrl+K anywhere opens the search (Library handles it itself when it is on screen).
  useEffect(() => {
    const onKey = (e: KeyboardEvent) => {
      if (e.key === "k" && (e.metaKey || e.ctrlKey) && !window.location.pathname.startsWith("/library")) { e.preventDefault(); openSearch(); }
    };
    window.addEventListener("keydown", onKey);
    return () => { window.removeEventListener("keydown", onKey); };
  }, []);

  // Path routing: every screen has a readable, shareable URL and the back button works.
  useEffect(() => {
    const onPop = () => { setView(pathToView(window.location.pathname)); };
    window.addEventListener("popstate", onPop);
    return () => { window.removeEventListener("popstate", onPop); };
  }, []);

  const player = usePlayer(cat);
  const { toggle, toggleMute, nudge } = player;
  // Space plays/pauses, M mutes, arrows seek in Library mode. Keys typed into a field or on a control are left alone.
  useEffect(() => {
    const onKey = (e: KeyboardEvent) => {
      if (e.metaKey || e.ctrlKey || e.altKey || e.defaultPrevented) return;
      const el = e.target instanceof HTMLElement ? e.target : null;
      if (el?.closest("input, textarea, select, [contenteditable], button, a, [role=slider], dialog")) return;
      if (e.key === " ") { e.preventDefault(); toggle(); }
      else if (e.key === "m" || e.key === "M") toggleMute();
      else if (e.key === "ArrowRight") nudge(10);
      else if (e.key === "ArrowLeft") nudge(-10);
    };
    window.addEventListener("keydown", onKey);
    return () => { window.removeEventListener("keydown", onKey); };
  }, [toggle, toggleMute, nudge]);
  const { resync } = player;
  const afterTx = useCallback(() => { refresh(); resync(); }, [refresh, resync]);
  const actions = useActions(afterTx);
  useMediaMeta(cat, view, player);
  const saved = useSaved();
  // The catalog names the URL (/artist/scott-buckley-1): once it is loaded, the
  // address bar is rewritten in place, legacy #/ links included.
  const catRef = useRef(cat);
  catRef.current = cat;
  useEffect(() => {
    const name = viewName(cat, view);
    const path = viewToPath(view, name);
    if (window.location.pathname !== path || window.location.hash) window.history.replaceState(null, "", path);
    document.title = pageTitle(view, name);
  }, [cat, view]);
  const go = useCallback((v: View) => {
    const path = viewToPath(v, viewName(catRef.current, v));
    if (window.location.pathname !== path) window.history.pushState(null, "", path);
    setView(v);
    setSheet(false);
    document.querySelector(".main")?.scrollTo({ top: 0 });
  }, []);

  const poster = splash === "done" ? null : <Splash ready={cat !== null} error={loadError} onLeave={onSplashLeave} onDone={onSplashDone} onRetry={() => { setLoadError(""); refresh(); }} />;
  if (!cat) return poster;

  const w = actions.wallet.state;
  const wallet = w.status === "connected" || w.status === "wrong-network" ? w.address : "";
  const isAdmin = (w.status === "connected" || w.status === "wrong-network") && w.address === cat.admin;

  return (
    <>
    {poster}
    <div className={`shell${intro ? " reveal" : ""}`}>
      <MobileTop actions={actions} />
      <Sidebar view={view} go={go} actions={actions} isAdmin={isAdmin} />
      <main className="main">
        <div className="view" key={viewToPath(view)}>
        {renderView({ view, cat, player, actions, go, savedIds: saved.ids, activity, support, now, openSupport: setSupportTarget, openPick, isAdmin })}
        </div>
      </main>
      <NowPlaying cat={cat} player={player} actions={actions} saved={saved} open={sheet} onClose={closeSheet} go={go} openSupport={setSupportTarget} openPick={openPick} />
      <MiniPlayer cat={cat} player={player} onOpen={() => { setSheet(true); }} />
      <TabBar view={view} go={go} />
      {pick !== null && (
        <PickNext cat={cat} station={pick.station} suggest={pick.track} me={wallet} pending={actions.pending} onPick={actions.queue} onClose={() => { setPick(null); }} />
      )}
      {supportTarget && (
        <SupportSheet target={supportTarget} codeURL={codeURLFor(supportTarget)} onClose={() => { setSupportTarget(null); }} onTip={actions.tip} onSupport={actions.support} />
      )}
      {actions.gnokey && <GnokeySheet label={actions.gnokey.label} call={actions.gnokey.call} onClose={actions.closeGnokey} />}
      <div className={`toast${actions.toast ? "" : " empty"}`} role="status" aria-live="polite">
        {actions.toast?.text}
        {actions.toast?.link && <> · <a href={actions.toast.link} target="_blank" rel="noreferrer">View on gnoscan</a></>}
      </div>
    </div>
    </>
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
  readonly openPick: (station: number, track?: number) => void;
  readonly isAdmin: boolean;
}

function renderView(a: RenderArgs) {
  const { view, cat, player, actions, go } = a;
  switch (view.k) {
    case "listen":
      return <Listen cat={cat} player={player} go={go} activity={a.activity} support={a.support} now={a.now} openSupport={a.openSupport} openPick={a.openPick} />;
    case "stations":
      return <Stations cat={cat} player={player} live={view.live} />;
    case "library":
      return <Library cat={cat} player={player} go={go} genre={view.genre} />;
    case "concerts":
      return <Concerts cat={cat} go={go} actions={actions} />;
    case "community":
      return <Community cat={cat} go={go} support={a.support} activity={a.activity} now={a.now} onSupport={() => { a.openSupport({ kind: "platform" }); }} openPick={a.openPick} />;
    case "me":
      return <Me cat={cat} go={go} player={player} actions={actions} savedIds={a.savedIds} />;
    case "studio":
      return a.isAdmin ? <Studio cat={cat} go={go} actions={actions} /> : <p className="muted">The studio is for the GnoRadio admin.</p>;
    case "track":
      return <TrackView cat={cat} player={player} go={go} id={view.id} actions={actions} openSupport={a.openSupport} openPick={a.openPick} />;
    case "artist":
      return <ArtistView cat={cat} player={player} go={go} id={view.id} actions={actions} openSupport={a.openSupport} />;
    case "album":
      return <AlbumView cat={cat} player={player} go={go} id={view.id} />;
    case "playlist":
      return <PlaylistView cat={cat} player={player} go={go} id={view.id} />;
    case "contribute":
      return <Contribute cat={cat} go={go} path={view.path} actions={actions} isAdmin={a.isAdmin} openPick={a.openPick} />;
    case "about":
      return <About cat={cat} support={a.support} go={go} />;
  }
}
