import { useState } from "react";
import { BigList, Count, Head, TrackCards, TrackRows } from "../components/common";
import { tracksOf } from "../lib/catalog";
import { clock, gnot } from "../lib/format";
import { ActivityFeed } from "../components/ActivityFeed";
import { Shape } from "../components/Shapes";
import type { SupportTarget } from "../components/SupportSheet";
import type { Activity, Catalog, Navigate, SupportInfo } from "../lib/types";
import type { Player } from "../player/usePlayer";

interface ViewProps {
  readonly cat: Catalog;
  readonly player: Player;
  readonly go: Navigate;
}

export function Listen({ cat, player, go, activity, support, now, openSupport }: ViewProps & {
  readonly activity: readonly Activity[];
  readonly support: SupportInfo;
  readonly now: number;
  readonly openSupport: (t: SupportTarget) => void;
}) {
  const main = cat.stations[0];
  const onAir = main ? cat.byId.get(main.now.track) : undefined;
  const fresh = [...cat.tracks].sort((a, b) => b.id - a.id).slice(0, 8);
  const claimed = [...cat.artists.values()].filter((a) => a.owner && a.tracks.length > 0).sort((a, b) => b.tips - a.tips).slice(0, 4);
  const goal = support.goal > 0 ? support.goal : 50 * 1_000_000;
  return (
    <section>
      <div className="hero">
        <button className="onair" onClick={() => { player.goLive(0); }}>
          <span className="chip red"><Shape g="circle" size={9} fill="#fff" /> On air · Main</span>
          <span className="onair-title">{onAir?.title ?? "Nothing on air yet"}</span>
          <span className="muted">{onAir && main ? `${onAir.artistName} · join at ${clock(main.now.offset)} · same second for everyone` : "Publish or import the first track."}</span>
          <span className="go">Go live →</span>
        </button>
        <button className="pulse-card" onClick={() => { go({ k: "community" }); }}>
          <span className="lbl">Kept on air by listeners</span>
          <span className="big">{gnot(support.monthTotal)}</span>
          <span className="bar"><i style={{ width: `${String(Math.min(100, (support.monthTotal / goal) * 100))}%` }} /></span>
          <span className="muted small">of {gnot(goal)} this month · {support.supporters} supporters</span>
        </button>
      </div>

      <div className="cols">
        <div>
          <h3 className="sub">Community pulse <span className="live-dot" aria-hidden="true" /></h3>
          <ActivityFeed items={activity.slice(0, 8)} cat={cat} go={go} now={now} compact />
          <button className="link small" onClick={() => { go({ k: "community" }); }}>All activity →</button>
        </div>
        <div>
          <h3 className="sub">Support an artist</h3>
          {claimed.length === 0 && <p className="muted">Artists who claimed their profile appear here. Every tip reaches them in the same transaction.</p>}
          <div className="artists">
            {claimed.map((a) => {
              const first = cat.byId.get(a.tracks[a.tracks.length - 1] ?? 0);
              return (
                <div key={a.id} className="artist-card">
                  <button className="name" onClick={() => { go({ k: "artist", id: a.id }); }}>{a.name}</button>
                  <span className="muted small">{gnot(a.tips)} raised · {a.followers} followers</span>
                  {first && <button className="cta yellow" onClick={() => { openSupport({ kind: "tip", track: first, artist: a }); }}><Shape g="square" size={10} fill="var(--ink)" /> Tip</button>}
                </div>
              );
            })}
          </div>
        </div>
      </div>

      <h3 className="sub">New releases</h3>
      <TrackCards tracks={fresh} player={player} meta={(t) => `${t.artistName} · ♥ ${String(t.likes)}`} />
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

export function Stations({ cat, player }: Omit<ViewProps, "go">) {
  return (
    <section>
      <Head a="Choose" b="Station" note="Each station plays the same second for everyone." right={<Count label="All" value={cat.stations.length} />} />
      <BigList
        items={cat.stations.map((s) => ({
          key: s.id,
          label: s.name,
          count: s.tracks,
          dim: s.tracks === 0,
          live: player.mode === "live" && player.station === s.id,
          onClick: () => { if (s.tracks > 0) player.goLive(s.id); },
        }))}
      />
    </section>
  );
}

export function Library({ cat, player, go, genre }: ViewProps & { readonly genre: number }) {
  const counts = new Map<number, number>();
  for (const t of cat.tracks) counts.set(t.genre, (counts.get(t.genre) ?? 0) + 1);
  const list = genre ? cat.tracks.filter((t) => t.genre === genre) : cat.tracks;
  const genreName = cat.genres.find((g) => g.id === genre)?.name ?? "All genres";
  return (
    <section>
      <Head a="Choose" b="Genre" right={<Count label="All" value={cat.tracks.length} />} />
      <BigList
        compact
        items={[
          { key: 0, label: "All", count: cat.tracks.length, dim: genre !== 0, onClick: () => { go({ k: "library", genre: 0 }); } },
          ...cat.genres
            .filter((g) => counts.has(g.id))
            .map((g) => ({ key: g.id, label: g.name, count: counts.get(g.id) ?? 0, dim: genre !== g.id, onClick: () => { go({ k: "library", genre: g.id }); } })),
        ]}
      />
      <h3 className="sub">Tracks · {genreName}</h3>
      <TrackRows tracks={list} player={player} />
      <h3 className="sub">Artists</h3>
      <BigList compact items={[...cat.artists.values()].map((a) => ({ key: a.id, label: a.name, count: a.tracks.length, onClick: () => { go({ k: "artist", id: a.id }); } }))} />
    </section>
  );
}

export function Search({ cat, player, go }: ViewProps) {
  const [q, setQ] = useState("");
  const s = q.trim().toLowerCase();
  const tracks = s ? cat.tracks.filter((t) => `${t.title} ${t.artistName} ${t.credits}`.toLowerCase().includes(s)) : [];
  const artists = s ? [...cat.artists.values()].filter((a) => a.name.toLowerCase().includes(s)) : [];
  return (
    <section>
      <label className="search">
        <span className="sr">Search tracks and artists</span>
        <input autoFocus value={q} onChange={(e) => { setQ(e.target.value); }} placeholder="Search" />
      </label>
      {s && (
        <>
          <h3 className="sub">Tracks · {tracks.length}</h3>
          <TrackRows tracks={tracks} player={player} />
          <h3 className="sub">Artists · {artists.length}</h3>
          <BigList compact items={artists.map((a) => ({ key: a.id, label: a.name, onClick: () => { go({ k: "artist", id: a.id }); } }))} />
        </>
      )}
    </section>
  );
}

export function Saved({ cat, player, ids }: Omit<ViewProps, "go"> & { readonly ids: readonly number[] }) {
  return (
    <section>
      <Head a="Saved" b="tracks" note="Stored in this browser only. Free, private, no wallet needed." />
      {ids.length === 0 ? <p className="muted">Save a track with the bookmark in the player.</p> : <TrackRows tracks={tracksOf(cat, ids)} player={player} />}
    </section>
  );
}
