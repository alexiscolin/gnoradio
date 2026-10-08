// Station jingles (archive.org item gnoradio-jingles, CC BY 4.0, see NOTICE): served by
// archive.org, not by the site, to keep Netlify's bandwidth for the app itself. Played on
// tuning into a live station only, never in the library or when the app opens.
const JINGLES = "https://archive.org/download/gnoradio-jingles";

// Main's jingle follows the music on air: the variant closest to the genre playing
// (Rock and Metal keep the original, the most energetic).
const MAIN_BY_GENRE: Readonly<Record<string, string>> = {
  Electronica: "main-3", Synthwave: "main-3", Techno: "main-3", House: "main-3", "Drum & Bass": "main-3", "Dubstep & Trap": "main-3",
  Ambient: "main-1", "Lo-fi Beats": "main-1", "Folk & Acoustic": "main-1",
  "Jazz & Blues": "main-2", "R&B & Soul": "main-2", "Hip-hop & Rap": "main-2", "Funk & Disco": "main-2", Pop: "main-2",
  World: "main-4", Latin: "main-4", "Reggae & Dub": "main-4",
  "Cinematic & Classical": "main-5",
};

/** jingleURL is a station's jingle file, named after the station ("R&B & Soul" → rnb-and-soul.mp3); Main's follows genre, the genre on air. */
export const jingleURL = (station: string, genre = ""): string =>
  station === "Main"
    ? `${JINGLES}/${MAIN_BY_GENRE[genre] ?? "main"}.mp3`
    : `${JINGLES}/${station.toLowerCase().replace("r&b", "rnb").replace("lo-fi", "lofi").replaceAll("&", "and").replaceAll("'", "").replace(/\s+/g, "-")}.mp3`;

/** STALL_MS: a jingle that makes no progress this long (archive.org slow or silent) is given up on, so the music is never held back by it. */
export const STALL_MS = 3000;

/** tail resolves once the jingle is within s seconds of its end (or ended, or failed, or stalled for STALL_MS: the caller then fades it out and brings the station in). */
export const tail = (j: HTMLAudioElement, s: number): Promise<void> =>
  new Promise((done) => {
    let watchdog = 0;
    const finish = () => {
      window.clearTimeout(watchdog);
      for (const e of ["timeupdate", "ended", "error"]) j.removeEventListener(e, check);
      done();
    };
    const check = () => {
      if (!j.ended && !j.error && !(j.duration > 0 && j.currentTime >= j.duration - s)) { // still going: it has STALL_MS to show progress
        window.clearTimeout(watchdog);
        watchdog = window.setTimeout(finish, STALL_MS);
        return;
      }
      finish();
    };
    for (const e of ["timeupdate", "ended", "error"]) j.addEventListener(e, check);
    check();
  });

/** playingNow resolves once the element actually sounds. */
export const playingNow = (a: HTMLAudioElement): Promise<void> =>
  !a.paused && a.readyState >= 3 ? Promise.resolve() : new Promise((done) => { a.addEventListener("playing", () => { done(); }, { once: true }); });

/**
 * topOfHour is the schedule entry whose start is the first track change of the
 * current hour, when now falls in the few seconds after it: the moment for the
 * hourly jingle. Picked from the chain clock, so every listener gets the same one.
 */
export function topOfHour<E extends { readonly start: number }>(entries: readonly E[], now: number, within = 3): E | undefined {
  const change = entries.find((e) => e.start >= Math.floor(now / 3600) * 3600);
  return change && now >= change.start && now <= change.start + within ? change : undefined;
}
