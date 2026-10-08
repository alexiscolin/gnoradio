import { Icon } from "../components/Icons";
import { useNames } from "../lib/names";
import { Confirm, type Crumb, Crumbs, Empty, FollowButton, Head, LIBRARY, LikeButton, Proof, ShareButton, TrackCards, TrackRows, Who, rightsLabel, sharedValue, walletOf } from "../components/common";
import { Cover } from "../components/Cover";
import { tracksOf } from "../lib/catalog";
import { clock, gnot, hostOf, licenseLabel, licenseURL, plural, shortAddr } from "../lib/format";
import { REALMS, qeval, unquote } from "../lib/gno";
import type { Artist, Catalog, ConcertEvent, Navigate, OwnedTicket } from "../lib/types";
import { CHECK_IN, type ConcertFilter, NO_FILTER, REFUND, REFUND_SHORT, almostFull, byMonth, cities, filterConcerts } from "../lib/concerts";
import { loadTicketsOf, useEvents } from "../lib/community";
import { useFees } from "../lib/fees";
import { codeURL, eventPage, gnowebOf, txURL } from "../lib/links";
import { EditTrackForm, PlaylistForm } from "./Contribute";
import type { Actions } from "../player/useActions";
import type { Saved } from "../lib/saved";
import type { Player } from "../player/usePlayer";
import { PlayButton } from "../components/PlayButton";
import { UNAVAILABLE, isDead, usePlayable } from "../lib/playable";
import { Shape } from "../components/Shapes";
import { VerifyPanel, VerifyStatus, tippable, useClaim } from "../components/Verify";
import { useEffect, useState } from "react";
import type { SupportTarget } from "../components/SupportSheet";

const artistCrumb = (cat: Catalog, id: number): Crumb => ({ label: cat.artists.get(id)?.name ?? "Artist", to: { k: "artist", id } });

/** License names a license and links its text when it has one. */
function License({ id }: { readonly id: string }) {
  const url = licenseURL(id);
  return url ? <a href={url} target="_blank" rel="noreferrer">{licenseLabel(id)}</a> : <>{licenseLabel(id)}</>;
}

/**
 * Unavailable stands in for a missing page, saying why when it was hidden
 * (catalog HiddenNote), with a way back. An artist may show again a track or
 * album they hid themselves (the realm refuses anyone else).
 */
function Unavailable({ kind, id, go, actions, cat }: { readonly kind: "track" | "artist" | "album" | "playlist"; readonly id: number; readonly go: Navigate; readonly actions?: Actions; readonly cat?: Catalog }) {
  const [note, setNote] = useState("");
  useEffect(() => {
    qeval(REALMS.catalog, `HiddenNote(${JSON.stringify(kind)}, ${String(id)})`).then((r) => { setNote(unquote(r)); }, () => { setNote(""); });
  }, [kind, id]);
  const me = actions ? walletOf(actions) : "";
  const artist = me !== "" && cat !== undefined && [...cat.artists.values()].some((a) => a.owner === me);
  return (
    <section className="not-found">
      <p className="muted">{note || `This ${kind} is not available.`}</p>
      <p className="row2">
        <button className="cta" onClick={() => { go(kind === "artist" || kind === "playlist" ? { k: "library", genre: 0 } : { k: "listen" }); }}>{kind === "artist" || kind === "playlist" ? "Back to the Library" : "Back to Listen"}</button>
        {artist && actions && (kind === "track" || kind === "album") && (
          <button className="cta ghost" title="Only for the artist who hid it" onClick={() => { actions.hideOwn(kind, id, false); }}>Yours? Show it again</button>
        )}
      </p>
    </section>
  );
}

/** SupportCTA opens the Support sheet for a verified artist: yellow, the Bauhaus square, as in the player. */
function SupportCTA({ artist, onClick }: { readonly artist: Artist; readonly onClick: () => void }) {
  return <button className="cta yellow" onClick={onClick}><Shape g="square" size={12} fill="var(--ink)" /> Support {artist.name}</button>;
}

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
  usePlayable();
  const a = cat.artists.get(id);
  if (!a) return <Unavailable kind="artist" id={id} go={go} />;
  const [first = a.name, ...rest] = a.name.split(" ");
  const tracks = tracksOf(cat, a.tracks);
  const albums = cat.albums.filter((al) => a.albums.includes(al.id));
  const paid = tippable(a);
  return (
    <section className="artist-page">
      <Crumbs trail={[LIBRARY, { label: a.name }]} go={go} />
      <div className="artist-head">
        <h1>
          {first}
          {rest.length > 0 && (<><br /><span>{rest.join(" ")}</span></>)}
          <i className="dot" />
        </h1>
        <span className="count">
          <span className="muted small">{paid ? (a.tips > 0 ? "Received in tips" : "No tip yet") : a.kind === "audius" ? "Streamed from" : a.kind === "curated" ? "Curated CC artist" : "On GnoRadio"}</span>
          <b className={paid && a.tips === 0 ? "first" : undefined}>{paid ? (a.tips > 0 ? gnot(a.tips) : `Be the first to support ${a.name}`) : a.kind === "audius" ? "Audius" : a.kind === "curated" ? "CC" : plural(tracks.length, "track")}</b>
          <span className="muted small">{plural(a.followers, "follower")}</span>
        </span>
      </div>
      {a.bio && <p className="bio">{a.bio}</p>}
      <div className="actions inline">
        {tracks.length > 0 && <PlayButton label="Play all" tracks={tracks} onClick={() => { player.playList(tracks.map((t) => t.id), 0); }} />}
        {paid && tracks[0] && <SupportCTA artist={a} onClick={() => { if (tracks[0]) openSupport({ kind: "tip", track: tracks[0], artist: a }); }} />}
        <FollowButton artist={a.id} followers={a.followers} actions={actions} />
        {a.source && <a className="btn" href={a.source} target="_blank" rel="noreferrer">{a.kind === "audius" ? "On Audius" : "Source"}</a>}
        <ShareButton title={a.name} refBy={walletOf(actions)} />
      </div>
      <div className="artist-meta">
        <VerifyStatus a={a} claim={claim} onVerify={() => { setVerifying(true); }} />
        <Proof page={gnowebOf({ k: "artist", id: a.id })} code={codeURL("artist")} label={a.name} />
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
                  <button className="album-play" disabled={tracksOf(cat, al.tracks).every(isDead)} onClick={() => { player.playList(al.tracks, 0); }} aria-label={`Play ${al.title}`} title={`Play ${al.title}`}>
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

export function AlbumView({ cat, player, go, id, actions, saved, openSupport }: DetailProps & { readonly actions: Actions; readonly saved: Saved; readonly openSupport: (t: SupportTarget) => void }) {
  const al = cat.albums.find((x) => x.id === id);
  if (!al) return <Unavailable kind="album" id={id} go={go} actions={actions} cat={cat} />;
  const tracks = tracksOf(cat, al.tracks);
  const total = tracks.reduce((s, t) => s + t.duration, 0);
  const a = cat.artists.get(al.artist);
  const shuffled = () => [...al.tracks].map((x) => ({ x, r: Math.random() })).sort((p, q) => p.r - q.r).map(({ x }) => x);
  return (
    <section>
      <Crumbs trail={[LIBRARY, artistCrumb(cat, al.artist), { label: al.title }]} go={go} />
      <div className="album-head of-album">
        <Cover t={tracks[0]} size="220px" />
        <div>
          <span className="muted small">Album · {al.year}</span>
          <h1 className="album-title">{al.title}</h1>
          <button className="link" onClick={() => { go({ k: "artist", id: al.artist }); }}>{cat.artists.get(al.artist)?.name}</button>
          <p className="muted small">{[plural(tracks.length, "track"), clock(total), sharedValue(tracks, rightsLabel)].filter(Boolean).join(" · ")}</p>
          <div className="actions inline">
            <PlayButton tracks={tracks} onClick={() => { player.playList(al.tracks, 0); }} />
            {tippable(a) && a && tracks[0] && <SupportCTA artist={a} onClick={() => { if (tracks[0]) openSupport({ kind: "tip", track: tracks[0], artist: a }); }} />}
            <button onClick={() => { player.playList(shuffled(), 0); }}>Shuffle</button>
            <ShareButton title={al.title} refBy={walletOf(actions)} />
            {a && a.owner !== "" && a.owner === walletOf(actions) && (
              <Confirm label="Hide album" ask="Hide it from GnoRadio? You can show it again from its link." busy={actions.pending === `hide:album:${String(al.id)}`} onConfirm={() => { actions.hideOwn("album", al.id, true); }} />
            )}
          </div>
          <Proof page={gnowebOf({ k: "album", id: al.id })} code={codeURL("publish")} label={al.title} />
        </div>
      </div>
      <TrackRows tracks={tracks} player={player} actions={actions} saved={saved} />
    </section>
  );
}

export function PlaylistView({ cat, player, go, id, actions, saved }: DetailProps & { readonly actions: Actions; readonly saved: Saved }) {
  const pl = cat.playlists.find((x) => x.id === id);
  const who = useNames(pl ? [pl.owner] : []);
  const [editing, setEditing] = useState(false);
  if (!pl) return <Unavailable kind="playlist" id={id} go={go} />;
  const mine = pl.owner === walletOf(actions);
  const plTracks = tracksOf(cat, pl.tracks);
  return (
    <section>
      <Crumbs trail={[LIBRARY, { label: pl.title }]} go={go} />
      <Head a={pl.title} note={<>Public playlist by <Who address={pl.owner} shown={who} go={go} /> · {plural(pl.tracks.length, "track")}</>}
        right={<div className="head-actions"><PlayButton tracks={plTracks} onClick={() => { player.playList(pl.tracks, 0); }} /><ShareButton title={pl.title} refBy={walletOf(actions)} />{mine && <button className="btn" aria-expanded={editing} onClick={() => { setEditing(!editing); }}>Edit</button>}</div>} />
      {editing && <PlaylistForm cat={cat} actions={actions} edit={pl} onDone={() => { setEditing(false); }} />}
      <TrackRows tracks={plTracks} player={player} actions={actions} saved={saved} />
      <Proof page={gnowebOf({ k: "playlist", id: pl.id })} code={codeURL("playlist")} label={pl.title} />
    </section>
  );
}

/**
 * concertTime says when a concert starts. The realm keeps no venue time zone,
 * so the stored time is shown in UTC, labelled, then the listener's own clock.
 */
function concertTime(start: number): readonly [string, string] {
  const d = new Date(start * 1000);
  const utc = `${d.toLocaleString("en", { month: "short", day: "numeric", year: "numeric", hour: "2-digit", minute: "2-digit", hourCycle: "h23", timeZone: "UTC" })} UTC`;
  if (d.getTimezoneOffset() === 0) return [utc, ""];
  const day = (timeZone?: string) => d.toLocaleDateString("en", { month: "short", day: "numeric", timeZone });
  const local = d.toLocaleTimeString("en", { hour: "2-digit", minute: "2-digit", hourCycle: "h23" });
  return [utc, `(${day() === day("UTC") ? "" : `${day()}, `}${local} your time)`];
}

/** ConcertTicket is one black stub: cover, seats, buy, a listen-first link; a red stamp once sold out. */
function ConcertTicket({ e, cat, go, player, actions, me }: { readonly e: ConcertEvent; readonly cat: Catalog; readonly go: Navigate; readonly player: Player; readonly actions: Actions; readonly me: string }) {
  const artist = cat.artists.get(e.artist);
  const tracks = tracksOf(cat, artist?.tracks ?? []);
  const { allDead } = usePlayable(tracks);
  const fee = e.price > 0 ? (e.fee ?? 0) : 0;
  const locked = e.price > 0 && !tippable(artist);
  const soldOut = e.sold >= e.capacity && !e.cancelled;
  const almost = almostFull(e);
  const [at, mine] = concertTime(e.start);
  return (
    <article className={`ticket${soldOut ? " sold" : ""}`}>
      <div>
        <span className="lbl light">GnoRadio · admit one</span>
        <b>{e.title}</b>
        <span className="small">{e.venue} · {at} {mine && <span className="muted">{mine}</span>}</span>
        <span className="ticket-by">
          <button className="link light" onClick={() => { go({ k: "artist", id: e.artist }); }}>{artist?.name}</button>
          <a className="small ticket-chain" href={eventPage(e.id)} target="_blank" rel="noreferrer" aria-label={`View ${e.title} on gno.land, opens a new tab`}>On gno.land <Icon name="external" size={12} className="nudge-out" /></a>
        </span>
        {almost && <span className="almost">{almost}</span>}
        <div className="ticket-acts">
          {!soldOut && (
            <button className="cta yellow" disabled={e.cancelled || locked} title={locked ? "Paid tickets open once the artist verifies their profile" : undefined} onClick={() => { actions.buyTicket(e); }}>
              {e.cancelled ? "Cancelled" : locked ? "Artist not verified yet" : e.price > 0 ? `Buy · ${gnot(e.price)}${fee ? ` + ${gnot(fee)} fee` : ""}` : "Get a free ticket"}
            </button>
          )}
          {tracks.length > 0 && !allDead && <button className="listen" onClick={() => { player.playList(tracks.map((t) => t.id), 0); }}><Icon name="play" size={12} /> Listen before you go</button>}
          {artist && me !== "" && artist.owner === me && !e.cancelled && <CancelConcert e={e} actions={actions} />}
        </div>
        {e.price > 0 && !soldOut && !e.cancelled && <span className="small refund-note" title={REFUND}>{REFUND_SHORT}</span>}
      </div>
      <div className="stub">
        {tracks[0] && <Cover t={tracks[0]} size="52px" />}
        <span className="mono">{e.sold}/{e.capacity}</span>
        <Shape g="square" size={soldOut ? 14 : 26} />
      </div>
      {soldOut && <span className="stamp">Sold out</span>}
    </article>
  );
}

/** CancelConcert lets the artist cancel their own concert (tickets.CancelEvent), after a confirm. */
export function CancelConcert({ e, actions }: { readonly e: ConcertEvent; readonly actions: Actions }) {
  return (
    <Confirm label="Cancel concert" busy={actions.pending === `cancel:${String(e.id)}`}
      ask={e.sold > 0 ? `${plural(e.sold, "ticket")} sold: sales stop and holders see it cancelled. Refunds are yours to make.` : "Sales stop and the concert shows as cancelled."}
      onConfirm={() => { actions.cancelEvent(e); }} />
  );
}

export function Concerts({ cat, go, player, actions }: { readonly cat: Catalog; readonly go: Navigate; readonly player: Player; readonly actions: Actions }) {
  const fees = useFees();
  const [f, setF] = useState<ConcertFilter>(NO_FILTER);
  const s = actions.wallet.state;
  const address = s.status === "connected" || s.status === "wrong-network" ? s.address : "";
  const [mine, setMine] = useState<readonly OwnedTicket[]>([]);
  const myEvents = useEvents(cat, mine.map((tk) => tk.event));
  useEffect(() => {
    setMine([]);
    if (address) loadTicketsOf(address).then(setMine, () => { setMine([]); });
  }, [address]);
  const isArtist = address !== "" && [...cat.artists.values()].some((a) => a.owner === address);
  const shown = filterConcerts(cat.events, f, (id) => cat.artists.get(id)?.name ?? "", Date.now() / 1000);
  const set = (p: Partial<ConcertFilter>) => { setF({ ...f, ...p }); };
  const chip = (label: string, on: boolean, p: Partial<ConcertFilter>) => (
    <button key={label} className="chip" aria-pressed={on} onClick={() => { set(p); }}>{label}</button>
  );
  return (
    <section className="concerts-page">
      <Head a="Concerts" b="& tickets" note={`The ticket price goes 100% to the artist${fees ? "; a service fee is added" : ""}.`} />
      {cat.events.length === 0 ? (
        <Empty text="No concert announced yet.">
          <a className="cta" href={txURL("tickets", "CreateEvent")} target="_blank" rel="noreferrer">Announce yours <Icon name="external" size={14} className="nudge-out" /></a>
          {cat.tracks.length > 0 && <button className="cta ghost" onClick={() => { player.goLive(0); }}>Tune in <Icon name="arrow-right" size={16} className="nudge" /></button>}
        </Empty>
      ) : (
        <div className="concerts">
          <aside className="concerts-side">
            {mine.length > 0 && (
              <div className="my-tickets">
                <h3 className="lbl">My tickets</h3>
                {mine.map((tk) => {
                  const e = myEvents.get(tk.event) ?? undefined;
                  return (
                    <div key={tk.id} className="my-ticket">
                      <Shape g={tk.attended ? "circle" : "square"} size={10} />
                      <span><b>{e?.title ?? `Concert ${String(tk.event)}`}</b><span className="muted small">{e ? concertTime(e.start)[0] : ""} · #{tk.serial} · {tk.attended ? "Checked in" : "Valid"}</span></span>
                    </div>
                  );
                })}
              </div>
            )}
            <label className="concerts-search">
              <span className="sr">Search concerts</span>
              <input type="search" placeholder="Artist, city, venue" value={f.q} onChange={(ev) => { set({ q: ev.target.value }); }} />
            </label>
            <div className="concert-chips" role="group" aria-label="Filter concerts">
              {chip("This week", f.when === "week", { when: f.when === "week" ? "" : "week" })}
              {chip("This month", f.when === "month", { when: f.when === "month" ? "" : "month" })}
              <label className={`chip date-chip${f.day ? " on" : ""}`} title="Concerts on a day">
                <Icon name="calendar" size={15} />
                <input type="date" aria-label="Concerts on a day" value={f.day} min={new Date().toISOString().slice(0, 10)}
                  onChange={(ev) => { set({ day: ev.target.value }); }} onClick={(ev) => { try { ev.currentTarget.showPicker(); } catch { /* older browsers open it themselves */ } }} />
                {f.day && <button type="button" className="date-clear" aria-label="Any day" onClick={(ev) => { ev.preventDefault(); set({ day: "" }); }}><Icon name="close" size={12} /></button>}
              </label>
              {chip("Free", f.free, { free: !f.free })}
              {cities(cat.events).map((c) => chip(c, f.city === c, { city: f.city === c ? "" : c }))}
            </div>
            {isArtist && (
              <p className="concerts-announce small">
                <a href={txURL("tickets", "CreateEvent")} target="_blank" rel="noreferrer">Announce a concert (form on gno.land) <Icon name="external" size={12} /></a>
                <span className="muted">{CHECK_IN}</span>
              </p>
            )}
          </aside>
          <div className="concerts-list">
            {shown.length === 0 && <p className="muted">No concert matches. <button className="link" onClick={() => { setF(NO_FILTER); }}>Clear filters</button></p>}
            {byMonth(shown).map((g) => (
              <div key={g.month} className="tickets">
                <h3 className="month">{g.month}</h3>
                {g.events.map((e) => <ConcertTicket key={e.id} e={e} cat={cat} go={go} player={player} actions={actions} me={address} />)}
              </div>
            ))}
          </div>
        </div>
      )}
    </section>
  );
}

/** TrackView is the shareable page of one track: play, support, queue, proof. */
export function TrackView({ cat, player, go, id, actions, openSupport, openPick }: DetailProps & { readonly actions: Actions; readonly openSupport: (t: SupportTarget) => void; readonly openPick: (station: number, track?: number) => void }) {
  const [editing, setEditing] = useState(false);
  usePlayable();
  const t = cat.byId.get(id);
  if (!t) return <Unavailable kind="track" id={id} go={go} actions={actions} cat={cat} />;
  const a = cat.artists.get(t.artist);
  const genre = cat.genres.find((g) => g.id === t.genre)?.name ?? "";
  const artistPct = 100 - t.splits.reduce((s, x) => s + x.pct, 0);
  const mine = a !== undefined && a.owner !== "" && a.owner === walletOf(actions);
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
            <PlayButton tracks={[t]} onClick={() => { player.playList([t.id], 0); }} />
            {tippable(a) && a && <button className="cta yellow" onClick={() => { openSupport({ kind: "tip", track: t, artist: a }); }}><Shape g="square" size={12} fill="var(--ink)" /> Support</button>}
            <LikeButton t={t} actions={actions} />
            <button className="onchain" disabled={isDead(t)} title={isDead(t) ? UNAVAILABLE : "Choose a station in the next step · public, on-chain"} onClick={() => { openPick(0, t.id); }}><Icon name="on-air" size={14} /> Pick next</button>
            <ShareButton title={t.title} refBy={walletOf(actions)} />
            {mine && <button className="btn" aria-expanded={editing} onClick={() => { setEditing(!editing); }}>Edit</button>}
            {mine && <Confirm label="Hide track" ask="Hide it from GnoRadio and its stations? You can show it again from its link." busy={actions.pending === `hide:track:${String(t.id)}`} onConfirm={() => { actions.hideOwn("track", t.id, true); }} />}
          </div>
        </div>
      </div>
      {editing && <EditTrackForm key={t.id} cat={cat} t={t} actions={actions} onDone={() => { setEditing(false); }} />}
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
          <p><License id={t.origin === "audius" ? "Audius-OML" : t.license} />{t.credits ? ` · ${t.credits}` : ""}</p>
          {t.attribution && <p className="muted small">{t.attribution}</p>}
          {t.source && <a className="link small" href={t.source} target="_blank" rel="noreferrer" title={t.source}>Source · {hostOf(t.source)}</a>}
          <Proof page={gnowebOf({ k: "track", id: t.id })} code={codeURL("publish")} label={t.title} />
        </div>
      </div>
    </section>
  );
}
