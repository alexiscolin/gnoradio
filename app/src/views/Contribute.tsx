import { Icon, type IconName } from "../components/Icons";
import { type ReactNode, useEffect, useMemo, useRef, useState } from "react";
import { Cover } from "../components/Cover";
import { Help } from "../components/Help";
import { Shape } from "../components/Shapes";
import { RIGHTS_FALLBACK, hostAllowed, loadRightsTerms, loadUser } from "../lib/community";
import { txURL } from "../lib/links";
import { ARTIST_NEEDS, IMPORTED, REPORTS } from "../lib/features";
import { track } from "../lib/analytics";
import { CHECK_IN } from "../lib/concerts";
import { CONTACT } from "../lib/legal";
import { clock, errorMessage, plural } from "../lib/format";
import { SearchPick } from "../components/SearchPick";
import { Confirm } from "../components/common";
import { VerifyPanel, useClaim } from "../components/Verify";
import {
  LICENSES, type SplitRow, type TrackDraft, type TrackEdit, allowHost, artistProblems, editProblems, playlistProblems, reportProblems,
  sha256Hex, sha256OfURL, trackProblems,
} from "../lib/rules";
import type { Catalog, ContribPath, Navigate, Playlist, Track, UserInfo } from "../lib/types";
import { type Actions, DEPOSIT, PICK_COST, playlistDeposit } from "../player/useActions";
import { FEATURES_NAME } from "../lib/seo";

/** searchHint: a picker's placeholder, which never offers to search nothing. */
const searchHint = (n: number, what: string): string => (n > 0 ? `Search ${String(n)} ${what}` : `No ${what} yet`);

interface Props {
  readonly cat: Catalog;
  readonly go: Navigate;
  readonly actions: Actions;
  readonly isAdmin: boolean;
  readonly openPick: (station: number) => void;
}

const deposit = (n: number | undefined) => (n === undefined ? "" : `About ${String(n)} GNOT deposit`);

/** Problems lists what the realm would refuse, live, before Adena opens. */
function Problems({ list }: { readonly list: readonly string[] }) {
  if (list.length === 0) return <p className="ok small"><Icon name="check" size={14} /> Ready to sign</p>;
  return <ul className="problems">{list.map((p) => <li key={p}>{p}</li>)}</ul>;
}

function Panel({ id, glyph, title, note, children }: { readonly id: string; readonly glyph: "quarter" | "triangle" | IconName; readonly title: string; readonly note: string; readonly children: ReactNode }) {
  // Problems show once the listener starts filling the form, not on an empty one.
  const [touched, setTouched] = useState(false);
  return (
    <section id={id} className={`panel contrib-form${touched ? " touched" : ""}`} onInput={() => { setTouched(true); }} onChange={() => { setTouched(true); }}>
      <h3>{glyph === "quarter" || glyph === "triangle" ? <Shape g={glyph} size={14} /> : <Icon name={glyph} size={16} />} {title}</h3>
      <p className="muted small">{note}</p>
      {children}
    </section>
  );
}

const PATHS: readonly { readonly id: ContribPath; readonly label: string; readonly line: string; readonly mark: ReactNode }[] = [
  { id: "listener", label: "Listener", line: "Pick what plays, make playlists", mark: <Shape g="quarter" size={34} /> },
  { id: "artist", label: "Artist", line: "In rotation when you publish · 0% of tips to GnoRadio", mark: <Shape g="triangle" size={34} /> },
  { id: "claim", label: "Already on Audius or GnoRadio?", line: "Verify your profile to receive tips", mark: <Shape g="circle" size={34} /> },
  { id: "report", label: "Report", line: "Report what breaks the rules", mark: <Shape g="square" size={34} /> },
];

/** Contribute asks one question, then shows only the chosen path, one step at a time. */
export function Contribute({ cat, go, path, actions, isAdmin, openPick }: Props & { readonly path?: ContribPath | undefined }) {
  const s = actions.wallet.state;
  const address = s.status === "connected" || s.status === "wrong-network" ? s.address : "";
  const [user, setUser] = useState<UserInfo | null>(null);
  useEffect(() => {
    if (!address) { setUser(null); return; }
    loadUser(address).then(setUser, () => { setUser(null); });
  }, [address]);
  const myArtist = user?.artist ? cat.artists.get(user.artist) : undefined;
  const chosen: ContribPath = path ?? (myArtist ? "artist" : "listener");

  return (
    <section>
      <h2 className="ask">How do you want to contribute?</h2>
      <p className="new-here"><button className="link" onClick={() => { go({ k: "features" }); }}>New here? {FEATURES_NAME} <Icon name="arrow-right" size={14} className="nudge" /></button></p>
      <div className="tiles" role="tablist" aria-label="Ways to contribute">
        {PATHS.map((p) => (
          <button key={p.id} role="tab" aria-selected={chosen === p.id} className={`tile${chosen === p.id ? " on" : ""}`} onClick={() => { go({ k: "contribute", path: p.id }); }}>
            {p.mark}
            <b>{p.label}</b>
            <span>{p.line}</span>
          </button>
        ))}
      </div>

      {chosen === "report" && <p className="report-first">Rights holder? Open a <a href={CONTACT} target="_blank" rel="noreferrer">GitHub issue</a>: no wallet needed.</p>}
      {!address && (
        <p className="connect-line">
          <Icon name="wallet" size={18} /> Contributing writes to gno.land, so it needs a wallet. Listening never does.
          <button className="cta" onClick={() => void actions.wallet.connectWallet()}>Connect Adena</button>
        </p>
      )}

      <div className="path-body" key={chosen} role="tabpanel">
        {chosen === "listener" && (
          <div className="contrib two">
            <div className="panel">
              <h3><Shape g="quarter" size={14} /> Pick what plays next <Help text={`Your pick airs for everyone after the picks already waiting. One per station every 30 minutes, ${PICK_COST}.`} /></h3>
              <p className="muted small">Choose a track and a station. Everyone hears it at the same second.</p>
              <button className="cta blue" onClick={() => { openPick(0); }}>Pick a track</button>
            </div>
            <PlaylistForm cat={cat} actions={actions} />
          </div>
        )}
        {chosen === "artist" && !myArtist && (
          <p className="artist-needs muted small">
            {ARTIST_NEEDS} <button className="link" onClick={() => { go({ k: "contribute", path: "claim" }); }}>{IMPORTED}</button>
          </p>
        )}
        {chosen === "artist" && <ArtistPath cat={cat} actions={actions} self={address} artist={myArtist} />}
        {chosen === "artist" && myArtist && <ArtistTx />}
        {chosen === "claim" && <div className="contrib"><ClaimForm cat={cat} actions={actions} /></div>}
        {chosen === "report" && (
          <div className="contrib">
            <ReportForm cat={cat} actions={actions} />
            {isAdmin && <button className="cta ghost" onClick={() => { go({ k: "studio" }); }}>Open the Studio</button>}
          </div>
        )}
      </div>
    </section>
  );
}

/** ArtistPath is the artist stepper: 1 profile → 2 track info → 3 rights & publish. */
function ArtistPath({ cat, actions, self, artist }: { readonly cat: Catalog; readonly actions: Actions; readonly self: string; readonly artist: { readonly name: string; readonly bio: string; readonly verified?: boolean } | undefined }) {
  const [step, setStep] = useState(artist ? 2 : 1);
  useEffect(() => { if (artist) setStep((n) => Math.max(n, 2)); }, [artist]);
  useEffect(() => { track("artist_step", { at: step as 1 | 2 | 3 }); }, [step]);
  const [d, setD] = useState<TrackDraft>({
    title: "", genre: 0, duration: "", license: "CC-BY-4.0", cmo: "none", credits: "",
    audio: "", audioSha: "", cover: "", coverSha: "", splits: [], rights: false,
  });
  const set = <K extends keyof TrackDraft>(k: K, v: TrackDraft[K]) => { setD((x) => ({ ...x, [k]: v })); };
  const done = (n: number, summary: string) => (
    <p className="step-done"><span className="step-n">{n}</span>{summary}<button className="link small" onClick={() => { setStep(n); }}>Edit</button></p>
  );
  return (
    <div className="contrib stepper">
      <ol className="steps" aria-label="Steps">
        {["Profile", "Track info", "Rights & publish"].map((l, i) => <li key={l} className={step === i + 1 ? "on" : step > i + 1 ? "done" : ""}>{i + 1} · {l}</li>)}
        <li className="steps-help"><Help text="Each field is checked the way the realm will check it. You sign once, at the last step; the profile is its own small transaction." /></li>
      </ol>
      {step === 1 ? <ArtistForm actions={actions} existing={artist?.name ?? ""} existingBio={artist?.bio ?? ""} verified={artist?.verified ?? false} onNext={artist ? () => { setStep(2); } : undefined} />
        : done(1, artist ? `Profile · ${artist.name}` : "Profile")}
      {step === 2 && <TrackInfo cat={cat} d={d} set={set} onNext={() => { setStep(3); }} />}
      {step > 2 && done(2, d.title ? `Track · ${d.title}` : "Track info")}
      {step === 3 && <TrackPublish d={d} set={set} actions={actions} self={self} isArtist={artist !== undefined} />}
    </div>
  );
}

/** sameName: a rename the realm keeps verified (its skeleton folds more; this errs on the side of asking). */
export const sameName = (a: string, b: string): boolean => {
  const k = (s: string) => s.toLowerCase().replace(/[^\p{L}\p{N}]/gu, "");
  return k(a) === k(b);
};

function ArtistForm({ actions, existing, existingBio, verified = false, onNext }: { readonly actions: Actions; readonly existing: string; readonly existingBio: string; readonly verified?: boolean; readonly onNext?: (() => void) | undefined }) {
  const [name, setName] = useState(existing);
  const [bio, setBio] = useState(existingBio);
  useEffect(() => { setName(existing); setBio(existingBio); }, [existing, existingBio]);
  const problems = artistProblems(name, bio);
  return (
    <Panel id="c-artist" glyph="triangle" title={existing ? "Your artist profile" : "Create your artist profile"} note={`One profile per wallet. Saving again renames it and frees the old name. ${deposit(DEPOSIT["Register artist"])}.`}>
      <label>Artist name<input value={name} maxLength={40} onChange={(e) => { setName(e.target.value); }} placeholder="Lea Kosmos" /></label>
      <label>Bio<textarea value={bio} rows={3} onChange={(e) => { setBio(e.target.value); }} placeholder="Night synthwave from Lyon." /><span className="muted small">{Array.from(bio).length}/280</span></label>
      <Problems list={problems} />
      <div className="row2">
        {verified && !sameName(name, existing) && problems.length === 0
          // A new name drops the ✓ (catalog rename): say what that stops before it is signed.
          ? <Confirm className="cta" label="Save profile" ask="A new name removes your verification: tips and paid ticket sales stop until you verify again and wait 72 hours." onConfirm={() => { actions.registerArtist(name, bio); }} />
          : <button className="cta" disabled={problems.length > 0} onClick={() => { actions.registerArtist(name, bio); }}>{existing ? "Save profile" : "Create my profile"}</button>}
        {onNext && <button className="cta ghost" onClick={onNext}>Next: track info</button>}
      </div>
    </Panel>
  );
}

const EMPTY_SPLIT: SplitRow = { to: "", pct: "" };

/** HashField shows a sha256 input with the two ways to fill it: from the link, or from a local file. */
function HashField({ label, uri, sha, setSha }: { readonly label: string; readonly uri: string; readonly sha: string; readonly setSha: (v: string) => void }) {
  const [state, setState] = useState("");
  const ctrl = useRef<AbortController | null>(null);
  useEffect(() => () => { ctrl.current?.abort(); }, []);
  const fromLink = async () => {
    ctrl.current?.abort();
    ctrl.current = new AbortController();
    setState("Hashing the file…");
    try {
      setSha(await sha256OfURL(uri, ctrl.current.signal));
      setState("Hashed from the link.");
    } catch (e) {
      setState(`The host did not let the browser read it (${errorMessage(e)}). Drop the same file instead.`);
    }
  };
  const fromFile = async (f: File | undefined) => {
    if (!f) return;
    setState(`Hashing ${f.name}…`);
    setSha(await sha256Hex(await f.arrayBuffer()));
    setState(`Hashed from ${f.name}. It must be the exact file at the link.`);
  };
  return (
    <div className="hash">
      <label>{label} sha256<input className="mono" value={sha} onChange={(e) => { setSha(e.target.value.trim().toLowerCase()); }} placeholder="64 hex characters" /></label>
      <div className="row2">
        {uri.startsWith("https://") && <button className="cta ghost" onClick={() => void fromLink()}>Hash from the link</button>}
        <label className="cta ghost file">Hash a local file<input type="file" onChange={(e) => void fromFile(e.target.files?.[0])} /></label>
      </div>
      {state && <p className="muted small" role="status">{state}</p>}
    </div>
  );
}

/** TrackInfo is step 2: what the track is and where its file lives. */
function TrackInfo({ cat, d, set, onNext }: { readonly cat: Catalog; readonly d: TrackDraft; readonly set: <K extends keyof TrackDraft>(k: K, v: TrackDraft[K]) => void; readonly onNext: () => void }) {
  return (
    <Panel id="c-track" glyph="triangle" title="Track info" note="Title, genre, license and the link to your hosted file.">
      <details className="hosting">
        <summary aria-label="Where do I host my file?">?</summary>
        <p>GnoRadio stores the link and its fingerprint on-chain, not the audio. There is no upload button yet, so host the file first:</p>
        <ul>
          <li><b>IPFS</b> through a pinning service such as Pinata or Filebase, then paste <span className="mono">ipfs://&lt;CID&gt;</span>. The CID already proves the content.</li>
          <li><b>Arweave</b>, paid once and kept for good: paste <span className="mono">ar://&lt;id&gt;</span>.</li>
          <li><b>An https link</b> on a host the moderator allows (archive.org today). Add the file's sha256 so anyone can check it was not swapped.</li>
        </ul>
      </details>
      <label>Title<input value={d.title} maxLength={64} onChange={(e) => { set("title", e.target.value); }} /></label>
      <div className="row2">
        <label>Genre
          <select value={d.genre} onChange={(e) => { set("genre", Number(e.target.value)); }}>
            <option value={0}>Choose…</option>
            {cat.genres.map((g) => <option key={g.id} value={g.id}>{g.name}</option>)}
          </select>
        </label>
        <label>Duration<input value={d.duration} placeholder="3:42" inputMode="numeric" onChange={(e) => { set("duration", e.target.value); }} /></label>
      </div>
      <div className="row2">
        <label>License
          <select value={d.license} onChange={(e) => { set("license", e.target.value); }}>
            {LICENSES.map(([id, label]) => <option key={id} value={id}>{label}</option>)}
          </select>
        </label>
        <label>Collecting society
          <select value={d.cmo} onChange={(e) => { set("cmo", e.target.value); }}>
            <option value="none">None</option>
            <option value="sacem-nc">SACEM, NC works</option>
          </select>
        </label>
      </div>
      <label>Credits <span className="muted small">optional</span><input value={d.credits} maxLength={160} placeholder="Mixed by Moko" onChange={(e) => { set("credits", e.target.value); }} /></label>
      <label>Audio<input className="mono" value={d.audio} placeholder="ipfs://… · ar://… · https://archive.org/…" onChange={(e) => { set("audio", e.target.value.trim()); }} /></label>
      {(d.audio.startsWith("https://") || d.audioSha) && <HashField label="Audio" uri={d.audio} sha={d.audioSha} setSha={(v) => { set("audioSha", v); }} />}
      <label>Cover <span className="muted small">optional</span><input className="mono" value={d.cover} placeholder="ipfs://… · ar://… · https://…" onChange={(e) => { set("cover", e.target.value.trim()); }} /></label>
      {(d.cover.startsWith("https://") || d.coverSha) && <HashField label="Cover" uri={d.cover} sha={d.coverSha} setSha={(v) => { set("coverSha", v); }} />}

      <div className="splits">
        <span className="lbl">Collaborators <span className="muted small">optional · they get a share of every tip, you keep at least 10%</span></span>
        {d.splits.map((r, i) => (
          <div key={i} className="split-row">
            <input className="mono" value={r.to} placeholder="g1…" aria-label={`Collaborator ${String(i + 1)} address`} onChange={(e) => { set("splits", d.splits.map((x, j) => (j === i ? { ...x, to: e.target.value.trim() } : x))); }} />
            <input value={r.pct} placeholder="%" inputMode="numeric" aria-label={`Collaborator ${String(i + 1)} share`} onChange={(e) => { set("splits", d.splits.map((x, j) => (j === i ? { ...x, pct: e.target.value } : x))); }} />
            <button className="x" aria-label="Remove collaborator" onClick={() => { set("splits", d.splits.filter((_, j) => j !== i)); }}><Icon name="close" size={16} /></button>
          </div>
        ))}
        {d.splits.length < 4 && <button className="cta ghost" onClick={() => { set("splits", [...d.splits, EMPTY_SPLIT]); }}>+ Add a collaborator</button>}
      </div>

      <button className="cta" disabled={!d.title || !d.genre || !d.audio} onClick={onNext}>Next: rights & publish</button>
    </Panel>
  );
}

/** TrackPublish is step 3: the rights statement, the realm's checks, the deposit, then sign. */
function TrackPublish({ d, set, actions, self, isArtist }: { readonly d: TrackDraft; readonly set: <K extends keyof TrackDraft>(k: K, v: TrackDraft[K]) => void; readonly actions: Actions; readonly self: string; readonly isArtist: boolean }) {
  const [terms, setTerms] = useState("");
  useEffect(() => { void loadRightsTerms().then(setTerms); }, []);
  // https hosts are allowlisted on-chain: ask the realm, once per host.
  const [hosts, setHosts] = useState<Readonly<Record<string, boolean | undefined>>>({});
  const audioHost = d.audio.startsWith("https://") ? allowHost(d.audio) : "";
  const coverHost = d.cover.startsWith("https://") ? allowHost(d.cover) : "";
  useEffect(() => {
    for (const h of [audioHost, coverHost]) {
      if (!h || h in hosts) continue;
      void hostAllowed(h).then((ok) => { setHosts((x) => ({ ...x, [h]: ok })); });
    }
  }, [audioHost, coverHost, hosts]);
  const problems = trackProblems(d, self, { audio: audioHost ? hosts[audioHost] : undefined, cover: coverHost ? hosts[coverHost] : undefined });
  if (!isArtist) problems.unshift("Create your artist profile first");
  return (
    <Panel id="c-publish" glyph="triangle" title="Rights & publish" note={`Your track joins its genre station right away, in the same transaction. ${deposit(DEPOSIT["Publish track"])}.`}>
      <label className="toggle rights">
        <input type="checkbox" checked={d.rights} onChange={(e) => { set("rights", e.target.checked); }} />
        <span>{terms || RIGHTS_FALLBACK}</span>
      </label>
      <Problems list={problems} />
      <button className="cta" disabled={problems.length > 0} onClick={() => { actions.publishTrack(d); }}>Publish on GnoRadio</button>
    </Panel>
  );
}

/** PlaylistForm publishes a playlist, or with edit updates its owner's playlist (catalog.UpdatePlaylist). */
export function PlaylistForm({ cat, actions, edit, onDone }: { readonly cat: Catalog; readonly actions: Actions; readonly edit?: Playlist; readonly onDone?: () => void }) {
  const [title, setTitle] = useState(edit?.title ?? "");
  const [ids, setIds] = useState<readonly number[]>(edit?.tracks ?? []);
  const pickable = useMemo(() => cat.tracks.filter((t) => !ids.includes(t.id)).map((t) => ({ id: t.id, label: t.title, sub: `${t.artistName} · ${clock(t.duration)}`, art: <Cover t={t} size="28px" /> })), [cat.tracks, ids]);
  const problems = playlistProblems(title, ids);
  const move = (i: number, by: number) => {
    const j = i + by;
    if (j < 0 || j >= ids.length) return;
    const next = [...ids];
    [next[i], next[j]] = [next[j] ?? 0, next[i] ?? 0];
    setIds(next);
  };
  return (
    <Panel id="c-playlist" glyph="quarter" title={edit ? "Edit playlist" : "Publish a playlist"} note={edit ? "Rename it, reorder, add or remove tracks. A longer playlist locks a little more storage deposit." : `Public and playable by anyone, in the order you set. ${deposit(playlistDeposit(ids.length))}.`}>
      <label>Title<input value={title} maxLength={64} placeholder="Late Night Lyon" onChange={(e) => { setTitle(e.target.value); }} /></label>
      {ids.length > 0 && (
        <ol className="chosen">
          {ids.map((id, i) => {
            const t = cat.byId.get(id);
            return (
              <li key={id}>
                <span className="mono muted">{String(i + 1).padStart(2, "0")}</span>
                <span className="tt"><b>{t?.title ?? `Track ${String(id)}`}</b><span className="muted">{t?.artistName}</span></span>
                <button aria-label="Move up" onClick={() => { move(i, -1); }}><Icon name="chevron-down" size={16} className="flip" /></button>
                <button aria-label="Move down" onClick={() => { move(i, 1); }}><Icon name="chevron-down" size={16} /></button>
                <button aria-label="Remove" onClick={() => { setIds(ids.filter((x) => x !== id)); }}><Icon name="close" size={16} /></button>
              </li>
            );
          })}
        </ol>
      )}
      <SearchPick label="Add tracks" keepOpen items={pickable} value={0} onChange={(id) => { if (id && !ids.includes(id)) setIds([...ids, id]); }} placeholder={searchHint(cat.tracks.length, "tracks")} hint="Choose as many as you like; reorder them above." />
      <Problems list={problems} />
      {edit
        ? <button className="cta" disabled={problems.length > 0 || actions.pending !== ""} onClick={() => { actions.updatePlaylist(edit.id, title, ids, () => { onDone?.(); }); }}>Save playlist</button>
        : <button className="cta" disabled={problems.length > 0} onClick={() => { actions.publishPlaylist(title, ids); }}>Publish playlist</button>}
    </Panel>
  );
}

function ClaimForm({ cat, actions }: { readonly cat: Catalog; readonly actions: Actions }) {
  // Curated imports are verified only by the moderator (catalog AssignArtist): not offered here.
  const unverified = useMemo(() => [...cat.artists.values()].filter((a) => !a.verified && a.kind !== "curated").map((a) => ({ id: a.id, label: a.name, sub: `${a.kind === "audius" ? "Audius" : "On GnoRadio"} · ${plural(a.tracks.length, "track")}` })), [cat.artists]);
  const [artist, setArtist] = useState(0);
  const [refresh, setRefresh] = useState(0);
  const a = cat.artists.get(artist);
  const claim = useClaim(artist, refresh);
  return (
    <Panel id="c-claim" glyph="check" title="Verify your artist profile" note="Already on GnoRadio, imported from Audius, or registered yourself? Add a code to your Audius bio or your own site; tips open 72 hours later.">
      <SearchPick label="Your profile" items={unverified} value={artist} onChange={setArtist} placeholder={searchHint(unverified.length, "profiles")} />
      <p className="muted small">Imported from an archive (a curated profile)? Those are verified by the GnoRadio moderator: <a href={CONTACT} target="_blank" rel="noreferrer">ask in a GitHub issue</a>.</p>
      {a && <VerifyPanel a={a} claim={claim} actions={actions} onClose={() => { setArtist(0); }} onChange={() => { setRefresh((n) => n + 1); }} />}
    </Panel>
  );
}

/** ArtistTx links the artist actions the app has no screen for to their gnoweb forms, and says where the others are. */
function ArtistTx() {
  return (
    <>
      <p className="more-links">
        <a href={txURL("tickets", "CreateEvent")} target="_blank" rel="noreferrer">Announce a concert (form on gno.land) <Icon name="external" size={12} /></a>
        <a href={txURL("catalog", "CreateAlbum")} target="_blank" rel="noreferrer">Make an album (form on gno.land) <Icon name="external" size={12} /></a>
      </p>
      <p className="muted small">Edit or hide a track: open its page and press Edit or Hide track. {CHECK_IN} Cancel a concert from its ticket in Concerts or in Me.</p>
    </>
  );
}

/** EditTrackForm changes what radio.EditTrack allows: info and media; license, splits and rights stay as published. */
export function EditTrackForm({ cat, t, actions, onDone }: { readonly cat: Catalog; readonly t: Track; readonly actions: Actions; readonly onDone: () => void }) {
  const [d, setD] = useState<TrackEdit>({
    title: t.title, genre: t.genre, duration: clock(t.duration), credits: t.credits,
    audio: t.audio, audioSha: t.audioSha256, cover: t.cover, coverSha: t.coverSha256,
  });
  const set = <K extends keyof TrackEdit>(k: K, v: TrackEdit[K]) => { setD((x) => ({ ...x, [k]: v })); };
  const [hosts, setHosts] = useState<Readonly<Record<string, boolean | undefined>>>({});
  const audioHost = d.audio.startsWith("https://") ? allowHost(d.audio) : "";
  const coverHost = d.cover.startsWith("https://") ? allowHost(d.cover) : "";
  useEffect(() => {
    for (const h of [audioHost, coverHost]) {
      if (!h || h in hosts) continue;
      void hostAllowed(h).then((ok) => { setHosts((x) => ({ ...x, [h]: ok })); });
    }
  }, [audioHost, coverHost, hosts]);
  const audius = t.origin === "audius";
  const problems = audius ? editProblems(d).filter((p) => !p.startsWith("Audio") && !p.startsWith("Cover")) : editProblems(d, { audio: audioHost ? hosts[audioHost] : undefined, cover: coverHost ? hosts[coverHost] : undefined });
  return (
    <Panel id="c-edit" glyph="triangle" title="Edit track" note="Title, genre, duration, credits and the file links. License, collaborators and the rights declaration stay as published.">
      <label>Title<input value={d.title} maxLength={64} onChange={(e) => { set("title", e.target.value); }} /></label>
      <div className="row2">
        <label>Genre
          <select value={d.genre} onChange={(e) => { set("genre", Number(e.target.value)); }}>
            {cat.genres.map((g) => <option key={g.id} value={g.id}>{g.name}</option>)}
          </select>
        </label>
        <label>Duration<input value={d.duration} placeholder="3:42" inputMode="numeric" onChange={(e) => { set("duration", e.target.value); }} /></label>
      </div>
      <label>Credits <span className="muted small">optional</span><input value={d.credits} maxLength={160} onChange={(e) => { set("credits", e.target.value); }} /></label>
      {!audius && (
        <>
          <label>Audio<input className="mono" value={d.audio} onChange={(e) => { set("audio", e.target.value.trim()); }} /></label>
          {(d.audio.startsWith("https://") || d.audioSha) && <HashField label="Audio" uri={d.audio} sha={d.audioSha} setSha={(v) => { set("audioSha", v); }} />}
          <label>Cover <span className="muted small">optional</span><input className="mono" value={d.cover} onChange={(e) => { set("cover", e.target.value.trim()); }} /></label>
          {(d.cover.startsWith("https://") || d.coverSha) && <HashField label="Cover" uri={d.cover} sha={d.coverSha} setSha={(v) => { set("coverSha", v); }} />}
        </>
      )}
      <Problems list={problems} />
      <div className="row2">
        <button className="cta" disabled={problems.length > 0 || actions.pending !== ""} onClick={() => { actions.editTrack(t, d, onDone); }}>Save changes</button>
        <button className="cta ghost" onClick={onDone}>Cancel</button>
      </div>
    </Panel>
  );
}

type Kind = "track" | "album" | "artist" | "playlist";

function ReportForm({ cat, actions }: { readonly cat: Catalog; readonly actions: Actions }) {
  const [kind, setKind] = useState<Kind>("track");
  const [n, setN] = useState(0);
  const [reason, setReason] = useState("");
  const items = useMemo(() => {
    switch (kind) {
      case "track": return cat.tracks.map((t) => ({ id: t.id, label: t.title, sub: t.artistName }));
      case "album": return cat.albums.map((a) => ({ id: a.id, label: a.title, sub: cat.artists.get(a.artist)?.name ?? "" }));
      case "artist": return [...cat.artists.values()].map((a) => ({ id: a.id, label: a.name, sub: plural(a.tracks.length, "track") }));
      case "playlist": return cat.playlists.map((p) => ({ id: p.id, label: p.title, sub: plural(p.tracks.length, "track") }));
    }
  }, [cat, kind]);
  const problems = [...(n > 0 ? [] : [`Choose the ${kind}`]), ...reportProblems(reason)];
  return (
    <Panel id="c-report" glyph="flag" title="Report something" note={`${REPORTS} ${deposit(DEPOSIT["Report"])}.`}>
      <div className="row2">
        <label>What
          <select value={kind} onChange={(e) => { setKind(e.target.value as Kind); setN(0); }}>
            <option value="track">Track</option>
            <option value="album">Album</option>
            <option value="artist">Artist</option>
            <option value="playlist">Playlist</option>
          </select>
        </label>
      </div>
      <SearchPick label={`${kind.charAt(0).toUpperCase()}${kind.slice(1)}`} items={items} value={n} onChange={setN} placeholder={searchHint(items.length, `${kind}s`)} />
      <label>Reason<textarea rows={2} value={reason} maxLength={200} placeholder="Not the artist's own recording" onChange={(e) => { setReason(e.target.value); }} /></label>
      <p className="muted small">Your report and wallet address are public on-chain.</p>
      <Problems list={problems} />
      <button className="cta red" disabled={problems.length > 0} onClick={() => { actions.report(kind, n, reason); }}>{problems[0] ?? "Send the report"}</button>
    </Panel>
  );
}
