import type { ReactNode } from "react";

// GnoRadio's line icons: a 24px grid, 1.75 stroke, round caps, currentColor.
// Drawn here (no icon dependency). Always decorative: the control carries the label.

const PATHS = {
  "arrow-right": <path d="M5 12h14M13 6l6 6-6 6" />,
  "arrow-left": <path d="M19 12H5M11 6l-6 6 6 6" />,
  share: <><path d="M12 15V4M8 8l4-4 4 4" /><path d="M6 12v7h12v-7" /></>,
  external: <path d="M7 17 17 7M9 7h8v8" />,
  "chevron-down": <path d="m6 9 6 6 6-6" />,
  close: <path d="M6 6l12 12M18 6 6 18" />,
  prev: <><path d="M6 5v14" /><path d="M18 6v12l-9-6z" fill="currentColor" /></>,
  next: <><path d="M18 5v14" /><path d="M6 6v12l9-6z" fill="currentColor" /></>,
  play: <path d="M7 5v14l12-7z" fill="currentColor" />,
  stop: <rect x="6" y="6" width="12" height="12" rx="1.5" fill="currentColor" />,
  pause: <><rect x="6.5" y="5" width="3.5" height="14" rx="1" fill="currentColor" /><rect x="14" y="5" width="3.5" height="14" rx="1" fill="currentColor" /></>,
  volume: <><path d="M4 9.5h3.5L12 6v12l-4.5-3.5H4z" fill="currentColor" /><path d="M15.5 9a4 4 0 0 1 0 6M18 6.5a7.5 7.5 0 0 1 0 11" /></>,
  mute: <><path d="M4 9.5h3.5L12 6v12l-4.5-3.5H4z" fill="currentColor" /><path d="m16 9.5 5 5M21 9.5l-5 5" /></>,
  search: <><circle cx="11" cy="11" r="6" /><path d="m20 20-4.5-4.5" /></>,
  wallet: <><rect x="3.5" y="6" width="17" height="13" rx="2.5" /><path d="M3.5 9.5h17M16 14h1.5" /></>,
  check: <path d="m5 12.5 4.5 4.5L19 7.5" />,
  flag: <path d="M6 21V4h11l-2 4 2 4H6" />,
  heart: <path d="M12 20s-7-4.4-7-10a4 4 0 0 1 7-2.6A4 4 0 0 1 19 10c0 5.6-7 10-7 10z" />,
  "heart-on": <path d="M12 20s-7-4.4-7-10a4 4 0 0 1 7-2.6A4 4 0 0 1 19 10c0 5.6-7 10-7 10z" fill="currentColor" />,
  // Pick next: a track goes on air for everyone, waves out of a point.
  "on-air": <><circle cx="12" cy="12" r="2" fill="currentColor" /><path d="M8.5 8.5a5 5 0 0 0 0 7M15.5 8.5a5 5 0 0 1 0 7M5.5 5.5a9.2 9.2 0 0 0 0 13M18.5 5.5a9.2 9.2 0 0 1 0 13" /></>,
  calendar: <><rect x="4" y="5.5" width="16" height="14.5" rx="2.5" /><path d="M4 10h16M8.5 3.5v4M15.5 3.5v4" /></>,
  bookmark: <path d="M7 4h10v16l-5-4-5 4z" />,
  "bookmark-on": <path d="M7 4h10v16l-5-4-5 4z" fill="currentColor" />,
} satisfies Record<string, ReactNode>;

export type IconName = keyof typeof PATHS;

export function Icon({ name, size = 18, className = "" }: { readonly name: IconName; readonly size?: number; readonly className?: string }) {
  return (
    <svg
      className={`icon icon-${name}${className ? ` ${className}` : ""}`}
      viewBox="0 0 24 24"
      width={size}
      height={size}
      fill="none"
      stroke="currentColor"
      strokeWidth={1.75}
      strokeLinecap="round"
      strokeLinejoin="round"
      aria-hidden="true"
      focusable="false"
    >
      {PATHS[name]}
    </svg>
  );
}
