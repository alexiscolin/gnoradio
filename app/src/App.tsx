import { useCallback, useEffect, useRef, useState } from "react";
import { register, start as startAnalytics, track } from "./lib/analytics";
import { CHAIN_ID } from "./lib/gno";
import { MiniPlayer, MobileTop, Sidebar, TabBar } from "./components/Chrome";
import { GnokeySheet } from "./components/GnokeySheet";
import { jumpTo } from "./components/common";
import { WalletSheet } from "./wallet/WalletSheet";
import { NowPlaying } from "./components/NowPlaying";
import { PickNext } from "./components/PickNext";
import { Splash } from "./components/Splash";
import { SupportSheet, type SupportTarget } from "./components/SupportSheet";
import { loadCatalog, type Touched, touchedBy, viewName } from "./lib/catalog";
import { useNamedRefs } from "./lib/refs";
import { EMPTY_SUPPORT, loadActivity, loadFees, loadSupport } from "./lib/community";
import { FeesContext } from "./lib/fees";
import { errorMessage } from "./lib/format";
import type { Call } from "./lib/gno";
import { sessionRef } from "./lib/incentives";
import { codeURL } from "./lib/links";
import { openSearch } from "./lib/search";
import { pathToView, viewToPath } from "./lib/router";
import { useSaved } from "./lib/saved";
import type { Activity, Catalog, SupportInfo, View } from "./lib/types";
import { type Actions, useActions } from "./player/useActions";
import { useMediaMeta } from "./player/useMediaMeta";
import { type Player, usePlayer } from "./player/usePlayer";
import { Library, Listen, Stations } from "./views/Browse";
import { Community, Me, NotFound, Studio } from "./views/Community";
import { About } from "./views/About";
import { Features } from "./views/Features";
import { Legal } from "./views/Legal";
import { ListenerView } from "./views/Listener";
import { DoorView } from "./views/Door";
import { CollectionView } from "./views/Collection";
import { Contribute } from "./views/Contribute";
import { AlbumView, ArtistView, Concerts, PlaylistView, TrackView } from "./views/Detail";

const PULSE_MS = 60_000;
// "Read the code" opens the file holding the function the sheet calls.
const codeURLFor = (t: SupportTarget) => codeURL(t.kind === "tip" ? "tip" : "support");

const EARLY: ReadonlySet<View["k"]> = new Set(["listen", "stations", "library"]);

export default function App() {
  const [chainCat, setCat] = useState<Catalog | null>(null);
  // Audius and Jamendo pointers named from their platform as screens show them (lib/refs.ts).
  const cat = useNamedRefs(chainCat);
  const [loadError, setLoadError] = useState("");
  // Old #/ links still open the right screen; the URL is rewritten to a path below.
  const [view, setView] = useState<View>(() => pathToView(window.location.hash.startsWith("#/") ? window.location.hash : window.location.pathname));
  // A section anchor in the first URL (/me#me-tickets): kept before the address bar is rewritten, honoured once the page is drawn.
  const firstHash = useRef(window.location.hash.startsWith("#/") ? "" : decodeURIComponent(window.location.hash.slice(1)));
  const viewRef = useRef(view);
  viewRef.current = view;
  const [sheet, setSheet] = useState(false);
  const [supportTarget, setSupportTarget] = useState<SupportTarget | null>(null);
  const [pick, setPick] = useState<{ readonly station: number; readonly track?: number | undefined } | null>(null);
  const openPick = useCallback((station: number, track?: number) => { setPick({ station, track }); }, []);
  const closeSheet = useCallback(() => { setSheet(false); }, []);
  const [activity, setActivity] = useState<readonly Activity[]>([]);
  const [support, setSupport] = useState<SupportInfo>(EMPTY_SUPPORT);
  const [fees, setFees] = useState(false); // no fee until the realm says so
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
    void loadFees().then(setFees);
    setNow(Date.now() / 1000);
  }, []);

  const loadSeq = useRef(0);
  const booting = useRef(true); // the first full catalog load is still running
  // touched: after a transaction, what it can have changed (re-read whatever the browser cache says).
  const refresh = useCallback((touched?: Touched) => {
    const seq = ++loadSeq.current;
    // A return visit opens on the stored catalog; a first visit on the newest tracks while
    // the rest loads, but a page that needs a given artist, album or track waits for the whole catalog.
    const show = (c: Catalog) => { if (seq === loadSeq.current) setCat((prev) => prev ?? c); };
    loadCatalog({ cached: show, early: EARLY.has(viewRef.current.k) ? show : undefined, touched, current: () => seq === loadSeq.current }).then(
      (c) => {
        if (seq !== loadSeq.current) return;
        booting.current = false;
        if (seq === 1) track("load", { what: "catalog", ms: Math.round(performance.now()) });
        setCat(c);
        setLoadError("");
      },
      (e: unknown) => { if (seq === loadSeq.current) { booting.current = false; setLoadError(errorMessage(e)); } },
    );
    refreshPulse();
  }, [refreshPulse]);

  useEffect(() => { refresh(); }, [refresh]);
  // Audience measurement: loads once idle, only in a build with a key (lib/analytics.ts).
  useEffect(() => { startAnalytics(CHAIN_ID); }, []);
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
    const onPop = () => { setView(pathToView(window.location.pathname)); setFrom(null); };
    window.addEventListener("popstate", onPop);
    return () => { window.removeEventListener("popstate", onPop); };
  }, []);

  // A track the radio airs that this catalog does not hold yet (published since it loaded): read it.
  // Not while the first full load runs: a refresh would restart it (the full catalog brings the track anyway).
  const fetchTrack = useCallback((id: number) => { if (!booting.current) refresh({ tracks: [id], artists: [] }); }, [refresh]);
  const player = usePlayer(cat, fetchTrack);
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
  const afterTx = useCallback((c?: Call) => { refresh(touchedBy(c)); resync(); }, [refresh, resync]);
  const actions = useActions(afterTx);
  useEffect(() => { register({ wallet: actions.wallet.state.status }); }, [actions.wallet.state.status]);
  // Whether a shared link brought this browser (the sharer is never sent): the share loop, measured.
  useEffect(() => { register({ referred: sessionRef() !== "" }); }, []);
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
  }, [cat, view]);
  // The page Stations was opened from (an artist, an album…): a way back after changing station.
  const [from, setFrom] = useState<View | null>(null);
  const go = useCallback((v: View) => {
    setFrom(v.k === "stations" && viewName(catRef.current, viewRef.current) ? viewRef.current : null);
    const path = viewToPath(v, viewName(catRef.current, v));
    if (window.location.pathname !== path) window.history.pushState(null, "", path);
    setView(v);
    setSheet(false);
    document.querySelector(".main")?.scrollTo({ top: 0 });
  }, []);

  useEffect(() => {
    const h = firstHash.current;
    if (!cat || !h) return;
    firstHash.current = "";
    const id = window.setTimeout(() => { jumpTo(h); }, 300);
    return () => { window.clearTimeout(id); };
  }, [cat]);

  // A new screen: focus its title (or the content), so keyboard and screen-reader users land on it, not on <body>.
  const firstView = useRef(true);
  useEffect(() => {
    if (firstView.current) { firstView.current = false; return; }
    const id = window.requestAnimationFrame(() => {
      const target = document.querySelector<HTMLElement>(".main .view h1, .main .view h2") ?? document.querySelector<HTMLElement>(".main");
      if (!target) return;
      if (!target.hasAttribute("tabindex")) target.setAttribute("tabindex", "-1");
      target.focus({ preventScroll: true });
    });
    return () => { window.cancelAnimationFrame(id); };
  }, [view]);

  const poster = splash === "done" ? null : <Splash ready={cat !== null} error={loadError} onLeave={onSplashLeave} onDone={onSplashDone} onRetry={() => { setLoadError(""); refresh(); }} />;
  if (!cat) return poster;

  const w = actions.wallet.state;
  const wallet = w.status === "connected" || w.status === "wrong-network" ? w.address : "";
  const isAdmin = (w.status === "connected" || w.status === "wrong-network") && w.address === cat.admin;

  return (
    <FeesContext.Provider value={fees}>
    {poster}
    <div className={`shell${intro ? " reveal" : ""}`}>
      <a className="skip" href="#content">Skip to content</a>
      <MobileTop actions={actions} isAdmin={isAdmin} go={go} />
      <Sidebar view={view} go={go} actions={actions} isAdmin={isAdmin} />
      <main className="main" id="content" tabIndex={-1}>
        <div className="view" key={viewToPath(view)}>
        {renderView({ view, from, cat, player, actions, go, saved, activity, support, now, openSupport: setSupportTarget, openPick, isAdmin, me: wallet })}
        </div>
      </main>
      <NowPlaying cat={cat} player={player} actions={actions} saved={saved} open={sheet} onClose={closeSheet} go={go} openSupport={setSupportTarget} openPick={openPick} />
      <MiniPlayer cat={cat} player={player} onOpen={() => { setSheet(true); }} openPick={openPick} me={wallet} />
      <TabBar view={view} go={go} />
      {pick !== null && (
        <PickNext cat={cat} station={pick.station} suggest={pick.track} me={wallet} pending={actions.pending} notice={actions.toast} onPick={actions.queue} onClose={() => { setPick(null); }} go={go} />
      )}
      {supportTarget && (
        <SupportSheet target={supportTarget} codeURL={codeURLFor(supportTarget)} me={wallet} referrer={sessionRef()} onClose={() => { setSupportTarget(null); }} onTip={actions.tip} onSupport={actions.support} />
      )}
      {actions.wallet.asking && <WalletSheet wallet={actions.wallet} />}
      {actions.gnokey && <GnokeySheet label={actions.gnokey.label} call={actions.gnokey.call} onClose={actions.closeGnokey} />}
      <div className={`toast${actions.toast ? "" : " empty"}`} role="status" aria-live="polite">
        {actions.toast?.text}
        {actions.toast?.link && <> · <a href={actions.toast.link} target="_blank" rel="noreferrer">View on gnoscan</a></>}
      </div>
    </div>
    </FeesContext.Provider>
  );
}

interface RenderArgs {
  readonly from: View | null;
  readonly view: View;
  readonly cat: Catalog;
  readonly player: Player;
  readonly actions: Actions;
  readonly go: (v: View) => void;
  readonly saved: ReturnType<typeof useSaved>;
  readonly activity: readonly Activity[];
  readonly support: SupportInfo;
  readonly now: number;
  readonly openSupport: (t: SupportTarget) => void;
  readonly openPick: (station: number, track?: number) => void;
  readonly isAdmin: boolean;
  readonly me: string;
}

function renderView(a: RenderArgs) {
  const { view, cat, player, actions, go } = a;
  switch (view.k) {
    case "listen":
      return <Listen cat={cat} player={player} go={go} activity={a.activity} support={a.support} now={a.now} openSupport={a.openSupport} openPick={a.openPick} />;
    case "stations":
      return <Stations cat={cat} player={player} go={go} live={view.live} back={a.from ? { label: viewName(cat, a.from), to: a.from } : undefined} />;
    case "library":
      return <Library cat={cat} player={player} go={go} genre={view.genre} actions={actions} saved={a.saved} />;
    case "concerts":
      return <Concerts cat={cat} go={go} player={player} actions={actions} />;
    case "community":
      return <Community cat={cat} go={go} support={a.support} activity={a.activity} now={a.now} onSupport={() => { a.openSupport({ kind: "platform" }); }} openPick={a.openPick} />;
    case "me":
      return <Me cat={cat} go={go} actions={actions} saved={a.saved} openPick={a.openPick} />;
    case "studio":
      return a.isAdmin ? <Studio cat={cat} go={go} actions={actions} /> : <NotFound go={go} text="The studio is for the GnoRadio admin: connect the admin wallet to open it." />;
    case "track":
      return <TrackView cat={cat} player={player} go={go} id={view.id} actions={actions} openSupport={a.openSupport} openPick={a.openPick} />;
    case "artist":
      return <ArtistView cat={cat} player={player} go={go} id={view.id} actions={actions} openSupport={a.openSupport} />;
    case "album":
      return <AlbumView cat={cat} player={player} go={go} id={view.id} actions={actions} saved={a.saved} openSupport={a.openSupport} />;
    case "playlist":
      return <PlaylistView cat={cat} player={player} go={go} id={view.id} actions={actions} saved={a.saved} />;
    case "listener":
      return <ListenerView cat={cat} go={go} address={view.address} me={a.me} openPick={a.openPick} />;
    case "collection":
      return <CollectionView cat={cat} player={player} go={go} actions={actions} saved={a.saved} list={view.list} />;
    case "door":
      return <DoorView cat={cat} go={go} ticket={view.ticket} holder={view.holder} actions={actions} />;
    case "contribute":
      return <Contribute cat={cat} go={go} path={view.path} actions={actions} isAdmin={a.isAdmin} openPick={a.openPick} />;
    case "about":
      return <About cat={cat} support={a.support} go={go} />;
    case "features":
      return <Features cat={cat} support={a.support} go={go} openPick={a.openPick} me={a.me} />;
    case "legal":
      return <Legal />;
    case "notfound":
      return <NotFound go={go} text="Nothing lives at this address." />;
  }
}
