import { useCallback, useEffect, useMemo, useRef, useState, useSyncExternalStore } from "react";
import { audioURLs, loadSchedule } from "../lib/catalog";
import { errorMessage } from "../lib/format";
import type { Catalog, ScheduleEntry } from "../lib/types";

export type Mode = "library" | "live";

const RESYNC_MS = 5 * 60_000; // the schedule covers an hour; resync also on track end
const DRIFT_S = 4;
const FADE_S = 1.2;

/** fade ramps the element's volume to v over FADE_S (timers, so it also ends in a background tab). */
function fade(a: HTMLAudioElement, v: number): Promise<void> {
  const from = a.volume;
  const t0 = Date.now();
  return new Promise((done) => {
    const id = window.setInterval(() => {
      const k = Math.min(1, (Date.now() - t0) / (FADE_S * 1000));
      a.volume = from + (v - from) * k;
      if (k === 1) {
        window.clearInterval(id);
        done();
      }
    }, 40);
  });
}

/**
 * usePlayer drives one <audio> element in two modes:
 *  - library: an ordered queue the listener controls;
 *  - live: a station's on-chain schedule, joined at the right second.
 */
export function usePlayer(cat: Catalog | null) {
  const [audio] = useState(() => {
    const a = new Audio();
    a.crossOrigin = "anonymous";
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
  userVolume.current = volume;
  const [entries, setEntries] = useState<readonly ScheduleEntry[]>([]);
  const [error, setError] = useState("");
  const skew = useRef(0); // chain clock minus local clock, seconds
  const syncSeq = useRef(0); // drops stale schedule responses
  const pendingSeek = useRef<(() => void) | null>(null);
  const sources = useRef<{ urls: readonly string[]; i: number }>({ urls: [], i: 0 }); // gateway fallbacks

  // Latest values for event listeners, so they never read stale state.
  // True between a play and a pause: decides whether a gateway fallback resumes playback.
  const wantsPlay = useRef(false);
  const latest = useRef({ mode, station, queue, index, current });
  latest.current = { mode, station, queue, index, current };

  const chainNow = useCallback(() => Date.now() / 1000 + skew.current, []);

  const load = useCallback(
    (trackId: number, at = 0, autoplay = true) => {
      const t = cat?.byId.get(trackId);
      if (!t) return;
      setError("");
      setCurrent(trackId);
      const urls = audioURLs(t);
      const src = urls[0];
      if (src === undefined) {
        setError("This track has no playable source.");
        return;
      }
      sources.current = { urls, i: 0 };
      if (audio.src !== src) audio.src = src;
      if (pendingSeek.current) audio.removeEventListener("loadedmetadata", pendingSeek.current);
      pendingSeek.current = null;
      const seek = () => {
        pendingSeek.current = null;
        if (at > 0) audio.currentTime = at;
      };
      if (audio.readyState >= HTMLMediaElement.HAVE_METADATA) seek();
      else {
        pendingSeek.current = seek;
        audio.addEventListener("loadedmetadata", seek, { once: true });
      }
      if (autoplay) {
        audio.play().then(() => { setPlaying(true); }, () => { setPlaying(false); });
      }
    },
    [audio, cat],
  );

  // ---- library ----

  const playList = useCallback(
    (ids: readonly number[], start = 0) => {
      const first = ids[start];
      if (first === undefined) return;
      setMode("library");
      setQueue(ids);
      setIndex(start);
      load(first);
    },
    [load],
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

  const syncLive = useCallback(
    async (st: number, autoplay: boolean) => {
      const seq = ++syncSeq.current;
      try {
        const s = await loadSchedule(st);
        // Ignore a response that arrived after the listener changed station or mode.
        if (seq !== syncSeq.current || latest.current.mode !== "live" || latest.current.station !== st) return;
        skew.current = s.now - Date.now() / 1000;
        setEntries(s.entries);
        const now = chainNow();
        const e = s.entries.find((x) => now >= x.start && now < x.end) ?? s.entries[0];
        if (!e) {
          setError("Nothing on air on this station yet.");
          return;
        }
        setError("");
        const at = Math.max(0, now - e.start);
        if (latest.current.current !== e.track && !audio.paused && audio.duration - audio.currentTime > FADE_S) {
          // A listener's pick took the air mid-song: fade the old track out, the pick in.
          await fade(audio, 0);
          if (seq !== syncSeq.current) return;
          load(e.track, at + FADE_S, autoplay);
          void fade(audio, userVolume.current);
        } else if (latest.current.current !== e.track || Math.abs(audio.currentTime - at) > DRIFT_S) load(e.track, at, autoplay);
        else if (autoplay && audio.paused) audio.play().then(() => { setPlaying(true); }, () => { setPlaying(false); });
      } catch (err) {
        if (seq === syncSeq.current) setError(errorMessage(err));
      }
    },
    [audio, chainNow, load],
  );

  const goLive = useCallback(
    (st: number) => {
      setMode("live");
      setStation(st);
      setError("");
      latest.current = { ...latest.current, mode: "live", station: st };
      if (audio.src) void audio.play().catch(() => undefined); // unlock within the click, see toggle
      void syncLive(st, true);
    },
    [audio, syncLive],
  );

  // Show what is on air as soon as the catalog is there, without autoplay (browsers block it anyway).
  const primed = useRef(false);
  useEffect(() => {
    if (!cat || primed.current) return;
    primed.current = true;
    if (latest.current.mode === "live" && latest.current.current === 0) void syncLive(latest.current.station, false);
  }, [cat, syncLive]);

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
        const at = audio.currentTime;
        sources.current = { urls: s.urls, i: s.i + 1 };
        audio.src = nextURL;
        if (at > 0) audio.addEventListener("loadedmetadata", () => { audio.currentTime = at; }, { once: true });
        // Resume only if the listener was playing (a primed, paused station stays silent).
        if (wantsPlay.current) void audio.play().catch(() => undefined);
        return;
      }
      setError("This file could not be played (source offline?).");
    };
    const onPause = () => { wantsPlay.current = false; setPlaying(false); setBuffering(false); };
    const onPlay = () => { wantsPlay.current = true; setPlaying(true); };
    // waiting/stalled: the network is behind; playing/canplay: sound again.
    const onWait = () => { if (!audio.paused) setBuffering(true); };
    const onFlow = () => { setBuffering(false); };
    audio.addEventListener("waiting", onWait);
    audio.addEventListener("stalled", onWait);
    audio.addEventListener("playing", onFlow);
    audio.addEventListener("canplay", onFlow);
    audio.addEventListener("ended", onEnd);
    audio.addEventListener("error", onErr);
    audio.addEventListener("pause", onPause);
    audio.addEventListener("play", onPlay);
    return () => {
      audio.removeEventListener("ended", onEnd);
      audio.removeEventListener("error", onErr);
      audio.removeEventListener("pause", onPause);
      audio.removeEventListener("play", onPlay);
      audio.removeEventListener("waiting", onWait);
      audio.removeEventListener("stalled", onWait);
      audio.removeEventListener("playing", onFlow);
      audio.removeEventListener("canplay", onFlow);
    };
  }, [audio, step, syncLive]);

  useEffect(
    () => () => {
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
    // play() inside the click itself: after the network wait below, browsers
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
    syncSeq.current++;
    audio.pause();
    setMode("library");
    setError("");
    const cur = latest.current.current;
    if (cur && latest.current.mode === "live") {
      setQueue([cur]);
      setIndex(0);
    }
  }, [audio]);

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
    () => ({ audio, mode, station, queue, index, current, playing, buffering, volume, muted, entries, error, chainNow, playList, goLive, resync, toggle, seek, nudge, next, prev, toLibrary, setVolume, toggleMute }),
    [audio, mode, station, queue, index, current, playing, buffering, volume, muted, entries, error, chainNow, playList, goLive, resync, toggle, seek, nudge, next, prev, toLibrary, setVolume, toggleMute],
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
