import { useEffect, useRef, useState } from "react";
import { fnv } from "../lib/format";
import { mediaURLs } from "../lib/safe";
import type { Track } from "../lib/types";

// One request per Audius track per session, shared by every cover showing it.
const audiusArt = new Map<string, Promise<string>>();

function audiusArtwork(audiusId: string): Promise<string> {
  let p = audiusArt.get(audiusId);
  if (!p) {
    p = fetch(`https://api.audius.co/v1/tracks/${encodeURIComponent(audiusId)}?app_name=GnoRadio`)
      .then((r) => (r.ok ? (r.json() as Promise<AudiusTrack>) : Promise.reject(new Error(String(r.status)))))
      .then((j) => j.data?.artwork?.["480x480"] ?? "");
    p.catch(() => { audiusArt.delete(audiusId); }); // a refusal (429) is tried again later, not kept
    audiusArt.set(audiusId, p);
  }
  return p;
}

interface AudiusTrack {
  data?: { artwork?: Record<string, string | undefined> };
}

/**
 * useArtwork resolves a track's real cover; Audius artwork is read live (session use, per their terms).
 * wanted false holds the Audius call back (a row not on screen yet): long lists must not burst Audius's rate limit.
 */
export function useArtwork(t: Track | undefined, wanted = true): string {
  const [url, setUrl] = useState("");
  const id = t?.id;
  const cover = t?.cover ?? "";
  const audio = t?.audio ?? "";
  useEffect(() => {
    setUrl("");
    if (id === undefined) return;
    // ipfs://, ar:// and https:// covers resolve directly (cover is already scheme-checked at load).
    const direct = cover.startsWith("audius:") ? undefined : mediaURLs(cover)[0];
    if (direct !== undefined) {
      setUrl(direct);
      return;
    }
    if (!audio.startsWith("audius:") || !wanted) return;
    let alive = true;
    audiusArtwork(audio.slice(7)).then((u) => { if (alive) setUrl(u); }, () => undefined);
    return () => { alive = false; };
  }, [id, cover, audio, wanted]);
  return url;
}

/** Cover shows the real artwork, or the same generated composition the realm draws. */
export function Cover({ t, size = "100%" }: { t: Track | undefined; size?: string }) {
  const box = useRef<HTMLDivElement>(null);
  const [seen, setSeen] = useState(false);
  useEffect(() => {
    const el = box.current;
    if (seen || !el) return;
    if (typeof IntersectionObserver === "undefined") { setSeen(true); return; } // old browsers and tests: load now
    const io = new IntersectionObserver((es) => { if (es.some((e) => e.isIntersecting)) setSeen(true); }, { rootMargin: "200px" });
    io.observe(el);
    return () => { io.disconnect(); };
  }, [seen, t]);
  const art = useArtwork(t, seen);
  const [loaded, setLoaded] = useState("");
  const [broken, setBroken] = useState("");
  if (!t) return <div ref={box} className="cover" style={{ width: size }} />;
  // The generated cover is always drawn; the real artwork fades in on top once loaded, so nothing jumps.
  const show = art && broken !== art;
  return (
    <div ref={box} className={`cover v${String(fnv(`${t.id}${t.title}`) % 6)}`} style={{ width: size }} role="img" aria-label={`Cover of ${t.title}`}>
      <i />
      <b />
      {show && (
        <img key={art} className={`cover-art${loaded === art ? " in" : ""}`} src={art} alt="" loading="lazy" decoding="async"
          onLoad={() => { setLoaded(art); }} onError={() => { setBroken(art); }} />
      )}
    </div>
  );
}
