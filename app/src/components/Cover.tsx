import { useEffect, useState } from "react";
import { fnv } from "../lib/format";
import type { Track } from "../lib/types";

const audiusArt = new Map<string, string>();

interface AudiusTrack {
  data?: { artwork?: Record<string, string | undefined> };
}

/** useArtwork resolves a track's real cover; Audius artwork is read live (session use, per their terms). */
function useArtwork(t: Track | undefined): string {
  const [url, setUrl] = useState("");
  const id = t?.id;
  const cover = t?.cover ?? "";
  const audio = t?.audio ?? "";
  useEffect(() => {
    setUrl("");
    if (id === undefined) return;
    if (cover.startsWith("ipfs://")) {
      setUrl(`https://ipfs.io/ipfs/${cover.slice(7)}`);
      return;
    }
    if (cover.startsWith("https://")) {
      setUrl(cover);
      return;
    }
    if (!audio.startsWith("audius:")) return;
    const audiusId = audio.slice(7);
    const cached = audiusArt.get(audiusId);
    if (cached !== undefined) {
      setUrl(cached);
      return;
    }
    const ctrl = new AbortController();
    fetch(`https://api.audius.co/v1/tracks/${encodeURIComponent(audiusId)}?app_name=GnoRadio`, { signal: ctrl.signal })
      .then((r) => (r.ok ? (r.json() as Promise<AudiusTrack>) : Promise.reject(new Error(String(r.status)))))
      .then((j) => {
        const u = j.data?.artwork?.["480x480"] ?? "";
        audiusArt.set(audiusId, u);
        setUrl(u);
      })
      .catch(() => undefined);
    return () => { ctrl.abort(); };
  }, [id, cover, audio]);
  return url;
}

/** Cover shows the real artwork, or the same generated composition the realm draws. */
export function Cover({ t, size = "100%" }: { t: Track | undefined; size?: string }) {
  const art = useArtwork(t);
  const [broken, setBroken] = useState("");
  if (!t) return <div className="cover" style={{ width: size }} />;
  if (art && broken !== art) {
    return <img key={art} className="cover" style={{ width: size }} src={art} alt={`Cover of ${t.title}`} loading="lazy" onError={() => { setBroken(art); }} />;
  }
  return (
    <div className={`cover v${String(fnv(`${t.id}${t.title}`) % 6)}`} style={{ width: size }} role="img" aria-label={`Cover of ${t.title}`}>
      <i />
      <b />
    </div>
  );
}
