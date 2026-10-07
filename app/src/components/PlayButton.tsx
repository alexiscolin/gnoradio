import { Icon } from "./Icons";

/** PlayButton is the one way a page plays its tracks: ink, an icon, first in its row. */
export function PlayButton({ label = "Play", onClick, className = "" }: { readonly label?: string; readonly onClick: () => void; readonly className?: string }) {
  return <button className={`play cta play-btn ${className}`.trim()} onClick={onClick}><Icon name="play" size={16} /> {label}</button>;
}
