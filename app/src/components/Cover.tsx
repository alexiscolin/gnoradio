import { useState } from "react";
import { fnv } from "../lib/format";
import { mediaURLs } from "../lib/safe";
import type { Track } from "../lib/types";

/** useArtwork is a track's real cover, if it has one: ipfs://, ar:// or https:// (scheme-checked at load).
 * An Audius or Jamendo pointer's cover arrives with its title (lib/refs.ts). */
export function useArtwork(t: Track | undefined): string {
  return mediaURLs(t?.cover ?? "")[0] ?? "";
}

/** Cover shows the real artwork, or the same generated composition the realm draws. */
export function Cover({ t, size = "100%" }: { t: Track | undefined; size?: string }) {
  const art = useArtwork(t);
  const [loaded, setLoaded] = useState("");
  const [broken, setBroken] = useState("");
  if (!t) return <div className="cover" style={{ width: size }} />;
  // The generated cover is always drawn; the real artwork fades in on top once loaded, so nothing jumps.
  const show = art && broken !== art;
  return (
    <div className={`cover v${String(fnv(`${t.id}${t.title}`) % 6)}`} style={{ width: size }} role="img" aria-label={`Cover of ${t.title}`}>
      <i />
      <b />
      {show && (
        <img key={art} className={`cover-art${loaded === art ? " in" : ""}`} src={art} alt="" loading="lazy" decoding="async"
          onLoad={() => { setLoaded(art); }} onError={() => { setBroken(art); }} />
      )}
    </div>
  );
}
