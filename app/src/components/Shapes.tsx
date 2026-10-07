// GnoRadio's Bauhaus vocabulary. As functional glyphs, each shape has one meaning:
//   circle   (red)    live, likes
//   square   (yellow) money: tips, support, tickets
//   quarter  (blue)   community, on-chain proof, programming the radio
//   triangle (ink)    new music: publish, albums, playlists
// Anything else (save, report, claim, close…) uses a plain line Icon, never a shape.

export type Glyph = "circle" | "square" | "quarter" | "triangle";

const FILL: Record<Glyph, string> = {
  circle: "var(--red)",
  square: "var(--yellow)",
  quarter: "var(--blue)",
  triangle: "var(--ink)",
};

export function Shape({ g, size = 14, fill }: { readonly g: Glyph; readonly size?: number; readonly fill?: string }) {
  const f = fill ?? FILL[g];
  return (
    <svg width={size} height={size} viewBox="0 0 10 10" aria-hidden="true" className="glyph">
      {g === "circle" && <circle cx="5" cy="5" r="5" fill={f} />}
      {g === "square" && <rect width="10" height="10" fill={f} />}
      {g === "quarter" && <path d="M0 10V0a10 10 0 0 1 10 10z" fill={f} />}
      {g === "triangle" && <path d="M5 0l5 10H0z" fill={f} />}
    </svg>
  );
}
/** Composition is a small Bauhaus poster used for cards and the splash. */
export function Composition({ variant = 0 }: { readonly variant?: number }) {
  const v = variant % 3;
  return (
    <svg className="composition" viewBox="0 0 120 80" preserveAspectRatio="xMidYMid slice" aria-hidden="true">
      <rect width="120" height="80" fill="var(--paper)" />
      {v === 0 && (
        <>
          <path d="M0 80V20a60 60 0 0 1 60 60z" fill="var(--blue)" />
          <rect x="62" y="8" width="30" height="30" fill="var(--yellow)" />
          <circle cx="98" cy="58" r="16" fill="var(--red)" />
          <path d="M40 8l14 26H26z" fill="var(--ink)" />
        </>
      )}
      {v === 1 && (
        <>
          <rect x="0" y="0" width="56" height="80" fill="var(--ink)" />
          <circle cx="56" cy="40" r="22" fill="var(--yellow)" />
          <path d="M120 0v44a44 44 0 0 1-44-44z" fill="var(--red)" />
          <rect x="84" y="56" width="20" height="20" fill="var(--blue)" />
        </>
      )}
      {v === 2 && (
        <>
          <circle cx="30" cy="40" r="26" fill="var(--red)" />
          <path d="M60 80V40a40 40 0 0 1 40 40z" fill="var(--ink)" />
          <rect x="74" y="6" width="38" height="20" fill="var(--blue)" />
          <path d="M104 40l12 22H92z" fill="var(--yellow)" />
        </>
      )}
    </svg>
  );
}
