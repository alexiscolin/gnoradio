import { bucket, track } from "../lib/analytics";
import { Icon } from "../components/Icons";
import { useEffect, useMemo, useRef, useState } from "react";
import { type TrackOrder, sortTracks } from "../lib/catalog";
import { BigList, type Crumb, Count, Crumbs, Empty, Head, MakeMusic, NOTHING_ON_AIR, NO_TRACK, Proof, TrackCards, TrackRows } from "../components/common";
import { ProofMark } from "../components/Verify";
import { useFees } from "../lib/fees";
import { DEFAULT_GOAL, clock, gnot, plural } from "../lib/format";
import { ActivityFeed } from "../components/ActivityFeed";
import { Shape } from "../components/Shapes";
import { Cover } from "../components/Cover";
import { fold } from "../components/SearchPick";
import { GenreGlyph } from "../lib/genres";
import { stationLine } from "../lib/onair";
import { SEARCH_EVENT } from "../lib/search";
import { Loader } from "../components/Loader";
import { PlayButton } from "../components/PlayButton";
import type { SupportTarget } from "../components/SupportSheet";
import type { Activity, Catalog, Navigate, SupportInfo } from "../lib/types";
import type { Saved } from "../lib/saved";
import { codeURL, gnowebOf } from "../lib/links";
import { MineLinks } from "./Collection";
import type { Actions } from "../player/useActions";
import type { Player } from "../player/usePlayer";
import { useWant } from "../lib/refs";

interface ViewProps {
  readonly cat: Catalog;
  readonly player: Player;
  readonly go: Navigate;
}

export function Listen({ cat, player, go, activity, support, now, openSupport, openPick }: ViewProps & {
  readonly openPick: (station: number) => void;
  readonly activity: readonly Activity[];
  readonly support: SupportInfo;
  readonly now: number;
  readonly openSupport: (t: SupportTarget) => void;
}) {
  const fees = useFees().support;
  const main = cat.stations[0];
  const goal = support.goal > 0 ? support.goal : DEFAULT_GOAL;
  const onAir = main ? cat.byId.get(main.now.track) : undefined;
  const fresh = [...cat.tracks].sort((a, b) => b.id - a.id).slice(0, 8);
  const claimed = [...cat.artists.values()].filter((a) => a.verified && a.owner && a.tracks.length > 0).sort((a, b) => b.tips - a.tips).slice(0, 4);
  return (
    <section>
      <div className="hero">
        <button className="onair" onClick={() => { if (onAir) player.goLive(0); else go({ k: "contribute", path: "artist" }); }}>
          <span className="chip red"><Shape g="circle" size={9} fill="#fff" /> On air · Main</span>
          <span className="onair-eq" aria-hidden="true"><i /><i /><i /><i /></span>
          <span className="onair-title">{onAir?.title ?? "Nothing on air yet"}</span>
          <span className="muted">{onAir && main ? `${onAir.artistName} · ${clock(main.now.offset)} in · everyone hears the same second` : "Publish the first track: it goes on air in the same transaction."}</span>
          {onAir && <span className="muted small">Or play any track just for you in the Library.</span>}
          <span className="go">{onAir ? "Listen" : "Make music"} <Icon name="arrow-right" size={16} className="nudge" /></span>
        </button>
        {fees && <button className="block-yellow" onClick={() => { go({ k: "community" }); }}>
          <span className="lbl">Given to GnoRadio by listeners</span>
          <span className="big">{support.monthTotal > 0 ? gnot(support.monthTotal) : "Be the first"}</span>
          <span className="bar"><i style={{ width: `${String(Math.min(100, (support.monthTotal / goal) * 100))}%` }} /></span>
          <span className="small">{support.monthTotal > 0 ? `of ${gnot(goal)} this month` : `Goal: ${gnot(goal)} this month`}{support.supporters > 0 ? ` · ${plural(support.supporters, "supporter")}` : ""}</span>
        </button>}
        {!fees && <button className="block-yellow" onClick={() => { go({ k: "contribute", path: "artist" }); }}>
          <span className="lbl">For artists</span>
          <span className="big">Make music</span>
          <span className="small">Publish your tracks: they join the radio in the same transaction. Tips go 100% to you, 0% to GnoRadio.</span>
          <span className="go">Publish <Icon name="arrow-right" size={16} className="nudge" /></span>
        </button>}
      </div>
      {cat.tracks.length > 0 && <button className="bethedj" onClick={() => { openPick(0); }}>
        <Icon name="on-air" size={48} className="bethedj-icon" />
        <span className="bethedj-txt">
          <b>Be the DJ</b>
          <span>Pick a track: it plays on Main for everyone tuned in, next or at a time you choose.</span>
          <span className="bethedj-perks">
            <span>Your name on air</span>
            <span>A dedication on air</span>
            <span>A share of tips, if the artist sets one</span>
            <span>Some picks refunded by the artist</span>
          </span>
        </span>
        <span className="bethedj-go">Pick a track <Icon name="arrow-right" size={16} className="nudge" /></span>
      </button>}
      <div className="cols">
        <div>
          <h3 className="sub">Community pulse <span className="live-dot" aria-hidden="true" /></h3>
          <ActivityFeed items={activity.slice(0, 3)} cat={cat} go={go} now={now} compact />
          <button className="link small" onClick={() => { go({ k: "community" }); }}>All activity <Icon name="arrow-right" size={14} className="nudge" /></button>
        </div>
        <div>
          <h3 className="sub">Support an artist</h3>
          {claimed.length === 0 && <Empty text="Artists who verified their profile appear here. Every tip reaches them in the same transaction."><button className="link small" onClick={() => { go({ k: "contribute", path: "claim" }); }}>Verify your profile <Icon name="arrow-right" size={14} className="nudge" /></button></Empty>}
          <div className="artists">
            {claimed.map((a) => {
              const first = cat.byId.get(a.tracks[a.tracks.length - 1] ?? 0);
              return (
                <div key={a.id} className="artist-card">
                  <button className="name" onClick={() => { go({ k: "artist", id: a.id }); }}>{a.name}</button>
                  <span className="muted small"><ProofMark a={a} /> {[a.tips > 0 ? `${gnot(a.tips)} raised` : "Be the first to support them", a.followers > 0 ? plural(a.followers, "follower") : ""].filter(Boolean).join(" · ")}</span>
                  {first && <button className="cta yellow" onClick={() => { openSupport({ kind: "tip", track: first, artist: a }); }}><Shape g="square" size={10} fill="var(--ink)" /> Tip</button>}
                </div>
              );
            })}
          </div>
        </div>
      </div>

      <h3 className="sub">New releases</h3>
      {fresh.length === 0 ? <Empty text={NO_TRACK}><MakeMusic go={go} /></Empty> : <TrackCards tracks={fresh} player={player} meta={(t) => (t.likes > 0 ? `${t.artistName} · ♥ ${String(t.likes)}` : t.artistName)} />}
      {cat.playlists.length > 0 && (
        <>
          <h3 className="sub">Community playlists</h3>
          <BigList compact items={cat.playlists.map((pl) => ({ key: pl.id, label: pl.title, count: pl.tracks.length, onClick: () => { go({ k: "playlist", id: pl.id }); } }))} />
        </>
      )}
      {cat.albums.length > 0 && (
        <>
          <h3 className="sub">Albums</h3>
          <BigList compact items={cat.albums.map((al) => ({ key: al.id, label: al.title, count: al.tracks.length, onClick: () => { go({ k: "album", id: al.id }); } }))} />
        </>
      )}
    </section>
  );
}

/** Stations lists every station; opened from a page (the player's station chip), choosing one goes back there. */
export function Stations({ cat, player, go, live, back }: ViewProps & { readonly live?: number | undefined; readonly back?: Required<Crumb> | undefined }) {
  // A shared #/station/N link tunes in once on arrival.
  const { goLive } = player;
  // Tune in once per /live/N, not again each time the catalog (and so goLive) is renewed.
  const tuned = useRef<number | undefined>(undefined);
  useEffect(() => {
    if (live === undefined || tuned.current === live) return;
    tuned.current = live;
    goLive(live);
  }, [live, goLive]);
  return (
    <section>
      {back && <Crumbs trail={[back, { label: "Stations" }]} go={go} />}
      <Head a="Choose" b="Station" note="Each station plays the same second for everyone." right={<Count label="All" value={cat.stations.length} />} />
      {cat.tracks.length === 0 && <Empty text={NOTHING_ON_AIR}><MakeMusic go={go} /></Empty>}
      {/* The big station list, each with its one-line identity. */}
      <div className="biglist stations">
        {cat.stations.map((s) => {
          const on = player.mode === "live" && player.station === s.id;
          return (
            <button key={s.id} className={s.tracks === 0 ? "empty" : on ? "on" : ""} disabled={s.tracks === 0} onClick={() => { player.goLive(s.id); if (back) go(back.to); }}>
              {s.name}
              <sup>{s.tracks === 0 ? "(empty)" : `(${String(s.tracks)})`}</sup>
              {on && (<><i className="dot" aria-hidden="true" /><span className="sr"> playing now</span></>)}
              <small className="station-line">{stationLine(s.name, s.genre)}</small>
            </button>
          );
        })}
      </div>
      <Proof page={gnowebOf({ k: "stations" })} code={codeURL("radio")} label="the stations" />
    </section>
  );
}

/** isSearchShortcut: "/" or ⌘K / Ctrl+K focuses the Library search, unless typing elsewhere. */
const isSearchShortcut = (e: Pick<KeyboardEvent, "key" | "metaKey" | "ctrlKey">, typing: boolean): boolean =>
  (e.key === "k" && (e.metaKey || e.ctrlKey)) || (e.key === "/" && !typing);

/** Mark highlights the first case-insensitive match of q in text. */
function Mark({ text, q }: { readonly text: string; readonly q: string }) {
  const i = q ? text.toLowerCase().indexOf(q.toLowerCase()) : -1;
  if (i < 0) return <>{text}</>;
  return <>{text.slice(0, i)}<mark>{text.slice(i, i + q.length)}</mark>{text.slice(i + q.length)}</>;
}

const ORDERS: readonly (readonly [TrackOrder, string])[] = [["mix", "Mix of the day"], ["liked", "Most liked"], ["tipped", "Most tipped"], ["new", "Newest"]];

const NONE: readonly never[] = [];

/** Library leads with a search and genre filters, then the tracks. */
export function Library({ cat, player, go, genre, actions, saved }: ViewProps & { readonly genre: number; readonly actions: Actions; readonly saved: Saved & { readonly ids: readonly number[] } }) {
  const [raw, setRaw] = useState("");
  const [q, setQ] = useState("");
  useEffect(() => { const id = window.setTimeout(() => { setQ(raw.trim()); }, 120); return () => { window.clearTimeout(id); }; }, [raw]);
  const input = useRef<HTMLInputElement>(null);
  useEffect(() => {
    const onKey = (e: KeyboardEvent) => {
      const el = e.target instanceof HTMLElement ? e.target : null;
      if (isSearchShortcut(e, Boolean(el?.closest("input, textarea, select, [contenteditable]")))) { e.preventDefault(); input.current?.focus(); }
    };
    const onOpen = () => { input.current?.focus(); };
    window.addEventListener("keydown", onKey);
    window.addEventListener(SEARCH_EVENT, onOpen);
    return () => { window.removeEventListener("keydown", onKey); window.removeEventListener(SEARCH_EVENT, onOpen); };
  }, []);
  useWant(q ? cat.tracks : NONE); // a search reads every pointer's title
  // A search index built once per catalog: folded (lowercase, no accents) strings.
  const index = useMemo(() => ({
    tracks: cat.tracks.map((t) => ({ t, k: fold(`${t.title} ${t.artistName} ${t.credits}`) })),
    artists: [...cat.artists.values()].filter((a) => a.tracks.length > 0).map((a) => ({ a, k: fold(a.name) })),
    lists: [
      ...cat.albums.map((al) => ({ id: al.id, kind: "album" as const, title: al.title, k: fold(al.title) })),
      ...cat.playlists.map((pl) => ({ id: pl.id, kind: "playlist" as const, title: pl.title, k: fold(pl.title) })),
    ],
  }), [cat]);
  const words = fold(q).split(/\s+/).filter(Boolean);
  const hit = (k: string) => words.every((w) => k.includes(w));
  // Measured by how many tracks a search finds, never by what was typed.
  useEffect(() => {
    if (q) track("search", { results: bucket(index.tracks.filter((x) => hit(x.k)).length) });
    // eslint-disable-next-line react-hooks/exhaustive-deps -- once per settled query
  }, [q]);
  const found = words.length === 0 ? null : {
    artists: index.artists.filter((x) => hit(x.k)).slice(0, 4).map((x) => x.a),
    tracks: index.tracks.filter((x) => hit(x.k)).slice(0, 8).map((x) => x.t),
    lists: index.lists.filter((x) => hit(x.k)).slice(0, 6),
  };
  const counts = new Map<number, number>();
  const usedArtists = new Set<number>(); // genre cards: one cover per artist
  for (const t of cat.tracks) counts.set(t.genre, (counts.get(t.genre) ?? 0) + 1);
  const [order, setOrder] = useState<TrackOrder>("mix");
  const inGenre = useMemo(() => sortTracks(genre ? cat.tracks.filter((t) => t.genre === genre) : cat.tracks, order), [cat.tracks, genre, order]);
  const orders = (
    <div className="chips sort-tabs" role="group" aria-label="Order">
      {ORDERS.map(([o, label]) => <button key={o} className="chip" aria-pressed={o === order} onClick={() => { setOrder(o); }}>{label}</button>)}
    </div>
  );
  const tab = (id: number, label: string, n: number) => (
    <button key={id} className={`gtab${genre === id ? " on" : ""}`} aria-pressed={genre === id} onClick={() => { go({ k: "library", genre: id }); }}>
      {id ? <GenreGlyph id={id} muted={genre !== id} /> : <Shape g="circle" size={12} fill={genre === 0 ? "var(--ink)" : "var(--tick)"} />}
      {label} <span className="muted">{n}</span>
    </button>
  );
  return (
    <section>
      <label className="bigsearch">
        <Icon name="search" size={22} />
        <span className="sr">Search tracks, artists, albums and playlists</span>
        <input
          ref={input}
          value={raw}
          placeholder={cat.tracks.length > 0 ? `Search ${cat.tracks.length.toLocaleString("en")} tracks, ${index.artists.length.toLocaleString("en")} artists…` : "Search the library"}
          onChange={(e) => { setRaw(e.target.value); }}
          onKeyDown={(e) => {
            if (e.key === "Escape") { setRaw(""); setQ(""); }
            else if (e.key === "Enter" && found?.tracks[0]) player.playList(found.tracks.map((t) => t.id), 0);
          }}
        />
        {raw.trim() !== q ? <Loader label="Searching" /> : <kbd>/</kbd>}
      </label>
      {found ? (
        <div className="results">
          {found.artists.length + found.tracks.length + found.lists.length === 0 && (
            <p className="muted">Nothing for “{q}”. Try an artist, a title, or a genre below.</p>
          )}
          {found.artists.length > 0 && (
            <>
              <h3 className="sub">Artists</h3>
              <div className="aresults">
                {found.artists.map((a) => {
                  const g = (["circle", "square", "quarter", "triangle"] as const)[a.id % 4] ?? "circle";
                  const fill = ["var(--red)", "var(--yellow)", "var(--blue)", "var(--ink)"][a.id % 4] ?? "var(--ink)";
                  return (
                    <button key={a.id} className="aresult" onClick={() => { go({ k: "artist", id: a.id }); }}>
                      <span className="aresult-glyph" aria-hidden="true"><Shape g={g} size={20} fill={fill} /></span>
                      <span className="aresult-txt"><b><Mark text={a.name} q={q} /></b><small>{plural(a.tracks.length, "track")}{a.owner ? " · on GnoRadio" : a.kind === "audius" ? " · via Audius" : ""}</small></span>
                      <Icon name="arrow-right" className="nudge" />
                    </button>
                  );
                })}
              </div>
            </>
          )}
          {found.tracks.length > 0 && (
            <>
              <h3 className="sub">Tracks <span className="muted small">· Enter plays the first</span></h3>
              <TrackRows tracks={found.tracks} player={player} actions={actions} saved={saved} />
            </>
          )}
          {found.lists.length > 0 && (
            <>
              <h3 className="sub">Albums and playlists</h3>
              <div className="chips">{found.lists.map((x) => <button key={`${x.kind}${String(x.id)}`} className="chip" onClick={() => { go({ k: x.kind, id: x.id }); }}><Mark text={x.title} q={q} /></button>)}</div>
            </>
          )}
        </div>
      ) : (
        <>
          {genre === 0 && <MineLinks go={go} saved={saved.ids.length} liked={actions.liked.size} />}
          {genre === 0 ? (
            // Browse: one colour card per genre, Spotify-style, with a tilted cover from that genre.
            <div className="gcards" role="list" aria-label="Genres">
              {cat.genres.filter((g) => counts.has(g.id)).map((g, i) => {
                // A track with real artwork, by an artist no earlier card used: no generated look-alikes.
                const lead = cat.tracks.find((t) => t.genre === g.id && t.cover !== "" && !usedArtists.has(t.artist)) ?? cat.tracks.find((t) => t.genre === g.id);
                if (lead) usedArtists.add(lead.artist);
                return (
                  <button key={g.id} role="listitem" className={`gcard c${String(i % 4)}`} onClick={() => { go({ k: "library", genre: g.id }); }}>
                    <b>{g.name}</b>
                    <span className="gcard-n">{plural(counts.get(g.id) ?? 0, "track")}</span>
                    <span className="gcard-glyph" aria-hidden="true"><GenreGlyph id={g.id} size={22} /></span>
                    {lead && <span className="gcard-cover" aria-hidden="true"><Cover t={lead} /></span>}
                  </button>
                );
              })}
            </div>
          ) : (
            <div className="gtabs" role="group" aria-label="Genres">
              {tab(0, "All", cat.tracks.length)}
              {cat.genres.filter((g) => counts.has(g.id)).map((g) => tab(g.id, g.name, counts.get(g.id) ?? 0))}
            </div>
          )}
          {genre === 0 ? <h3 className="sub sub-row">All tracks {orders}</h3> : inGenre.length > 0 && (
            <div className="head-actions genre-play"><PlayButton label="Play all" tracks={inGenre} onClick={() => { player.playList(inGenre.map((t) => t.id), 0); }} />{orders}</div>
          )}
          {inGenre.length === 0 ? <Empty text={NO_TRACK}><MakeMusic go={go} /></Empty> : <TrackRows key={`${String(genre)}/${order}`} tracks={inGenre} player={player} actions={actions} saved={saved} />}
          {cat.albums.length > 0 && (
            <>
              <h3 className="sub">Albums</h3>
              <div className="chips">{cat.albums.map((al) => <button key={al.id} className="chip" onClick={() => { go({ k: "album", id: al.id }); }}>{al.title}</button>)}</div>
            </>
          )}
        </>
      )}
    </section>
  );
}
