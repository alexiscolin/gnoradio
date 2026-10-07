import { type Glyph, Shape } from "../components/Shapes";

// One pure glyph per genre: the 4 shapes × the 5 colours give exactly 20, ids 1..20.
const SHAPES: readonly Glyph[] = ["square", "circle", "triangle", "quarter"];
const COLOURS = ["var(--blue)", "var(--yellow)", "var(--red)", "var(--ink)", "var(--stone)"] as const;

function genreGlyph(id: number): { readonly g: Glyph; readonly fill: string } {
  const i = Math.max(0, id - 1);
  return { g: SHAPES[i % 4] ?? "circle", fill: COLOURS[Math.floor(i / 4) % 5] ?? "var(--red)" };
}

/** GenreGlyph draws a genre's shape; muted greys it until hovered or chosen. */
export function GenreGlyph({ id, size = 12, muted = false }: { readonly id: number; readonly size?: number; readonly muted?: boolean }) {
  const { g, fill } = genreGlyph(id);
  return <Shape g={g} size={size} fill={muted ? "var(--tick)" : fill} />;
}
