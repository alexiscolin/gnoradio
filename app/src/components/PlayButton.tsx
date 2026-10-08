import { UNAVAILABLE, usePlayable } from "../lib/playable";
import type { Track } from "../lib/types";
import { Icon } from "./Icons";

/**
 * PlayButton is the one way a page plays its tracks: ink, an icon, first in its row.
 * It probes its tracks at once and greys out when none of them has working audio.
 */
export function PlayButton({ label = "Play", tracks, onClick, className = "" }: {
  readonly label?: string; readonly tracks: readonly Pick<Track, "id" | "audio">[]; readonly onClick: () => void; readonly className?: string;
}) {
  const { allDead } = usePlayable(tracks);
  return (
    <button className={`play cta play-btn ${className}`.trim()} disabled={allDead} title={allDead ? UNAVAILABLE : undefined} onClick={onClick}>
      <Icon name="play" size={16} /> {allDead ? UNAVAILABLE : label}
    </button>
  );
}
