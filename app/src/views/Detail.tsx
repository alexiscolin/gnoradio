import { BigList, Head, TrackCards, TrackRows } from "../components/common";
import { Cover } from "../components/Cover";
import { tracksOf } from "../lib/catalog";
import { clock, gnot, hostOf, licenseLabel, shortAddr } from "../lib/format";
import type { Catalog, Navigate } from "../lib/types";
import type { Actions } from "../player/useActions";
import type { Player } from "../player/usePlayer";
import { Shape } from "../components/Shapes";
import type { SupportTarget } from "../components/SupportSheet";

interface DetailProps {
  readonly cat: Catalog;
  readonly player: Player;
  readonly go: Navigate;
  readonly id: number;
}

export function ArtistView({ cat, player, go, id, actions, openSupport }: DetailProps & { readonly actions: Actions; readonly openSupport: (t: SupportTarget) => void }) {
  const a = cat.artists.get(id);
  if (!a) return <p className="muted">Unknown artist.</p>;
  const [first = a.name, ...rest] = a.name.split(" ");
  const tracks = tracksOf(cat, a.tracks);
  return (
    <section>
      <div className="artist-head">
        <h1>
          {first}
          {rest.length > 0 && (<><br /><span>{rest.join(" ")}</span></>)}
          <i className="dot" />
        </h1>
        <span className="count">
          <span className="muted small">{a.owner ? "Received in tips" : a.kind === "audius" ? "Streamed from" : "Curated CC artist"}</span>
          <b>{a.owner ? gnot(a.tips) : a.kind === "audius" ? "Audius" : "CC"}</b>
          <span className="muted small">{a.followers} followers</span>
        </span>
      </div>
      {a.bio && <p className="bio">{a.bio}</p>}
      <div className="actions inline">
        {a.owner && tracks[0] && (
          <button className="cta yellow" onClick={() => { if (tracks[0]) openSupport({ kind: "tip", track: tracks[0], artist: a }); }}>
            <Shape g="square" size={12} fill="var(--ink)" /> Support {a.name}
          </button>
        )}
        <button onClick={() => { actions.follow(a.id); }}>Follow · {a.followers}</button>
        {a.source && <a className="btn" href={a.source} target="_blank" rel="noreferrer">{a.kind === "audius" ? "On Audius" : "Source"}</a>}
      </div>
      {!a.owner && <p className="muted small">Unclaimed profile. Is this you? Claim it from the GnoRadio site to receive tips.</p>}
      <h3 className="sub">Tracks</h3>
      <TrackCards tracks={tracks} player={player} meta={(t) => `${clock(t.duration)} · ♥ ${String(t.likes)}`} />
      {a.albums.length > 0 && (
        <>
          <h3 className="sub">Albums</h3>
          <BigList
            compact
            items={cat.albums.filter((al) => a.albums.includes(al.id)).map((al) => ({ key: al.id, label: al.title, count: al.year, onClick: () => { go({ k: "album", id: al.id }); } }))}
          />
        </>
      )}
    </section>
  );
}

export function AlbumView({ cat, player, go, id }: DetailProps) {
  const al = cat.albums.find((x) => x.id === id);
  if (!al) return <p className="muted">Unknown album.</p>;
  const tracks = tracksOf(cat, al.tracks);
  const total = tracks.reduce((s, t) => s + t.duration, 0);
  const shuffled = () => [...al.tracks].map((x) => ({ x, r: Math.random() })).sort((p, q) => p.r - q.r).map(({ x }) => x);
  return (
    <section>
      <div className="album-head">
        <Cover t={tracks[0]} size="220px" />
        <div>
          <span className="muted small">Album · {al.year}</span>
          <h1 className="album-title">{al.title}</h1>
          <button className="link" onClick={() => { go({ k: "artist", id: al.artist }); }}>{cat.artists.get(al.artist)?.name}</button>
          <p className="muted small">{tracks.length} tracks · {clock(total)}</p>
          <div className="actions inline">
            <button className="play" onClick={() => { player.playList(al.tracks, 0); }}>Play album</button>
            <button onClick={() => { player.playList(shuffled(), 0); }}>Shuffle</button>
          </div>
        </div>
      </div>
      <TrackRows tracks={tracks} player={player} />
    </section>
  );
}

export function PlaylistView({ cat, player, id }: Omit<DetailProps, "go">) {
  const pl = cat.playlists.find((x) => x.id === id);
  if (!pl) return <p className="muted">Unknown playlist.</p>;
  return (
    <section>
      <Head a={pl.title} note={`Public playlist by ${shortAddr(pl.owner)}`} />
      <div className="actions inline">
        <button className="play" onClick={() => { player.playList(pl.tracks, 0); }}>Play</button>
      </div>
      <TrackRows tracks={tracksOf(cat, pl.tracks)} player={player} />
    </section>
  );
}

export function Concerts({ cat, go, actions }: { readonly cat: Catalog; readonly go: Navigate; readonly actions: Actions }) {
  return (
    <section>
      <Head a="Concerts" b="& tickets" note="Tickets are NFTs drawn on-chain. 100% of the price goes to the artist; a small service fee keeps GnoRadio running." />
      {cat.events.length === 0 && <p className="muted">No concert announced.</p>}
      <div className="tickets">
        {cat.events.map((e) => {
          const fee = e.price > 0 ? (e.fee ?? 0) : 0;
          return (
            <article key={e.id} className="ticket">
              <div>
                <span className="lbl light">GnoRadio · admit one</span>
                <b>{e.title}</b>
                <span className="muted small">{e.venue} · {new Date(e.start * 1000).toLocaleString([], { dateStyle: "medium", timeStyle: "short" })}</span>
                <button className="link light" onClick={() => { go({ k: "artist", id: e.artist }); }}>{cat.artists.get(e.artist)?.name}</button>
                <button className="cta yellow" disabled={e.sold >= e.capacity || e.cancelled} onClick={() => { actions.buyTicket(e); }}>
                  {e.cancelled ? "Cancelled" : e.sold >= e.capacity ? "Sold out" : e.price > 0 ? `Buy · ${gnot(e.price)}${fee ? ` + ${gnot(fee)} fee` : ""}` : "Get a free ticket"}
                </button>
              </div>
              <div className="stub">
                <span className="mono">{e.sold}/{e.capacity}</span>
                <Shape g="square" size={26} />
              </div>
            </article>
          );
        })}
      </div>
    </section>
  );
}

/** TrackView is the shareable page of one track: play, support, queue, proof. */
export function TrackView({ cat, player, go, id, actions, openSupport }: DetailProps & { readonly actions: Actions; readonly openSupport: (t: SupportTarget) => void }) {
  const t = cat.byId.get(id);
  if (!t) return <p className="muted">This track is not available.</p>;
  const a = cat.artists.get(t.artist);
  const genre = cat.genres.find((g) => g.id === t.genre)?.name ?? "";
  const artistPct = 100 - t.splits.reduce((s, x) => s + x.pct, 0);
  return (
    <section>
      <div className="album-head">
        <Cover t={t} size="240px" />
        <div>
          <span className="muted small">{genre} · {clock(t.duration)}</span>
          <h1 className="album-title">{t.title}</h1>
          <button className="link" onClick={() => { go({ k: "artist", id: t.artist }); }}>{t.artistName}</button>
          <div className="actions inline">
            <button className="play" onClick={() => { player.playList([t.id], 0); }}>Play</button>
            {a?.owner && <button className="cta yellow" onClick={() => { openSupport({ kind: "tip", track: t, artist: a }); }}><Shape g="square" size={12} fill="var(--ink)" /> Support</button>}
            <button onClick={() => { actions.like(t); }}><Shape g="circle" size={12} /> Like · {t.likes}</button>
            <button onClick={() => { actions.queue(t, 0); }}><Shape g="quarter" size={12} /> Queue on Main</button>
            <button onClick={() => { actions.queue(t, t.genre); }}>Queue on {cat.stations.find((s) => s.id === t.genre)?.name}</button>
          </div>
        </div>
      </div>
      <div className="cols">
        <div>
          <h3 className="sub">Where support goes</h3>
          {a?.owner ? (
            <div className="flow plain">
              <div><span>{t.artistName} <span className="muted">artist</span></span><b className="mono">{artistPct}%</b></div>
              {t.splits.map((s) => <div key={s.to}><span className="mono">{shortAddr(s.to)} <span className="muted">collaborator</span></span><b className="mono">{s.pct}%</b></div>)}
              <div className="total"><span>Raised</span><b className="mono">{gnot(t.tips)} · {t.supporters} supporters</b></div>
            </div>
          ) : (
            <p className="muted">Unclaimed profile: tips open when {t.artistName} claims it.</p>
          )}
        </div>
        <div>
          <h3 className="sub">Rights</h3>
          <p>{t.origin === "audius" ? "Audius Open Music License" : licenseLabel(t.license)}{t.credits ? ` · ${t.credits}` : ""}</p>
          {t.attribution && <p className="muted small">{t.attribution}</p>}
          {t.source && <a className="link small" href={t.source} target="_blank" rel="noreferrer">Source: {hostOf(t.source)}</a>}
          <p className="muted small mono">{t.audio}</p>
        </div>
      </div>
    </section>
  );
}
