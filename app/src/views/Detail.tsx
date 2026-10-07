import { Help } from "../components/Help";
import { Icon } from "../components/Icons";
import { useNames } from "../lib/names";
import { type Crumb, Crumbs, FollowButton, Head, LikeButton, Proof, ShareButton, TrackCards, TrackRows, rightsLabel, sharedValue } from "../components/common";
import { Cover } from "../components/Cover";
import { tracksOf } from "../lib/catalog";
import { clock, gnot, hostOf, licenseLabel, plural, shortAddr } from "../lib/format";
import { codeURL, gnowebOf } from "../lib/links";
import type { Catalog, Navigate } from "../lib/types";
import type { Actions } from "../player/useActions";
import type { Player } from "../player/usePlayer";
import { Shape } from "../components/Shapes";
import { VerifyPanel, VerifyStatus, tippable, useClaim } from "../components/Verify";
import { useState } from "react";
import type { SupportTarget } from "../components/SupportSheet";

const LIBRARY: Crumb = { label: "Library", to: { k: "library", genre: 0 } };
const artistCrumb = (cat: Catalog, id: number): Crumb => ({ label: cat.artists.get(id)?.name ?? "Artist", to: { k: "artist", id } });

interface DetailProps {
  readonly cat: Catalog;
  readonly player: Player;
  readonly go: Navigate;
  readonly id: number;
}

export function ArtistView({ cat, player, go, id, actions, openSupport }: DetailProps & { readonly actions: Actions; readonly openSupport: (t: SupportTarget) => void }) {
  const [verifying, setVerifying] = useState(false);
  const [refresh, setRefresh] = useState(0);
  const claim = useClaim(id, refresh);
  const a = cat.artists.get(id);
  if (!a) return <p className="muted">Unknown artist.</p>;
  const [first = a.name, ...rest] = a.name.split(" ");
  const tracks = tracksOf(cat, a.tracks);
  const albums = cat.albums.filter((al) => a.albums.includes(al.id));
  const paid = tippable(a);
  return (
    <section>
      <Crumbs trail={[LIBRARY, { label: a.name }]} go={go} />
      <div className="artist-head">
        <h1>
          {first}
          {rest.length > 0 && (<><br /><span>{rest.join(" ")}</span></>)}
          <i className="dot" />
        </h1>
        <span className="count">
          <span className="muted small">{paid ? "Received in tips" : a.kind === "audius" ? "Streamed from" : a.kind === "curated" ? "Curated CC artist" : "On GnoRadio"}</span>
          <b>{paid ? gnot(a.tips) : a.kind === "audius" ? "Audius" : a.kind === "curated" ? "CC" : plural(tracks.length, "track")}</b>
          <span className="muted small">{plural(a.followers, "follower")}</span>
        </span>
      </div>
      {a.bio && <p className="bio">{a.bio}</p>}
      <div className="actions inline">
        {paid && tracks[0] && (
          <button className="cta yellow" onClick={() => { if (tracks[0]) openSupport({ kind: "tip", track: tracks[0], artist: a }); }}>
            <Shape g="square" size={12} fill="var(--ink)" /> Support {a.name}
          </button>
        )}
        <FollowButton artist={a.id} followers={a.followers} actions={actions} />
        {a.source && <a className="btn" href={a.source} target="_blank" rel="noreferrer">{a.kind === "audius" ? "On Audius" : "Source"}</a>}
        <ShareButton title={a.name} />
      </div>
      <div className="artist-meta">
        <VerifyStatus a={a} claim={claim} onVerify={() => { setVerifying(true); }} />
        <Proof page={gnowebOf({ k: "artist", id: a.id })} code={codeURL("artist")} />
      </div>
      {verifying && !a.verified && <VerifyPanel a={a} claim={claim} actions={actions} onClose={() => { setVerifying(false); }} onChange={() => { setRefresh((n) => n + 1); }} />}
      {albums.length > 0 && (
        <>
          <h3 className="sub">Albums</h3>
          <div className="album-cards">
            {albums.map((al) => (
              <div key={al.id} className="album-card">
                <button className="album-open" onClick={() => { go({ k: "album", id: al.id }); }}>
                  <Cover t={cat.byId.get(al.tracks[0] ?? 0)} size="100%" />
                  <b>{al.title}</b>
                  <span className="muted small">{al.year} · {plural(al.tracks.length, "track")}</span>
                </button>
                <span className="album-play-zone">
                  <button className="album-play" onClick={() => { player.playList(al.tracks, 0); }} aria-label={`Play ${al.title}`} title={`Play ${al.title}`}>
                    <Icon name="play" size={18} />
                  </button>
                </span>
              </div>
            ))}
          </div>
        </>
      )}
      <h3 className="sub">Tracks</h3>
      <TrackCards tracks={tracks} player={player} meta={(t) => `${clock(t.duration)} · ♥ ${String(t.likes)}`} />
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
      <Crumbs trail={[LIBRARY, artistCrumb(cat, al.artist), { label: al.title }]} go={go} />
      <div className="album-head">
        <Cover t={tracks[0]} size="220px" />
        <div>
          <span className="muted small">Album · {al.year}</span>
          <h1 className="album-title">{al.title}</h1>
          <button className="link" onClick={() => { go({ k: "artist", id: al.artist }); }}>{cat.artists.get(al.artist)?.name}</button>
          <p className="muted small">{[plural(tracks.length, "track"), clock(total), sharedValue(tracks, rightsLabel)].filter(Boolean).join(" · ")}</p>
          <div className="actions inline">
            <button className="play" onClick={() => { player.playList(al.tracks, 0); }}>Play album</button>
            <button onClick={() => { player.playList(shuffled(), 0); }}>Shuffle</button>
            <ShareButton title={al.title} />
          </div>
        </div>
      </div>
      <TrackRows tracks={tracks} player={player} />
      <Proof page={gnowebOf({ k: "album", id: al.id })} code={codeURL("playlist")} />
    </section>
  );
}

export function PlaylistView({ cat, player, go, id }: DetailProps) {
  const pl = cat.playlists.find((x) => x.id === id);
  const who = useNames(pl ? [pl.owner] : []);
  if (!pl) return <p className="muted">Unknown playlist.</p>;
  return (
    <section>
      <Crumbs trail={[LIBRARY, { label: pl.title }]} go={go} />
      <Head a={pl.title} note={`Public playlist by ${who(pl.owner)} · ${plural(pl.tracks.length, "track")}`}
        right={<div className="head-actions"><ShareButton title={pl.title} /><button className="cta head-play" onClick={() => { player.playList(pl.tracks, 0); }}><Icon name="play" size={18} /> Play</button></div>} />
      <TrackRows tracks={tracksOf(cat, pl.tracks)} player={player} />
      <Proof page={gnowebOf({ k: "playlist", id: pl.id })} code={codeURL("playlist")} />
    </section>
  );
}

export function Concerts({ cat, go, actions }: { readonly cat: Catalog; readonly go: Navigate; readonly actions: Actions }) {
  return (
    <section>
      <Head a="Concerts" b="& tickets" note="Tickets are NFTs drawn on-chain. 100% of the price goes to the artist; a small service fee keeps GnoRadio running." />
      {cat.events.length === 0 && <p className="muted">No concert announced.</p>}
      <Proof page={gnowebOf({ k: "concerts" })} code={codeURL("tickets")} />
      <div className="tickets">
        {cat.events.map((e) => {
          const fee = e.price > 0 ? (e.fee ?? 0) : 0;
          const locked = e.price > 0 && !tippable(cat.artists.get(e.artist));
          return (
            <article key={e.id} className="ticket">
              <div>
                <span className="lbl light">GnoRadio · admit one</span>
                <b>{e.title}</b>
                <span className="muted small">{e.venue} · {new Date(e.start * 1000).toLocaleString("en", { month: "short", day: "numeric", year: "numeric", hour: "2-digit", minute: "2-digit", hourCycle: "h23", timeZoneName: "short" })}</span>
                <button className="link light" onClick={() => { go({ k: "artist", id: e.artist }); }}>{cat.artists.get(e.artist)?.name}</button>
                {fee > 0 && <Help text="The price goes 100% to the artist. The small service fee, paid on top, keeps GnoRadio running." />}
                <button className="cta yellow" disabled={e.sold >= e.capacity || e.cancelled || locked} title={locked ? "Paid tickets open once the artist verifies their profile" : undefined} onClick={() => { actions.buyTicket(e); }}>
                  {e.cancelled ? "Cancelled" : e.sold >= e.capacity ? "Sold out" : locked ? "Artist not verified yet" : e.price > 0 ? `Buy · ${gnot(e.price)}${fee ? ` + ${gnot(fee)} fee` : ""}` : "Get a free ticket"}
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
export function TrackView({ cat, player, go, id, actions, openSupport, openPick }: DetailProps & { readonly actions: Actions; readonly openSupport: (t: SupportTarget) => void; readonly openPick: (station: number, track?: number) => void }) {
  const t = cat.byId.get(id);
  if (!t) return <p className="muted">This track is not available.</p>;
  const a = cat.artists.get(t.artist);
  const genre = cat.genres.find((g) => g.id === t.genre)?.name ?? "";
  const artistPct = 100 - t.splits.reduce((s, x) => s + x.pct, 0);
  return (
    <section>
      <Crumbs trail={[LIBRARY, artistCrumb(cat, t.artist), { label: t.title }]} go={go} />
      <div className="album-head">
        <Cover t={t} size="240px" />
        <div>
          <span className="muted small">{genre} · {clock(t.duration)}</span>
          <h1 className="album-title">{t.title}</h1>
          <button className="link" onClick={() => { go({ k: "artist", id: t.artist }); }}>{t.artistName}</button>
          <div className="actions inline">
            <button className="play" onClick={() => { player.playList([t.id], 0); }}>Play</button>
            {tippable(a) && a && <button className="cta yellow" onClick={() => { openSupport({ kind: "tip", track: t, artist: a }); }}><Shape g="square" size={12} fill="var(--ink)" /> Support</button>}
            <LikeButton t={t} actions={actions} />
            <Help text="Likes are public and on-chain. The first one locks a small storage deposit (about 0.3 GNOT); Unlike frees it." />
            <button className="onchain" title="Choose a station in the next step · public, on-chain" onClick={() => { openPick(cat.stations.some((x) => x.id === t.genre) ? t.genre : 0, t.id); }}><Shape g="quarter" size={12} /> Pick next</button>
            <ShareButton title={t.title} />
          </div>
        </div>
      </div>
      <div className="cols">
        {tippable(a) && (
          <div>
            <h3 className="sub">Where support goes</h3>
            <div className="flow plain">
              <div><span>{t.artistName} <span className="muted">artist</span></span><b className="mono">{artistPct}%</b></div>
              {t.splits.map((s) => <div key={s.to}><span className="mono">{shortAddr(s.to)} <span className="muted">collaborator</span></span><b className="mono">{s.pct}%</b></div>)}
              <div className="total"><span>Raised</span><b className="mono">{gnot(t.tips)} · {plural(t.supporters, "supporter")}</b></div>
            </div>
          </div>
        )}
        <div>
          <h3 className="sub">Rights</h3>
          <p>{t.origin === "audius" ? "Audius Open Music License" : licenseLabel(t.license)}{t.credits ? ` · ${t.credits}` : ""}</p>
          {t.attribution && <p className="muted small">{t.attribution}</p>}
          {t.source && <a className="link small" href={t.source} target="_blank" rel="noreferrer" title={t.source}>Source · {hostOf(t.source)}</a>}
        </div>
      </div>
      <Proof page={gnowebOf({ k: "track", id: t.id })} code={codeURL("tip")} />
    </section>
  );
}
