import { useCallback, useEffect, useMemo, useRef, useState, useSyncExternalStore } from "react";
import { audioURL, loadSchedule } from "../lib/catalog";
import { errorMessage } from "../lib/format";
import type { Catalog, ScheduleEntry } from "../lib/types";

export type Mode = "library" | "live";

const RESYNC_MS = 5 * 60_000; // the schedule covers an hour; resync also on track end
const DRIFT_S = 4;

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
  const [mode, setMode] = useState<Mode>("library");
  const [station, setStation] = useState(0);
  const [queue, setQueue] = useState<readonly number[]>([]);
  const [index, setIndex] = useState(0);
  const [current, setCurrent] = useState(0);
  const [playing, setPlaying] = useState(false);
  const [entries, setEntries] = useState<readonly ScheduleEntry[]>([]);
  const [error, setError] = useState("");
  const skew = useRef(0); // chain clock minus local clock, seconds
  const syncSeq = useRef(0); // drops stale schedule responses
  const pendingSeek = useRef<(() => void) | null>(null);

  // Latest values for event listeners, so they never read stale state.
  const latest = useRef({ mode, station, queue, index, current });
  latest.current = { mode, station, queue, index, current };

  const chainNow = useCallback(() => Date.now() / 1000 + skew.current, []);

  const load = useCallback(
    (trackId: number, at = 0, autoplay = true) => {
      const t = cat?.byId.get(trackId);
      if (!t) return;
      setError("");
      setCurrent(trackId);
      const src = audioURL(t);
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
        const at = Math.max(0, now - e.start);
        if (latest.current.current !== e.track || Math.abs(audio.currentTime - at) > DRIFT_S) load(e.track, at, autoplay);
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
      latest.current = { ...latest.current, mode: "live", station: st };
      void syncLive(st, true);
    },
    [syncLive],
  );

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
    const onErr = () => { setError("This file could not be played (source offline?)."); };
    const onPause = () => { setPlaying(false); };
    const onPlay = () => { setPlaying(true); };
    audio.addEventListener("ended", onEnd);
    audio.addEventListener("error", onErr);
    audio.addEventListener("pause", onPause);
    audio.addEventListener("play", onPlay);
    return () => {
      audio.removeEventListener("ended", onEnd);
      audio.removeEventListener("error", onErr);
      audio.removeEventListener("pause", onPause);
      audio.removeEventListener("play", onPlay);
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
    if (m === "live") void syncLive(st, true);
    else void audio.play().catch(() => undefined);
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
  const toLibrary = useCallback(() => {
    setMode("library");
    syncSeq.current++;
  }, []);

  return useMemo(
    () => ({ audio, mode, station, queue, index, current, playing, entries, error, chainNow, playList, goLive, resync, toggle, seek, next, prev, toLibrary }),
    [audio, mode, station, queue, index, current, playing, entries, error, chainNow, playList, goLive, resync, toggle, seek, next, prev, toLibrary],
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
