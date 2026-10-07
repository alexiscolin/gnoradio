import { useEffect } from "react";
import type { Catalog, View } from "../lib/types";
import { viewName } from "../lib/catalog";
import { pageTitle } from "../lib/seo";
import { useArtwork } from "../components/Cover";
import type { Player } from "./usePlayer";

const APP = "GnoRadio";

/**
 * useMediaMeta names the tab after what is playing ("● Title · Artist — Techno
 * live"), or after the screen when nothing plays, and tells the OS (lock
 * screen, headset keys, media hub) what is playing.
 */
export function useMediaMeta(cat: Catalog | null, view: View, player: Player): void {
  const t = cat?.byId.get(player.current);
  const live = player.mode === "live";
  const stationName = cat?.stations.find((s) => s.id === player.station)?.name;
  const page = pageTitle(view, viewName(cat, view));
  const onAir = player.playing && t ? `${live ? "●" : "▶"} ${t.title} · ${t.artistName}${live ? ` — ${stationName ?? "Main"} live` : ""}` : "";
  useEffect(() => {
    document.title = onAir || page;
  }, [onAir, page]);
  const art = useArtwork(t);
  useEffect(() => {
    if (!("mediaSession" in navigator)) return;
    const ms = navigator.mediaSession;
    if (!t) {
      ms.metadata = null;
      return;
    }
    ms.metadata = new MediaMetadata({
      title: t.title,
      artist: t.artistName,
      album: live && stationName ? `${stationName} · live on ${APP}` : APP,
      // The track's cover on the lock screen; the app icon when it has none.
      artwork: art ? [{ src: art, sizes: "480x480" }] : [{ src: "/apple-touch-icon.png", sizes: "180x180", type: "image/png" }],
    });
  }, [t, live, stationName, art]);

  const { toggle, next, prev, audio, goLive, station } = player;
  // On the radio, next/previous zap between stations (those with tracks), like a tuner.
  const ids = cat?.stations.filter((s) => s.tracks > 0).map((s) => s.id).join(",") ?? "";
  useEffect(() => {
    if (!("mediaSession" in navigator)) return;
    const ms = navigator.mediaSession;
    const set = (a: MediaSessionAction, h: MediaSessionActionHandler | null) => {
      try {
        ms.setActionHandler(a, h);
      } catch {
        // Unsupported action on this browser.
      }
    };
    // play/pause from the OS are explicit: a "pause" while paused must not start playback.
    set("play", () => { if (audio.paused) toggle(); });
    set("pause", () => { if (!audio.paused) audio.pause(); });
    // A live station follows the chain's schedule: the keys change station instead.
    const list = ids ? ids.split(",").map(Number) : [];
    const zap = (d: number) => () => {
      const i = list.indexOf(station);
      const to = list[(i + d + list.length) % list.length];
      if (to !== undefined) goLive(to);
    };
    set("nexttrack", live ? (list.length > 1 ? zap(1) : null) : next);
    set("previoustrack", live ? (list.length > 1 ? zap(-1) : null) : prev);
    return () => {
      for (const a of ["play", "pause", "nexttrack", "previoustrack"] as const) set(a, null);
    };
  }, [toggle, next, prev, live, audio, goLive, station, ids]);

  useEffect(() => {
    if ("mediaSession" in navigator) navigator.mediaSession.playbackState = player.playing ? "playing" : "paused";
  }, [player.playing]);
}
