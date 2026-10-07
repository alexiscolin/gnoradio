import { useEffect } from "react";
import type { Catalog, View } from "../lib/types";
import { useArtwork } from "../components/Cover";
import type { Player } from "./usePlayer";

const APP = "GnoRadio";

/** viewTitle names a screen for the browser tab: "Air · Scott Buckley — GnoRadio". */
export function viewTitle(cat: Catalog, v: View): string {
  const named = (s: string | undefined) => (s ? `${s} — ${APP}` : APP);
  switch (v.k) {
    case "listen":
      return `${APP} · Community radio, open music`;
    case "track": {
      const t = cat.byId.get(v.id);
      return named(t ? `${t.title} · ${t.artistName}` : undefined);
    }
    case "artist":
      return named(cat.artists.get(v.id)?.name);
    case "album":
      return named(cat.albums.find((a) => a.id === v.id)?.title);
    case "playlist":
      return named(cat.playlists.find((p) => p.id === v.id)?.title);
    case "library":
      return named(v.genre ? cat.genres.find((g) => g.id === v.genre)?.name : "Library");
    case "contribute":
      return named("Contribute");
    case "about":
      return named("About");
    case "stations":
      return named("Stations");
    case "concerts":
      return named("Concerts");
    case "community":
      return named("Community");
    case "me":
      return named("Me");
    case "studio":
      return named("Studio");
  }
}

/**
 * useMediaMeta keeps the tab title in step with the screen, and tells the OS
 * (lock screen, headset keys, media hub) what is playing.
 */
export function useMediaMeta(cat: Catalog | null, view: View, player: Player): void {
  useEffect(() => {
    if (cat) document.title = viewTitle(cat, view);
  }, [cat, view]);

  const t = cat?.byId.get(player.current);
  const live = player.mode === "live";
  const stationName = cat?.stations.find((s) => s.id === player.station)?.name;
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

  const { toggle, next, prev, audio } = player;
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
    // A live station follows the chain's schedule: no skipping.
    set("nexttrack", live ? null : next);
    set("previoustrack", live ? null : prev);
    return () => {
      for (const a of ["play", "pause", "nexttrack", "previoustrack"] as const) set(a, null);
    };
  }, [toggle, next, prev, live, audio]);

  useEffect(() => {
    if ("mediaSession" in navigator) navigator.mediaSession.playbackState = player.playing ? "playing" : "paused";
  }, [player.playing]);
}
