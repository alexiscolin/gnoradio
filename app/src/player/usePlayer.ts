import { track } from "../lib/analytics";
import { useCallback, useEffect, useMemo, useRef, useState, useSyncExternalStore } from "react";
import { audioURLs, loadOnAir, loadSchedule } from "../lib/catalog";
import { isDead, markDead } from "../lib/playable";
import { dropBucket, want } from "../lib/refs";
import { errorMessage } from "../lib/format";
import type { Catalog, ScheduleEntry } from "../lib/types";
import { jingleURL, playingNow, tail, topOfHour } from "./jingle";

export type Mode = "library" | "live";

/** The note shown when no source of a track answers. */
export const NOT_RESPONDING = "This track isn't responding.";

// Clock skew: a schedule's now is its last block's time, which lags the chain by
// up to a block, so the largest of the recent samples is the closest. Only the
// last SKEW_SAMPLES count, so a local clock set forward (NTP, sleep) lowers it
// again; a jump of more than SKEW_JUMP seconds restarts the window at once.
const SKEW_SAMPLES = 6;
const SKEW_JUMP = 30;
/** nextSkew adds a sample (chain now minus local now) to the recent ones; the skew is their max. */
export function nextSkew(recent: readonly number[], fresh: number): number[] {
  if (recent.length > 0 && Math.abs(fresh - Math.max(...recent)) > SKEW_JUMP) return [fresh];
  return [...recent, fresh].slice(-SKEW_SAMPLES);
}
const NOT_RESPONDING_AFTER_MS = 6000;

const RESYNC_MS = 5 * 60_000; // the schedule covers an hour; resync also at each entry's end
const DRIFT_S = 4;
const FADE_S = 1.2;
// The longest jingle is 12.3 s: past this, a jingle that stalled (a slow archive.org, a tune-in that
// never finished) lets the music back in, never leaving it silent under a clock that runs.
const IDENT_MAX_MS = 16_000;
const IDENT_AGAIN_MS = 10 * 60_000; // resuming the same station sooner skips its jingle
const HOURLY_GAP_MS = 20 * 60_000; // no hourly jingle this soon after another one
const HOURLY_DUCK = 0.25; // the music under the hourly jingle, as a share of the volume

/** A running fade on an element: stopFade ends it where it is (its promise still resolves). */
interface Fade { id: number; done: () => void }
function stopFade(slot: { current: Fade | null }) {
  const f = slot.current;
  if (!f) return;
  window.clearInterval(f.id);
  slot.current = null;
  f.done();
}

/**
 * fade ramps the element's volume to v over FADE_S (timers, so it also ends in a background
 * tab). With a slot, a new fade or stopFade cancels the one before, so no stale ramp drives
 * the volume back after the listener changed mode.
 */
function fade(a: HTMLAudioElement, v: number, slot?: { current: Fade | null }): Promise<void> {
  if (slot) stopFade(slot);
  const from = a.volume;
  const t0 = Date.now();
  return new Promise((done) => {
    const id = window.setInterval(() => {
      const k = Math.min(1, (Date.now() - t0) / (FADE_S * 1000));
      a.volume = from + (v - from) * k;
      if (k === 1) {
        window.clearInterval(id);
        if (slot?.current?.id === id) slot.current = null;
        done();
      }
    }, 40);
    if (slot) slot.current = { id, done };
  });
}

/**
 * usePlayer drives one <audio> element in two modes:
 *  - library: an ordered queue the listener controls;
 *  - live: a station's on-chain schedule, joined at the right second.
 */
export function usePlayer(cat: Catalog | null, onMissing?: (trackId: number) => void) {
  const [audio] = useState(() => {
    const a = new Audio();
    a.preload = "auto";
    return a;
  });
  const [mode, setMode] = useState<Mode>("live"); // GnoRadio opens on the radio; Play joins it
  const [station, setStation] = useState(0);
  const [queue, setQueue] = useState<readonly number[]>([]);
  const [index, setIndex] = useState(0);
  const [current, setCurrent] = useState(0);
  const [playing, setPlaying] = useState(false);
  const [buffering, setBuffering] = useState(false);
  const [volume, setVolumeState] = useState(() => {
    try {
      const v = Number(localStorage.getItem("gnoradio.volume") ?? "1");
      return Number.isFinite(v) ? Math.min(1, Math.max(0, v)) : 1;
    } catch {
      return 1;
    }
  });
  const [muted, setMuted] = useState(false);
  const userVolume = useRef(volume);
  // The jingle playing while a tuned-in station loads (goLive), null otherwise.
  const ident = useRef<HTMLAudioElement | null>(null);
  const lastIdent = useRef({ station: -1, at: 0 });
  const lastHourly = useRef(-1);
  // Read in goLive without making it change (and re-tune) whenever the catalog grows.
  const catalog = useRef(cat);
  catalog.current = cat;
  userVolume.current = volume;
  const [entries, setEntries] = useState<readonly ScheduleEntry[]>([]);
  const entriesRef = useRef(entries);
  entriesRef.current = entries;
  const [error, setError] = useState("");
  const failNote = useRef(0); // the pending "not responding" note, dropped if sound comes back
  // Chain clock minus local clock, seconds: the max of the recent samples (nextSkew), steady
  // between syncs instead of re-drawn at each one.
  const skew = useRef(0);
  const skewSamples = useRef<number[]>([]);
  // The next sync, timed for the end of the entry on air: a pick cuts or shortens it for everyone.
  const endTimer = useRef(0);
  const syncSeq = useRef(0); // drops stale schedule responses
  const pendingSeek = useRef<(() => void) | null>(null);
  const sources = useRef<{ urls: readonly string[]; i: number }>({ urls: [], i: 0 }); // gateway fallbacks
  const skips = useRef(0); // dead tracks skipped in a row
  const loadedId = useRef(0); // the track whose file the element holds (current may run ahead of it while paused)
  const hourly = useRef<HTMLAudioElement | null>(null); // the hourly jingle playing over the music
  const gotMeta = useRef(false); // some source of this load answered: an error after that is the network, not a dead file
  const audioFade = useRef<Fade | null>(null); // the main element's running fade
  const warmTimer = useRef(0);
  const awaiting = useRef(0); // the Jamendo pointer whose stream URL is being fetched
  const loadRef = useRef<(id: number, at?: number, autoplay?: boolean, live?: boolean, retried?: boolean) => void>(() => undefined);
  const warmed = useRef<HTMLAudioElement | null>(null); // the next track's file, fetched ahead
  // A track the schedule names that the catalog in memory does not hold yet (published since it
  // loaded): asked for once (onMissing), then played when the catalog brings it.
  const missing = useRef<{ id: number; autoplay: boolean } | null>(null);
  const onMissingRef = useRef(onMissing);
  onMissingRef.current = onMissing;
  // The station's schedule was read at least once since tuning in: "Nothing on air" is then a fact, not a wait.
  const [synced, setSynced] = useState(false);

  // Latest values for event listeners, so they never read stale state.
  // True between a play and a pause: decides whether a gateway fallback resumes playback.
  const wantsPlay = useRef(false);
  const latest = useRef({ mode, station, queue, index, current });
  latest.current = { mode, station, queue, index, current };

  const chainNow = useCallback(() => Date.now() / 1000 + skew.current, []);

  // live: at is a chain-time offset read now; the seek adds the time the file took to load.
  const load = useCallback(
    (trackId: number, at = 0, autoplay = true, live = false, retried = false) => {
      const t = catalog.current?.byId.get(trackId);
      window.clearTimeout(failNote.current);
      setError("");
      setCurrent(trackId);
      if (!t) {
        // Unknown here: never leave the old track playing as if it were on air.
        audio.pause();
        loadedId.current = 0;
        if (missing.current?.id !== trackId) onMissingRef.current?.(trackId);
        missing.current = { id: trackId, autoplay };
        return;
      }
      missing.current = null;
      const urls = audioURLs(t);
      const src = urls[0];
      if (src === undefined) {
        // A Jamendo stream comes with its bucket's meta (/api/meta): not there yet, fetch it and play then.
        if (!retried && t.audio.startsWith("jamendo:")) {
          const t0 = Date.now();
          awaiting.current = trackId;
          if (autoplay) setBuffering(true);
          void want([{ id: trackId }]).finally(() => {
            if (awaiting.current !== trackId) return; // the listener moved on meanwhile
            awaiting.current = 0;
            loadRef.current(trackId, at + (live ? (Date.now() - t0) / 1000 : 0), autoplay, live, true);
          });
          return;
        }
        setBuffering(false);
        setError("This track has no playable source.");
        return;
      }
      awaiting.current = 0;
      sources.current = { urls, i: 0 };
      // A load of the file already there fires no new loadedmetadata: keep what it answered.
      if (audio.src !== src) {
        audio.src = src;
        gotMeta.current = false;
      }
      loadedId.current = trackId;
      if (pendingSeek.current) audio.removeEventListener("loadedmetadata", pendingSeek.current);
      pendingSeek.current = null;
      const t0 = Date.now();
      const seek = () => {
        pendingSeek.current = null;
        const to = at + (live ? (Date.now() - t0) / 1000 : 0);
        if (to > 0) audio.currentTime = to;
      };
      if (audio.readyState >= HTMLMediaElement.HAVE_METADATA) seek();
      else {
        pendingSeek.current = seek;
        audio.addEventListener("loadedmetadata", seek, { once: true });
      }
      if (autoplay) {
        // archive.org takes 2 to 8 s to start a file: the dial shows it loading until sound comes.
        setBuffering(true);
        audio.play().then(() => { setPlaying(true); }, () => { setPlaying(false); setBuffering(false); });
      }
    },
    [audio],
  );
  loadRef.current = load;

  /** stopLive ends what the radio had running: a pending sync, a fade, the tune-in jingle. */
  const stopLive = useCallback(() => {
    syncSeq.current++;
    awaiting.current = 0;
    window.clearTimeout(endTimer.current);
    stopFade(audioFade);
    ident.current?.pause();
    ident.current = null;
    hourly.current?.pause();
    hourly.current = null;
    audio.volume = userVolume.current;
  }, [audio]);

  // ---- library ----

  // A list plays without its known-dead tracks, from the first live one at or after start
  // (a dead track's own button is disabled); a list with nothing live plays nothing.
  const playList = useCallback(
    (ids: readonly number[], start = 0) => {
      const live = ids.filter((id) => !isDead(catalog.current?.byId.get(id)));
      const first = [...ids.slice(start), ...ids.slice(0, start)].find((id) => live.includes(id));
      if (first === undefined) return;
      const c = catalog.current;
      track("listen", { mode: "library", genre: c?.genres.find((g) => g.id === c.byId.get(first)?.genre)?.name ?? "" });
      stopLive();
      latest.current = { ...latest.current, mode: "library" };
      setMode("library");
      setQueue(live);
      setIndex(live.indexOf(first));
      load(first);
    },
    [load, stopLive],
  );

  const step = useCallback(
    (delta: 1 | -1) => {
      const { mode: m, queue: q, index: i } = latest.current;
      if (m === "live" || q.length === 0) return;
      if (delta === -1 && audio.currentTime > 5) {
        audio.currentTime = 0;
        return;
      }
      const n = (i + delta + q.length) % q.length;
      const id = q[n];
      if (id === undefined) return;
      setIndex(n);
      load(id);
    },
    [audio, load],
  );

  // ---- live ----

  // syncLive through a ref, for the end-of-entry timer it sets itself.
  const syncRef = useRef<(st: number, autoplay: boolean) => Promise<void>>(() => Promise.resolve());
  const syncLive = useCallback(
    async (st: number, autoplay: boolean) => {
      const seq = ++syncSeq.current;
      window.clearTimeout(endTimer.current);
      try {
        const s = await loadSchedule(st);
        // Ignore a response that arrived after the listener changed station or mode.
        if (seq !== syncSeq.current || latest.current.mode !== "live" || latest.current.station !== st) return;
        setSynced(true);
        const fresh = s.now - Date.now() / 1000;
        skewSamples.current = nextSkew(skewSamples.current, fresh);
        skew.current = Math.max(...skewSamples.current);
        const now = chainNow();
        let e = s.entries.find((x) => now >= x.start && now < x.end);
        // ponytail: onyx's catalog/v1 leaves Audius and Jamendo pointers out of ScheduleJSON (they store no
        // title; fixed in catalog PlayableTitle for the next release). A hole now is filled from StationsJSON,
        // which has them; drop this once the deployed realms carry the fix.
        if (!e) {
          const on = await loadOnAir(st).catch(() => undefined);
          if (seq !== syncSeq.current) return;
          const d = on && on.track > 0 ? catalog.current?.byId.get(on.track)?.duration ?? 0 : 0;
          if (on && d > on.offset) {
            const start = now - on.offset;
            const next = s.entries.find((x) => x.start > now)?.start ?? Infinity;
            e = { track: on.track, title: "", start, end: Math.min(start + d, next), offset: 0, queued: on.queued, by: "", note: "" };
          }
        }
        setEntries(e && !s.entries.includes(e) ? [e, ...s.entries] : s.entries);
        // Sync again when this entry ends (or the next one starts, in a gap): a pick that cut
        // the track on air switches every listener on time, not only the one who picked.
        const switchAt = e?.end ?? s.entries.find((x) => x.start > now)?.start;
        // Warm the next track's file 20 s before it airs, so the change is not a few seconds of silence.
        const upcoming = s.entries.find((x) => x.start >= (e?.end ?? now) && x.start > now);
        const warm = upcoming && catalog.current?.byId.get(upcoming.track);
        window.clearTimeout(warmTimer.current);
        if (warm) {
          warmTimer.current = window.setTimeout(() => {
            const src = audioURLs(warm)[0];
            if (src && audio.src !== src) { const a = new Audio(); a.preload = "auto"; a.src = src; warmed.current = a; }
          }, Math.max(0, upcoming.start - now - 20) * 1000);
        }
        if (switchAt !== undefined) {
          endTimer.current = window.setTimeout(() => {
            const l = latest.current;
            if (l.mode === "live" && l.station === st) void syncRef.current(st, !audio.paused);
          }, Math.max(0.5, switchAt - now) * 1000);
        }
        if (!e) {
          // Nothing on air this second: wait for the next entry rather than play it early.
          setError(""); // an empty station is not an error: the player says "Nothing on air yet"
          return;
        }
        setError("");
        // Paused or never played: show what is on air, download nothing until Listen.
        if (!autoplay && audio.paused && !audio.ended) {
          setCurrent(e.track);
          if (!catalog.current?.byId.has(e.track) && missing.current?.id !== e.track) {
            missing.current = { id: e.track, autoplay: false };
            onMissingRef.current?.(e.track);
          }
          return;
        }
        // The file ended before its slot (a duration typed a little long): wait for the next
        // entry in silence; play() on an ended element would start it again from 0.
        if (audio.ended && loadedId.current === e.track) return;
        const at = Math.max(0, now - e.start);
        if (loadedId.current !== e.track && !audio.paused && audio.duration - audio.currentTime > FADE_S) {
          // A listener's pick took the air mid-song: fade the old track out, the pick in.
          await fade(audio, 0, audioFade);
          if (seq !== syncSeq.current) return;
          load(e.track, at + FADE_S, autoplay, true);
          if (!ident.current) void fade(audio, userVolume.current, audioFade);
        } else if (loadedId.current !== e.track || !audio.src || Math.abs(audio.currentTime - at) > DRIFT_S) load(e.track, at, autoplay, true);
        else if (autoplay && audio.paused) audio.play().then(() => { setPlaying(true); }, () => { setPlaying(false); });
        // Tuning in: the track, already playing silently in sync, comes in under the jingle's end.
        const j = ident.current;
        if (j) {
          await tail(j, FADE_S);
          await playingNow(audio);
          if (ident.current !== j) return;
          ident.current = null;
          void fade(j, 0).then(() => { j.pause(); });
          void fade(audio, userVolume.current, audioFade);
        }
      } catch (err) {
        if (seq !== syncSeq.current) return;
        // No schedule: never leave the music silenced under a jingle that has nothing to hand over to.
        stopFade(audioFade);
        ident.current?.pause();
        ident.current = null;
        audio.volume = userVolume.current;
        setError(errorMessage(err));
      }
    },
    [audio, chainNow, load],
  );
  syncRef.current = syncLive;

  const goLive = useCallback(
    (st: number) => {
      track("listen", { mode: "live", station: catalog.current?.stations.find((x) => x.id === st)?.name ?? `#${String(st)}` });
      const same = st === latest.current.station && latest.current.mode === "live"; // entries read are this station's
      if (st !== latest.current.station) setSynced(false);
      stopFade(audioFade);
      setMode("live");
      setStation(st);
      setError("");
      latest.current = { ...latest.current, mode: "live", station: st };
      // The station's jingle, only from a listener's click (never on load), while the track loads.
      ident.current?.pause();
      ident.current = null;
      audio.volume = userVolume.current; // a replaced jingle's silence ends with it (a new one re-zeroes below)
      const c = catalog.current;
      const on = c?.stations.find((x) => x.id === st);
      const name = on?.name;
      const genre = c?.genres.find((g) => g.id === c.byId.get(on?.now.track ?? 0)?.genre)?.name;
      if (name && !audio.muted && userVolume.current > 0 && (!("userActivation" in navigator) || navigator.userActivation.isActive)) {
        const j = new Audio(jingleURL(name, genre));
        j.volume = userVolume.current;
        ident.current = j;
        lastIdent.current = { station: st, at: Date.now() };
        audio.volume = 0;
        void j.play().catch(() => { if (ident.current === j) { ident.current = null; audio.volume = userVolume.current; } });
        window.setTimeout(() => {
          if (ident.current !== j) return;
          ident.current = null;
          j.pause();
          void fade(audio, userVolume.current, audioFade);
        }, IDENT_MAX_MS);
      }
      // Sound within the click (see toggle): what plays, else the station's track on air from the
      // catalog, so the first Listen works before the schedule is read; syncLive then aligns it.
      // The schedule already read for this station (a paused tab shows it without loading it) beats the
      // catalog's snapshot, which may be a cached one from an earlier visit.
      const now = chainNow();
      const read = same ? entriesRef.current.find((x) => now >= x.start && now < x.end) : undefined;
      // Only a file the station has on air now is kept: coming from the library or another station,
      // the old file (loadedId) is the wrong music, never resumed.
      const onAir = read?.track ?? (same ? latest.current.current : on?.now.track);
      if (audio.src && loadedId.current === onAir) {
        if (read) audio.currentTime = now - read.start; // not the old place the pause left: syncLive would jump there later
        void audio.play().catch(() => undefined);
      }
      else if (read) load(read.track, now - read.start, true, true);
      else if (on?.now.track) load(on.now.track, on.now.offset);
      else { audio.pause(); loadedId.current = 0; } // nothing known on air yet: syncLive loads it, the old file stays silent
      void syncLive(st, true);
    },
    [audio, chainNow, load, syncLive],
  );

  // Top of the hour: at the first track change after :00, the station's jingle plays over the
  // change. The music keeps its place, only lowered under it, and the chain clock picks the
  // moment, so every listener hears it together. Once an hour, never just after a tune-in.
  useEffect(() => {
    if (mode !== "live" || !playing) return;
    const id = window.setInterval(() => {
      const change = topOfHour(entries, chainNow());
      if (!change) return;
      const hour = Math.floor(change.start / 3600);
      if (lastHourly.current === hour || ident.current || audio.muted || Date.now() - lastIdent.current.at < HOURLY_GAP_MS) return;
      lastHourly.current = hour;
      const c = catalog.current;
      const name = c?.stations.find((x) => x.id === station)?.name;
      if (!name) return;
      const j = new Audio(jingleURL(name, c.genres.find((g) => g.id === c.byId.get(change.track)?.genre)?.name));
      j.volume = userVolume.current;
      lastIdent.current = { station, at: Date.now() };
      hourly.current = j;
      void j.play().then(() => {
        if (hourly.current !== j) return; // the listener left the radio meanwhile
        void fade(audio, userVolume.current * HOURLY_DUCK, audioFade);
        void tail(j, FADE_S).then(() => {
          if (hourly.current !== j) return;
          hourly.current = null;
          void fade(audio, userVolume.current, audioFade);
        });
      }, () => undefined);
    }, 1000);
    return () => { window.clearInterval(id); };
  }, [audio, chainNow, entries, mode, playing, station]);

  // Show what is on air as soon as the catalog is there, without autoplay (browsers block it anyway).
  const primed = useRef(false);
  useEffect(() => {
    if (!cat || primed.current) return;
    primed.current = true;
    if (latest.current.mode === "live" && latest.current.current === 0) void syncLive(latest.current.station, false);
  }, [cat, syncLive]);

  // The catalog brought a track the schedule asked for: play it now, at the right second on the radio.
  useEffect(() => {
    const m = missing.current;
    if (!m || !cat?.byId.has(m.id)) return;
    missing.current = null;
    if (latest.current.mode === "live") void syncLive(latest.current.station, m.autoplay);
    else load(m.id, 0, m.autoplay);
  }, [cat, load, syncLive]);

  /** resync re-reads the live schedule without interrupting playback (after a Queue, say). */
  const resync = useCallback(() => {
    if (latest.current.mode === "live") void syncLive(latest.current.station, !audio.paused);
  }, [audio, syncLive]);

  useEffect(() => {
    if (mode !== "live") return;
    const id = window.setInterval(() => { if (!document.hidden) void syncLive(station, !audio.paused); }, RESYNC_MS);
    return () => { window.clearInterval(id); };
  }, [audio, mode, station, syncLive]);

  // ---- element events ----

  useEffect(() => {
    const onEnd = () => {
      if (latest.current.mode === "live") void syncLive(latest.current.station, true);
      else step(1);
    };
    const onErr = () => {
      // Try the next gateway (IPFS has several) at the same position before giving up.
      const s = sources.current;
      const nextURL = s.urls[s.i + 1];
      if (nextURL !== undefined) {
        const t0 = Date.now();
        const live = latest.current.mode === "live";
        // On the radio the place is the chain's, not the failed element's (0 if it never got metadata).
        const now = chainNow();
        const onAir = live ? entriesRef.current.find((x) => now >= x.start && now < x.end && x.track === loadedId.current) : undefined;
        const at = onAir ? now - onAir.start : audio.currentTime;
        sources.current = { urls: s.urls, i: s.i + 1 };
        audio.src = nextURL;
        // Same place on the next gateway (plus the switch time on the radio), dropped by the next load().
        if (pendingSeek.current) audio.removeEventListener("loadedmetadata", pendingSeek.current);
        const seek = () => {
          pendingSeek.current = null;
          const to = at + (live ? (Date.now() - t0) / 1000 : 0);
          if (to > 0) audio.currentTime = to;
        };
        pendingSeek.current = seek;
        audio.addEventListener("loadedmetadata", seek, { once: true });
        // Resume only if the listener was playing (a primed, paused station stays silent).
        if (wantsPlay.current) void audio.play().catch(() => undefined);
        return;
      }
      // On the radio, a stream that drops (a CDN hiccup, a rate limit) is tuned again once,
      // silently, before the listener is told anything.
      if (latest.current.mode === "live" && skips.current === 0) {
        skips.current++;
        void syncLive(latest.current.station, wantsPlay.current);
        return;
      }
      // Every source failed and none ever answered for this load: the track is dead, its buttons
      // grey out everywhere. One that answered then dropped is the network, not the file.
      // A Jamendo stream is a signed URL that may have expired: forget the bucket's meta once, the next want() fetches it again.
      if (audio.src.includes("jamendo.com")) { dropBucket(loadedId.current); void want([{ id: loadedId.current }]); } else if (!gotMeta.current) markDead(loadedId.current);
      // Every source failed: stop, and in an album or playlist go on with the next track
      // (twice in a row at most: more is the network, not the files). The note stays until sound.
      audio.pause();
      setPlaying(false);
      setBuffering(false);
      const { mode: m, queue: q } = latest.current;
      if (m === "library" && q.length > 1 && skips.current < Math.min(q.length, 2)) {
        skips.current++;
        step(1);
      }
      // Say it only if no sound came back within 6 s: a short drop is not worth a red line.
      window.clearTimeout(failNote.current);
      failNote.current = window.setTimeout(() => { setError(NOT_RESPONDING); }, NOT_RESPONDING_AFTER_MS);
    };
    const onPause = () => { wantsPlay.current = false; setPlaying(false); setBuffering(false); };
    const onPlay = () => { wantsPlay.current = true; setPlaying(true); };
    const onSound = () => {
      skips.current = 0;
      window.clearTimeout(failNote.current);
      setError((e) => (e === NOT_RESPONDING ? "" : e));
    };
    // waiting/stalled: the network is behind; playing/canplay: sound again.
    const onWait = () => { if (!audio.paused) setBuffering(true); };
    const onFlow = () => { setBuffering(false); };
    const onMeta = () => { gotMeta.current = true; };
    audio.addEventListener("loadedmetadata", onMeta);
    audio.addEventListener("waiting", onWait);
    audio.addEventListener("stalled", onWait);
    audio.addEventListener("playing", onFlow);
    audio.addEventListener("playing", onSound);
    audio.addEventListener("canplay", onFlow);
    audio.addEventListener("ended", onEnd);
    audio.addEventListener("error", onErr);
    audio.addEventListener("pause", onPause);
    audio.addEventListener("play", onPlay);
    return () => {
      audio.removeEventListener("loadedmetadata", onMeta);
      audio.removeEventListener("ended", onEnd);
      audio.removeEventListener("error", onErr);
      audio.removeEventListener("pause", onPause);
      audio.removeEventListener("play", onPlay);
      audio.removeEventListener("waiting", onWait);
      audio.removeEventListener("stalled", onWait);
      audio.removeEventListener("playing", onFlow);
      audio.removeEventListener("playing", onSound);
      audio.removeEventListener("canplay", onFlow);
    };
  }, [audio, chainNow, step, syncLive]);

  useEffect(
    () => () => {
      window.clearTimeout(failNote.current);
      window.clearTimeout(endTimer.current);
      audio.pause();
      audio.removeAttribute("src");
      audio.load();
    },
    [audio],
  );

  const toggle = useCallback(() => {
    const { mode: m, station: st, current: cur } = latest.current;
    if (cur === 0) {
      if (m === "live") goLive(st);
      else if (cat?.tracks.length) playList(cat.tracks.map((t) => t.id));
      return;
    }
    if (!audio.paused) {
      audio.pause();
      return;
    }
    // On the radio, listening is tuning in (jingle, then what is on air now), unless this
    // station's jingle played moments ago: then the radio just comes back at once.
    if (m === "live" && !(lastIdent.current.station === st && Date.now() - lastIdent.current.at < IDENT_AGAIN_MS)) {
      goLive(st);
      return;
    }
    // play() inside the click itself: after the network wait, browsers
    // (Safari first) no longer count it as a user gesture and refuse it.
    void audio.play().catch(() => undefined);
    if (m === "live") void syncLive(st, true);
  }, [audio, cat, goLive, playList, syncLive]);

  const seek = useCallback(
    (frac: number) => {
      const t = cat?.byId.get(latest.current.current);
      if (!t || latest.current.mode === "live") return;
      const total = Number.isFinite(audio.duration) ? audio.duration : t.duration;
      audio.currentTime = Math.min(Math.max(frac, 0), 1) * total;
    },
    [audio, cat],
  );

  const next = useCallback(() => { step(1); }, [step]);
  const prev = useCallback(() => { step(-1); }, [step]);
  /** toLibrary stops the radio: what was on air becomes a local queue of one, paused. */
  const toLibrary = useCallback(() => {
    stopLive();
    audio.pause();
    setMode("library");
    setError("");
    const cur = latest.current.current;
    if (cur && latest.current.mode === "live") {
      setQueue([cur]);
      setIndex(0);
    }
  }, [audio, stopLive]);

  // ---- volume ----

  useEffect(() => {
    audio.volume = volume;
    audio.muted = muted;
  }, [audio, volume, muted]);
  const setVolume = useCallback((v: number) => {
    const x = Math.min(1, Math.max(0, v));
    setVolumeState(x);
    setMuted(false);
    try { localStorage.setItem("gnoradio.volume", String(x)); } catch { /* private mode */ }
  }, []);
  const toggleMute = useCallback(() => { setMuted((m) => !m); }, []);

  /** nudge moves the playhead by seconds (Library only: live follows the chain). */
  const nudge = useCallback((by: number) => {
    if (latest.current.mode === "live" || !Number.isFinite(audio.duration)) return;
    audio.currentTime = Math.min(audio.duration, Math.max(0, audio.currentTime + by));
  }, [audio]);

  return useMemo(
    () => ({ audio, mode, station, queue, index, current, playing, buffering, volume, muted, entries, error, synced, chainNow, playList, goLive, resync, toggle, seek, nudge, next, prev, toLibrary, setVolume, toggleMute }),
    [audio, mode, station, queue, index, current, playing, buffering, volume, muted, entries, error, synced, chainNow, playList, goLive, resync, toggle, seek, nudge, next, prev, toLibrary, setVolume, toggleMute],
  );
}

/**
 * usePosition subscribes to the playback position on its own, so only the
 * components that show it re-render ~4 times a second, not the whole app.
 */
export function usePosition(audio: HTMLAudioElement): number {
  return useSyncExternalStore(
    (onChange) => {
      audio.addEventListener("timeupdate", onChange);
      audio.addEventListener("emptied", onChange);
      return () => {
        audio.removeEventListener("timeupdate", onChange);
        audio.removeEventListener("emptied", onChange);
      };
    },
    () => audio.currentTime,
  );
}

export type Player = ReturnType<typeof usePlayer>;
